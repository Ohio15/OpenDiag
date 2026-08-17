# OpenOBD — calibration viewer/editor + log overlay for truck-mcp

An HP-Tuners-style desktop app for the **2010 Silverado 1500 5.3 (E38 ECM /
T43 TCM, 6L80)** calibration work. It renders the harvested calibration values
as editable, heatmapped tables; overlays captured logs onto tables; analyzes a
log's trims / knock / shift points; and drives a live gauge dashboard.

It is the **UI layer of the truck-mcp own-app suite** — it reads the same
calibration model the `wot_analyzer` / `hpl_bridge` modules produce, and its
dashboard reads from the same transport seam `gt.py` (the OBDX Pro GT port)
will implement. No vendor software, no subscriptions, no `.hpt` encryption.

## What it is (and isn't)

* **Is:** a viewer/editor over *our own* calibration format (`.cal.json`) —
  values transcribed byte-precisely from the `#24` change sheet (both stock and
  new), plus a log-analysis engine that codifies the 8.8.26 baseline logic.
* **Is:** editable — cells save to `.cal.json` / export to CSV, so you can plan
  changes visually now.
* **Is NOT:** a flasher. It never writes an encrypted `.hpt`. Turning a
  `.cal.json` back into a flashable tune stays behind the gated Phase 3/4 path
  in the GT swivel spec. The tables here are for *planning and analysis*.

## Install & run (dev)

```bash
cd OpenOBD
python -m pip install -r requirements.txt
python -m openobd            # opens on the seeded 2010 Silverado #24 cal
# or: python run.py path/to/other.cal.json
```

Regenerate the seed calibration from the change-sheet source:

```bash
python -m openobd.seed_2010_silverado    # -> data/2010_silverado_24.cal.json
```

Run the tests:

```bash
python -m pytest tests/ -q                # headless core (calspec + logbin)
QT_QPA_PLATFORM=offscreen python tests/smoke_gui.py   # GUI smoke
```

## Build the Windows exe

On the Windows box, from the repo root:

```bash
python -m pip install -r requirements.txt
pyinstaller openobd.spec
# -> dist/openobd.exe   (single file, windowed, seed bundled)
```

## The four tabs

**Editor** — pick a table from the left tree; edit heatmapped cells in place.
Changed-vs-stock cells are bold, and each cell's tooltip shows stock + Δ.
"Revert cell → stock" undoes one cell. The **overlay** dropdown drops a loaded
log onto the grid (operation-count histogram, or mean of a chosen value
channel). *Overlays are meant for RPM×load breakpoint tables* (VE, spark) which
arrive with the Phase 3 calibration dump — for the shift **setpoint** tables the
meaningful log view is the observed-shift report (below), not a cell overlay.

**Scalars** — final drive ratios, tire circumferences, DoD flag: editable, with
stock + Δ and the HPT parameter-ID breadcrumb.

**Log Analysis** — load a VCM Scanner CSV export (Log File → Export Log File →
CSV) or a plain CSV. Reports regime trims (idle/cruise/PE), knock events (real
KR channel, or a timing-collapse heuristic when KR isn't logged), fuel-pressure
sag, and **observed shift points** (from a `gear` channel, or inferred from RPM
drops) so you can compare real WOT shifts to the setpoint tables.

**Dashboard** — a gauge cluster with rolling sparklines. Today it's fed by a
`LogReplaySource` (replays a loaded log as if live). When `gt.py` lands, a
`GtDataSource` implementing the same `DataSource` interface drops in unchanged.

## Architecture

```
openobd/
  calspec.py     data model: Calibration / Table / Axis / Scalar + .cal.json I/O   [stdlib only]
  logbin.py      log parse (VCM Scanner + plain CSV), channel mapping,
                 table binning (overlay), regime/knock analysis, shift detection   [stdlib only]
  transport.py   DataSource seam: LogReplaySource now, GtDataSource stub for gt.py [stdlib only]
  seed_2010_silverado.py   builds the #24 seed calibration from the change sheet
  model.py       Qt table model + heatmap delegate                                 [PySide6]
  app.py         main window / tabs / file ops                                     [PySide6]
data/            the seed .cal.json
tests/           headless unit tests + offscreen GUI smoke
```

The `calspec` / `logbin` / `transport` core is **pure stdlib** — importable by
truck-mcp's CLI tools and fully unit-tested without Qt. Only `model.py` /
`app.py` pull in PySide6.

## How this folds into truck-mcp

* `logbin.analyze_log` / `detect_shift_points` / `bin_log_to_table` are the
  concrete `wot_analyzer` the GT spec calls for — reuse them from the CLI.
* `transport.DataSource` is the dashboard side of the `ElmTransport` seam;
  `gt.py`'s live source implements `channels()/latest()/start()/stop()`.
* `.cal.json` is the interchange format between this editor and any future
  read/flash path — a Phase 3 calibration read populates the *real* breakpoint
  tables (VE, spark, torque) into the same model, and the overlays light up.

## Provenance

Seed values transcribed from `24-claudes-edit-change-sheet.md`, verified in VCM
Editor via Compare → Comparison Log against `DO NOT CHANGE - 2010 Silverado
Stock - 10.13.24.hpt`. Vehicle: VIN 3GCRKTE35AG150432, E38 OS 12636005 / T43 OS
24254909, 4.11 gears, 35" tires, AFM disabled, E10 fuel.
