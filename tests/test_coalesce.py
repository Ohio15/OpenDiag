"""Unit tests for openobd.coalesce — merge, provenance, pins, stock derivation."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from openobd.calspec import Axis, Calibration, Scalar, Table
from openobd.coalesce import (
    MergePolicy, Pin, Rule, coalesce, compare, load_reference, stock_view,
)


def mk_table(name, vals, stock=None, category="Transmission", x=None):
    x = x or [float(i) for i in range(len(vals[0]))]
    y = (Axis(label="y", unit="", values=[float(i) for i in range(len(vals))])
         if len(vals) > 1 else None)
    return Table(name=name, x_axis=Axis(label="x", unit="", values=x),
                 y_axis=y,
                 values=[list(r) for r in vals],
                 stock_values=[list(r) for r in stock] if stock else None,
                 category=category)


def mk_refs():
    stock = Calibration(metadata={"base_tune": "stock"})
    stock.scalars.append(Scalar(name="Fan On Temp", value=105.0, unit="C"))
    stock.scalars.append(Scalar(name="Driven Tire Circumference",
                                value=2475.0, unit="mm"))
    stock.tables.append(mk_table("TCC Apply", [[10.0, 20.0]]))
    stock.tables.append(mk_table("VE Main", [[1.0, 2.0], [3.0, 4.0]],
                                 category="Engine"))
    tow = Calibration(metadata={"base_tune": "tow-consensus"})
    tow.tables.append(mk_table("TCC Apply", [[15.0, 25.0]]))
    tow.scalars.append(Scalar(name="Fan On Temp", value=93.0, unit="C"))
    tune24 = Calibration(metadata={"base_tune": "#24"})
    tune24.tables.append(mk_table("Spark High Octane", [[20.0]],
                                  category="Engine"))
    tune24.scalars.append(Scalar(name="Only In 24", value=7.0))
    return {"stock": stock, "tow": tow, "tune24": tune24}


def mk_policy():
    return MergePolicy(
        priority=["stock", "tune24"],
        stock_source="stock",
        rules=[Rule(match="TCC|Fan", source="tow")],
        pins=[Pin(name="Driven Tire Circumference", value=2742.0,
                  reason="35s measured")],
    )


class TestCoalesce(unittest.TestCase):
    def test_rule_routes_to_tow(self):
        m = coalesce(mk_refs(), mk_policy())
        t = m.table("TCC Apply")
        self.assertEqual(t.values, [[15.0, 25.0]])
        self.assertEqual(t.provenance["source"], "tow")
        self.assertTrue(t.provenance["rule"].startswith("rule:"))
        # stock baseline attached from the stock ref for editor diffing
        self.assertEqual(t.stock_values, [[10.0, 20.0]])
        s = m.scalar("Fan On Temp")
        self.assertEqual(s.value, 93.0)
        self.assertEqual(s.provenance["source"], "tow")
        self.assertEqual(s.provenance["candidates"],
                         {"stock": 105.0, "tow": 93.0})
        self.assertEqual(s.stock_value, 105.0)

    def test_priority_default_and_only_source(self):
        m = coalesce(mk_refs(), mk_policy())
        self.assertEqual(m.table("VE Main").provenance["source"], "stock")
        sp = m.table("Spark High Octane")
        self.assertEqual(sp.provenance["source"], "tune24")
        self.assertEqual(m.scalar("Only In 24").provenance["source"],
                         "tune24")

    def test_pin_overrides_everything(self):
        m = coalesce(mk_refs(), mk_policy())
        s = m.scalar("Driven Tire Circumference")
        self.assertEqual(s.value, 2742.0)
        self.assertEqual(s.provenance["source"], "pin")
        self.assertIn("35s measured", s.provenance["rule"])
        # candidate record still shows what stock said
        self.assertEqual(s.provenance["candidates"]["stock"], 2475.0)

    def test_rule_matching_absent_ref_falls_to_priority(self):
        refs = mk_refs()
        del refs["tow"]
        m = coalesce(refs, mk_policy())
        t = m.table("TCC Apply")
        self.assertEqual(t.provenance["source"], "stock")
        self.assertEqual(t.values, [[10.0, 20.0]])

    def test_provenance_round_trips_through_json(self):
        m = coalesce(mk_refs(), mk_policy())
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "m.cal.json")
            m.save(p)
            back = Calibration.load(p)
        self.assertEqual(back.table("TCC Apply").provenance["source"], "tow")
        self.assertEqual(
            back.scalar("Driven Tire Circumference").provenance["source"],
            "pin")
        self.assertEqual(back.validate(), [])

    def test_stock_view_drops_items_without_baseline(self):
        cal = Calibration()
        cal.scalars.append(Scalar(name="A", value=2.0, stock_value=1.0))
        cal.scalars.append(Scalar(name="B", value=3.0))
        cal.tables.append(mk_table("T1", [[9.0]], stock=[[5.0]]))
        cal.tables.append(mk_table("T2", [[9.0]]))
        sv = stock_view(cal)
        self.assertEqual([s.name for s in sv.scalars], ["A"])
        self.assertEqual(sv.scalar("A").value, 1.0)
        self.assertEqual([t.name for t in sv.tables], ["T1"])
        self.assertEqual(sv.table("T1").values, [[5.0]])

    def test_load_reference_stock_of(self):
        cal = Calibration()
        cal.tables.append(mk_table("T1", [[9.0]], stock=[[5.0]]))
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "c.cal.json")
            cal.save(p)
            name, ref = load_reference(f"stk=stock-of:{p}")
        self.assertEqual(name, "stk")
        self.assertEqual(ref.table("T1").values, [[5.0]])

    def test_compare_reports_disagreement(self):
        rep = compare(mk_refs())
        rec = next(r for r in rep
                   if r["kind"] == "scalar" and r["name"] == "Fan On Temp")
        self.assertFalse(rec["agree"])
        tcc = next(r for r in rep
                   if r["kind"] == "table" and r["name"] == "TCC Apply")
        self.assertFalse(tcc["agree"])
        d = tcc["deltas"]["stock vs tow"]
        self.assertEqual(d["n_diff"], 2)
        self.assertEqual(d["max_abs_delta"], 5.0)

    def test_shape_mismatch_recorded_not_fatal(self):
        refs = mk_refs()
        refs["tow"].tables[0] = mk_table("TCC Apply", [[1.0, 2.0, 3.0]])
        m = coalesce(refs, mk_policy())
        t = m.table("TCC Apply")
        self.assertEqual(t.provenance["source"], "tow")
        self.assertEqual(t.provenance["candidates"]["stock"],
                         "shape mismatch")
        # stock baseline must NOT attach across a shape mismatch
        self.assertIsNone(t.stock_values)

    def test_param_id_joins_across_differing_names(self):
        a = Calibration()
        ta = mk_table("WOT Shift Speed - Normal", [[40.0]])
        ta.param_id = 15010
        a.tables.append(ta)
        a.scalars.append(Scalar(name="Tire Circ", value=2475.0,
                                param_id=9056))
        b = Calibration()
        tb = mk_table("WOT Shift Speed vs. Shift - Normal", [[45.0]])
        tb.param_id = 15010
        b.tables.append(tb)
        b.scalars.append(Scalar(name="Non-Driven Tire Circumference",
                                value=2742.0, param_id=9056))
        pol = MergePolicy(priority=["a", "b"])
        m = coalesce({"a": a, "b": b}, pol)
        # one merged table / one merged scalar, not two of each
        self.assertEqual(len(m.tables), 1)
        self.assertEqual(len(m.scalars), 1)
        self.assertEqual(m.tables[0].values, [[40.0]])
        self.assertEqual(m.tables[0].provenance["candidates"]["b"]["n_diff"],
                         1)
        self.assertEqual(m.scalars[0].provenance["candidates"],
                         {"a": 2475.0, "b": 2742.0})

    def test_policy_json_round_trip(self):
        pol = mk_policy()
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "pol.json")
            with open(p, "w", encoding="utf-8") as fh:
                json.dump(pol.to_dict(), fh)
            back = MergePolicy.load(p)
        self.assertEqual(back.priority, pol.priority)
        self.assertEqual(back.rules[0].match, "TCC|Fan")
        self.assertEqual(back.pins[0].value, 2742.0)
        self.assertEqual(back.stock_source, "stock")

class TestCompareRefCli(unittest.TestCase):
    def test_compare_ref_excluded_from_merge_included_in_report(self):
        from openobd.coalesce import main
        a = Calibration()
        a.scalars.append(Scalar(name="Shared", value=1.0, param_id=100))
        tow = Calibration()
        tow.scalars.append(Scalar(name="Shared", value=2.0, param_id=100))
        tow.scalars.append(Scalar(name="TowOnly", value=9.0, param_id=999))
        pol = MergePolicy(priority=["a"])
        with tempfile.TemporaryDirectory() as td:
            pa = os.path.join(td, "a.cal.json"); a.save(pa)
            pt = os.path.join(td, "tow.cal.json"); tow.save(pt)
            pp = os.path.join(td, "pol.json")
            with open(pp, "w", encoding="utf-8") as fh:
                json.dump(pol.to_dict(), fh)
            po = os.path.join(td, "out.cal.json")
            pc = os.path.join(td, "cmp.json")
            rc = main(["--ref", f"a={pa}", "--compare-ref", f"tow={pt}",
                       "--policy", pp, "--out", po, "--compare-out", pc])
            self.assertEqual(rc, 0)
            merged = Calibration.load(po)
            # tow-only parameter must NOT leak into the merge
            self.assertEqual([s.name for s in merged.scalars], ["Shared"])
            self.assertEqual(merged.scalars[0].value, 1.0)
            with open(pc, encoding="utf-8") as fh:
                rep = json.load(fh)
            keys = {r["key"]: r for r in rep}
            # but it MUST appear in the comparison report, and the shared
            # parameter's report must carry both sources
            self.assertIn("pid:999", keys)
            self.assertEqual(set(keys["pid:100"]["sources"]), {"a", "tow"})


if __name__ == "__main__":
    unittest.main()
