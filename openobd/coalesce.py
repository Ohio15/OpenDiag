"""
coalesce — merge N reference calibrations into one "best" calibration.

Given an ordered set of named reference Calibrations (e.g. stock, tune24,
tow_community), a MergePolicy decides, per parameter, which reference supplies
the value. Every merged Scalar/Table carries a `provenance` dict recording
which source won, which rule picked it, and what every other reference said —
so the merged file is auditable cell-for-cell, not a mystery blend.

Merge granularity
-----------------
* Scalars merge per-scalar.
* Tables merge whole-table: mixing cells from different calibrations inside
  one physical table produces combinations no calibrator ever validated, so a
  table comes wholesale from exactly one source. The per-cell COMPARISON
  across all sources is still computed and recorded in provenance
  (n_diff / max_abs_delta per other source) so a human can audit the choice.
* Pins are explicit value overrides (verified hardware facts: tire
  circumference, final drive, AFM delete). A pin outranks every reference and
  records its reason.

Policy file (JSON)
------------------
{
  "priority": ["stock", "tune24"],          // default source order
  "stock_source": "stock",                  // ref whose values become the
                                            // merged file's stock_values
  "rules": [                                // first match wins
    {"match": "TCC|Shift Speed", "on": "name",     "source": "tow"},
    {"match": "^Transmission",   "on": "category", "source": "tune24"}
  ],
  "pins": [
    {"name": "Driven Tire Circumference", "value": 2742.0,
     "reason": "35x12.50R18 Kenda Klever MT measured circumference"}
  ]
}

Pure stdlib, headless, unit-testable — same contract as calspec.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from typing import Any, Optional

from .calspec import Axis, Calibration, Scalar, Table


# --------------------------------------------------------------------------- #
# Policy
# --------------------------------------------------------------------------- #
@dataclass
class Rule:
    match: str                    # regex
    source: str                   # reference name that supplies the value
    on: str = "name"              # "name" | "category"
    note: str = ""

    def matches(self, name: str, category: str) -> bool:
        hay = name if self.on == "name" else category
        return re.search(self.match, hay, re.IGNORECASE) is not None


@dataclass
class Pin:
    name: str                     # exact scalar name
    value: float
    reason: str = ""


@dataclass
class MergePolicy:
    priority: list[str] = field(default_factory=list)
    rules: list[Rule] = field(default_factory=list)
    pins: list[Pin] = field(default_factory=list)
    stock_source: Optional[str] = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "MergePolicy":
        return cls(
            priority=list(d.get("priority", [])),
            rules=[Rule(**r) for r in d.get("rules", [])],
            pins=[Pin(**p) for p in d.get("pins", [])],
            stock_source=d.get("stock_source"),
        )

    @classmethod
    def load(cls, path: str) -> "MergePolicy":
        with open(path, "r", encoding="utf-8") as fh:
            return cls.from_dict(json.load(fh))

    def to_dict(self) -> dict[str, Any]:
        return {
            "priority": self.priority,
            "stock_source": self.stock_source,
            "rules": [vars(r) for r in self.rules],
            "pins": [vars(p) for p in self.pins],
        }


# --------------------------------------------------------------------------- #
# Reference loading helpers
# --------------------------------------------------------------------------- #
def stock_view(cal: Calibration) -> Calibration:
    """
    Derive a stock-only Calibration from a cal that carries stock baselines
    alongside current values (the harvest format). Items without a stock
    baseline are DROPPED — absent is absent, never faked from current values.
    """
    out = Calibration(metadata=dict(cal.metadata))
    out.metadata["derived"] = "stock_view: stock_values/stock_value only"
    for s in cal.scalars:
        if s.stock_value is not None:
            out.scalars.append(Scalar(
                name=s.name, value=s.stock_value, unit=s.unit,
                stock_value=s.stock_value, param_id=s.param_id,
                category=s.category, note=s.note,
            ))
    for t in cal.tables:
        if t.stock_values is not None:
            out.tables.append(Table(
                name=t.name, x_axis=t.x_axis, y_axis=t.y_axis,
                values=[list(r) for r in t.stock_values],
                stock_values=[list(r) for r in t.stock_values],
                unit=t.unit, param_id=t.param_id,
                category=t.category, note=t.note,
            ))
    return out


def load_reference(spec: str) -> tuple[str, Calibration]:
    """
    Parse a CLI reference spec: "name=path" loads path as-is;
    "name=stock-of:path" loads path and takes only its stock baselines.
    """
    name, _, path = spec.partition("=")
    if not path:
        raise ValueError(f"reference spec needs name=path, got: {spec!r}")
    if path.startswith("stock-of:"):
        return name, stock_view(Calibration.load(path[len("stock-of:"):]))
    return name, Calibration.load(path)


# --------------------------------------------------------------------------- #
# Cross-reference identity
# --------------------------------------------------------------------------- #
# The same physical parameter can carry different display names in different
# harvests ("WOT Shift Speed – Normal" vs "WOT Shift Speed vs. Shift -
# Normal"), but the HPT ParameterID is stable. Join on param_id when present,
# on name otherwise.
def _key(item) -> str:
    return f"pid:{item.param_id}" if item.param_id is not None \
        else f"name:{item.name}"


def _index_scalars(cal: Calibration) -> dict[str, Scalar]:
    return {_key(s): s for s in cal.scalars}


def _index_tables(cal: Calibration) -> dict[str, Table]:
    return {_key(t): t for t in cal.tables}


def _union_keys(indexes: list[dict[str, Any]]) -> list[str]:
    out: list[str] = []
    for ix in indexes:
        for k in ix:
            if k not in out:
                out.append(k)
    return out


# --------------------------------------------------------------------------- #
# Comparison
# --------------------------------------------------------------------------- #
def _table_delta(a: Table, b: Table) -> Optional[dict[str, Any]]:
    """Per-cell delta summary between two same-named tables, None if shapes differ."""
    if a.n_rows != b.n_rows or a.n_cols != b.n_cols:
        return None
    n_diff = 0
    max_abs = 0.0
    for ra, rb in zip(a.values, b.values):
        for va, vb in zip(ra, rb):
            if va != vb:
                n_diff += 1
                max_abs = max(max_abs, abs(va - vb))
    return {"n_diff": n_diff, "max_abs_delta": max_abs,
            "n_cells": a.n_rows * a.n_cols}


def compare(refs: dict[str, Calibration]) -> list[dict[str, Any]]:
    """
    Per-parameter comparison across all references. One record per distinct
    parameter name: which refs have it, and how they differ.
    """
    out: list[dict[str, Any]] = []
    six = {rn: _index_scalars(cal) for rn, cal in refs.items()}
    for k in _union_keys(list(six.values())):
        have = {rn: ix[k] for rn, ix in six.items() if k in ix}
        vals = {rn: s.value for rn, s in have.items()}
        out.append({"kind": "scalar", "key": k,
                    "name": next(iter(have.values())).name,
                    "sources": list(have), "values": vals,
                    "agree": len(set(vals.values())) <= 1})
    tix = {rn: _index_tables(cal) for rn, cal in refs.items()}
    for k in _union_keys(list(tix.values())):
        have = {rn: ix[k] for rn, ix in tix.items() if k in ix}
        rec: dict[str, Any] = {"kind": "table", "key": k,
                               "name": next(iter(have.values())).name,
                               "sources": list(have)}
        rns = list(have)
        deltas = {}
        for other in rns[1:]:
            d = _table_delta(have[rns[0]], have[other])
            deltas[f"{rns[0]} vs {other}"] = d if d else "shape mismatch"
        rec["deltas"] = deltas
        rec["agree"] = all(
            isinstance(d, dict) and d["n_diff"] == 0 for d in deltas.values()
        ) if deltas else True
        out.append(rec)
    return out


# --------------------------------------------------------------------------- #
# Coalesce
# --------------------------------------------------------------------------- #
def _pick_source(name: str, category: str, present_in: list[str],
                 policy: MergePolicy) -> tuple[Optional[str], str]:
    """Return (winning source, rule description) or (None, reason)."""
    for r in policy.rules:
        if r.matches(name, category):
            if r.source in present_in:
                return r.source, f"rule:{r.match}->{r.source}"
            # rule matched but that ref doesn't carry the parameter —
            # fall through to priority so the parameter isn't lost.
            break
    for src in policy.priority:
        if src in present_in:
            return src, f"priority:{src}"
    if present_in:
        return present_in[0], f"only-source:{present_in[0]}"
    return None, "absent-everywhere"


def coalesce(refs: dict[str, Calibration], policy: MergePolicy,
             metadata: Optional[dict[str, Any]] = None) -> Calibration:
    """
    Merge references into one Calibration under the policy. `refs` order is
    the fallback order when policy.priority doesn't decide.
    """
    merged = Calibration(metadata=dict(metadata or {}))
    merged.metadata["coalesced_from"] = {
        rn: {"source": cal.metadata.get("source", ""),
             "base_tune": cal.metadata.get("base_tune", ""),
             "n_tables": len(cal.tables), "n_scalars": len(cal.scalars)}
        for rn, cal in refs.items()
    }
    merged.metadata["merge_policy"] = policy.to_dict()

    pins = {p.name: p for p in policy.pins}
    stock_ref = refs.get(policy.stock_source) if policy.stock_source else None

    six = {rn: _index_scalars(cal) for rn, cal in refs.items()}
    stock_six = _index_scalars(stock_ref) if stock_ref is not None else {}
    tix = {rn: _index_tables(cal) for rn, cal in refs.items()}
    stock_tix = _index_tables(stock_ref) if stock_ref is not None else {}

    # ---- scalars ---------------------------------------------------------- #
    for k in _union_keys(list(six.values())):
        have = {rn: ix[k] for rn, ix in six.items() if k in ix}
        base0 = next(iter(have.values()))
        src, why = _pick_source(base0.name, base0.category,
                                list(have), policy)
        base = have[src]
        # a pin matches if ANY reference knows this parameter by the pinned
        # name (display names differ across harvests; the pin is the intent)
        pin = next((pins[s.name] for s in have.values()
                    if s.name in pins), None)
        value = pin.value if pin else base.value
        stock = None
        if k in stock_six:
            stock = stock_six[k].value
        elif base.stock_value is not None:
            stock = base.stock_value
        prov = {
            "source": ("pin" if pin else src),
            "rule": (f"pin:{pin.reason}" if pin else why),
            "candidates": {rn: s.value for rn, s in have.items()},
        }
        merged.scalars.append(Scalar(
            name=base.name, value=value, unit=base.unit, stock_value=stock,
            param_id=base.param_id, category=base.category,
            note=(f"{base.note} " if base.note else "")
                 + f"[coalesced: {prov['source']}]",
            provenance=prov,
        ))

    # ---- tables ----------------------------------------------------------- #
    for k in _union_keys(list(tix.values())):
        have = {rn: ix[k] for rn, ix in tix.items() if k in ix}
        base0 = next(iter(have.values()))
        src, why = _pick_source(base0.name, base0.category,
                                list(have), policy)
        base = have[src]
        deltas = {}
        for rn, t in have.items():
            if rn == src:
                continue
            d = _table_delta(base, t)
            deltas[rn] = d if d else "shape mismatch"
        stock_vals = None
        st = stock_tix.get(k)
        if st is not None and _table_delta(base, st) is not None:
            stock_vals = [list(r) for r in st.values]
        if stock_vals is None and base.stock_values is not None:
            stock_vals = [list(r) for r in base.stock_values]
        prov = {"source": src, "rule": why, "candidates": deltas}
        merged.tables.append(Table(
            name=base.name, x_axis=base.x_axis, y_axis=base.y_axis,
            values=[list(r) for r in base.values], stock_values=stock_vals,
            unit=base.unit, param_id=base.param_id, category=base.category,
            note=(f"{base.note} " if base.note else "")
                 + f"[coalesced: {src}]",
            provenance=prov,
        ))
    return merged


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m openobd.coalesce",
        description="Merge N reference .cal.json files into one best cal "
                    "with per-parameter provenance.")
    ap.add_argument("--ref", action="append", required=True,
                    metavar="NAME=PATH",
                    help="reference cal (repeatable, order = fallback "
                         "priority). NAME=stock-of:PATH takes only the stock "
                         "baselines out of PATH.")
    ap.add_argument("--policy", required=True, help="merge policy JSON")
    ap.add_argument("--out", required=True, help="output .cal.json")
    ap.add_argument("--compare-out", default=None,
                    help="also write the full comparison report JSON here")
    ap.add_argument("--compare-ref", action="append", default=[],
                    metavar="NAME=PATH",
                    help="reference included in the comparison report but "
                         "NEVER in the merge (e.g. tow references from a "
                         "different vehicle: strategies to compare against, "
                         "not cell values to adopt).")
    a = ap.parse_args(argv)

    refs: dict[str, Calibration] = {}
    for spec in a.ref:
        name, cal = load_reference(spec)
        refs[name] = cal
        print(f"ref {name}: {len(cal.tables)} tables, "
              f"{len(cal.scalars)} scalars")
    crefs: dict[str, Calibration] = {}
    for spec in a.compare_ref:
        name, cal = load_reference(spec)
        crefs[name] = cal
        print(f"compare-ref {name}: {len(cal.tables)} tables, "
              f"{len(cal.scalars)} scalars (comparison only)")
    policy = MergePolicy.load(a.policy)
    merged = coalesce(refs, policy)
    errs = merged.validate()
    if errs:
        print(f"VALIDATION ERRORS ({len(errs)}):")
        for e in errs[:20]:
            print("  ", e)
        return 1
    merged.save(a.out)
    n_pin = sum(1 for s in merged.scalars
                if s.provenance and s.provenance["source"] == "pin")
    srcs: dict[str, int] = {}
    for item in [*merged.scalars, *merged.tables]:
        k = item.provenance["source"] if item.provenance else "?"
        srcs[k] = srcs.get(k, 0) + 1
    print(f"wrote {a.out}: {len(merged.tables)} tables, "
          f"{len(merged.scalars)} scalars (pins: {n_pin})")
    print(f"  by source: {srcs}")
    if a.compare_out:
        with open(a.compare_out, "w", encoding="utf-8") as fh:
            json.dump(compare({**refs, **crefs}), fh, indent=2)
        print(f"wrote comparison report: {a.compare_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
