"""
calspec — the truck-mcp calibration data model.

This is the shared spine between the GUI viewer/editor and the truck-mcp
analysis pipeline (wot_analyzer, hpl_bridge). It is deliberately pure-stdlib
so it can be imported by headless CLI tools and unit-tested without Qt.

A calibration (.cal.json) is a versioned document describing:
  - metadata (vehicle, base tune, provenance)
  - scalars   (single-value parameters: final drive ratio, tire circ, ...)
  - tables    (N-D grids with real, labeled axes: WOT shift speeds, VE, spark)

Design notes
------------
* Values are stored exactly as we know them (e.g. the #24 change sheet), with
  the STOCK value carried alongside the CURRENT value so the editor can show a
  live diff and "revert cell" without a second file.
* Axes carry unit + label so the log-binning engine can drop a log sample into
  the correct cell purely from the axis definitions (the HP Tuners overlay).
* No encryption, no .hpt. This is OUR format. Writing a real .hpt stays behind
  the gated Phase 3/4 flash path. Export here means JSON/CSV only.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from typing import Any, Optional

SCHEMA_VERSION = 1


# --------------------------------------------------------------------------- #
# Axes
# --------------------------------------------------------------------------- #
@dataclass
class Axis:
    """A single table axis: an ordered list of breakpoints with a unit."""
    label: str                      # e.g. "Gear change" / "Trans temp"
    unit: str                       # e.g. "RPM", "mph", "°F", "" (index)
    values: list[float]             # breakpoints, ascending or as-calibrated

    def __len__(self) -> int:
        return len(self.values)

    def index_of(self, sample: float) -> Optional[int]:
        """
        Return the axis cell index a live sample falls into (nearest-lower
        breakpoint, HP-Tuners style: a sample maps to the cell whose breakpoint
        is the greatest one <= sample). Returns None if below the first bp.
        For a single-cell axis, everything maps to 0.
        """
        vals = self.values
        if not vals:
            return None
        if len(vals) == 1:
            return 0
        ascending = vals[-1] >= vals[0]
        v = list(vals) if ascending else list(reversed(vals))
        if sample < v[0]:
            # clamp to first cell rather than dropping the sample; logbin can
            # choose to treat clamped samples separately if it wants.
            idx = 0
        else:
            idx = 0
            for i, bp in enumerate(v):
                if sample >= bp:
                    idx = i
                else:
                    break
        return idx if ascending else (len(vals) - 1 - idx)


# --------------------------------------------------------------------------- #
# Scalars
# --------------------------------------------------------------------------- #
@dataclass
class Scalar:
    """A single-value calibration parameter."""
    name: str
    value: float
    unit: str = ""
    stock_value: Optional[float] = None
    param_id: Optional[int] = None          # HPT ParameterID breadcrumb
    category: str = ""
    note: str = ""
    provenance: Optional[dict] = None       # coalesce: {source, rule, candidates}

    @property
    def changed(self) -> bool:
        return self.stock_value is not None and self.value != self.stock_value


# --------------------------------------------------------------------------- #
# Tables
# --------------------------------------------------------------------------- #
@dataclass
class Table:
    """
    An N-D calibration table. We support 1-D (x only) and 2-D (y rows, x cols).
    values is indexed values[row][col] == values[y_index][x_index].
    A 1-D table uses a single row: values == [[...]].
    """
    name: str
    x_axis: Axis
    values: list[list[float]]
    unit: str = ""                          # unit of the cell values
    y_axis: Optional[Axis] = None
    stock_values: Optional[list[list[float]]] = None
    param_id: Optional[int] = None
    category: str = ""
    note: str = ""
    provenance: Optional[dict] = None       # coalesce: {source, rule, candidates}

    # -- shape helpers ----------------------------------------------------- #
    @property
    def n_cols(self) -> int:
        return len(self.x_axis)

    @property
    def n_rows(self) -> int:
        return len(self.y_axis) if self.y_axis else 1

    def validate(self) -> list[str]:
        """Return a list of structural problems (empty == valid)."""
        errs: list[str] = []
        if len(self.values) != self.n_rows:
            errs.append(
                f"{self.name}: {len(self.values)} value rows != {self.n_rows} "
                f"y breakpoints"
            )
        for r, row in enumerate(self.values):
            if len(row) != self.n_cols:
                errs.append(
                    f"{self.name}: row {r} has {len(row)} cells != "
                    f"{self.n_cols} x breakpoints"
                )
        if self.stock_values is not None:
            if len(self.stock_values) != len(self.values) or any(
                len(a) != len(b)
                for a, b in zip(self.stock_values, self.values)
            ):
                errs.append(f"{self.name}: stock_values shape != values shape")
        return errs

    def cell_changed(self, r: int, c: int) -> bool:
        if self.stock_values is None:
            return False
        try:
            return self.values[r][c] != self.stock_values[r][c]
        except IndexError:
            return False

    def flat(self) -> list[float]:
        return [v for row in self.values for v in row]

    def vmin_vmax(self) -> tuple[float, float]:
        vals = self.flat()
        return (min(vals), max(vals)) if vals else (0.0, 0.0)


# --------------------------------------------------------------------------- #
# Calibration document
# --------------------------------------------------------------------------- #
@dataclass
class Calibration:
    metadata: dict[str, Any] = field(default_factory=dict)
    scalars: list[Scalar] = field(default_factory=list)
    tables: list[Table] = field(default_factory=list)
    schema_version: int = SCHEMA_VERSION

    # -- lookup ------------------------------------------------------------ #
    def table(self, name: str) -> Optional[Table]:
        for t in self.tables:
            if t.name == name:
                return t
        return None

    def scalar(self, name: str) -> Optional[Scalar]:
        for s in self.scalars:
            if s.name == name:
                return s
        return None

    def validate(self) -> list[str]:
        errs: list[str] = []
        for t in self.tables:
            errs.extend(t.validate())
        return errs

    # -- (de)serialization ------------------------------------------------- #
    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "metadata": self.metadata,
            "scalars": [asdict(s) for s in self.scalars],
            "tables": [_table_to_dict(t) for t in self.tables],
        }

    def to_json(self, indent: int = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent)

    def save(self, path: str, indent: int = 2) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(self.to_json(indent=indent))

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Calibration":
        scalars = [Scalar(**s) for s in d.get("scalars", [])]
        tables = [_table_from_dict(t) for t in d.get("tables", [])]
        return cls(
            metadata=d.get("metadata", {}),
            scalars=scalars,
            tables=tables,
            schema_version=d.get("schema_version", SCHEMA_VERSION),
        )

    @classmethod
    def load(cls, path: str) -> "Calibration":
        with open(path, "r", encoding="utf-8") as fh:
            return cls.from_dict(json.load(fh))


# --------------------------------------------------------------------------- #
# dict <-> Table (Axis is nested, so asdict/`**` need help)
# --------------------------------------------------------------------------- #
def _axis_to_dict(a: Axis) -> dict[str, Any]:
    return {"label": a.label, "unit": a.unit, "values": list(a.values)}


def _axis_from_dict(d: dict[str, Any]) -> Axis:
    return Axis(label=d["label"], unit=d.get("unit", ""), values=list(d["values"]))


def _table_to_dict(t: Table) -> dict[str, Any]:
    return {
        "name": t.name,
        "unit": t.unit,
        "category": t.category,
        "param_id": t.param_id,
        "note": t.note,
        "x_axis": _axis_to_dict(t.x_axis),
        "y_axis": _axis_to_dict(t.y_axis) if t.y_axis else None,
        "values": [list(r) for r in t.values],
        "stock_values": (
            [list(r) for r in t.stock_values]
            if t.stock_values is not None else None
        ),
        "provenance": t.provenance,
    }


def _table_from_dict(d: dict[str, Any]) -> Table:
    return Table(
        name=d["name"],
        unit=d.get("unit", ""),
        category=d.get("category", ""),
        param_id=d.get("param_id"),
        note=d.get("note", ""),
        x_axis=_axis_from_dict(d["x_axis"]),
        y_axis=_axis_from_dict(d["y_axis"]) if d.get("y_axis") else None,
        values=[list(r) for r in d["values"]],
        stock_values=(
            [list(r) for r in d["stock_values"]]
            if d.get("stock_values") is not None else None
        ),
        provenance=d.get("provenance"),
    )
