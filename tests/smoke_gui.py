"""Offscreen GUI smoke test: build window, load log, overlay, drive dashboard."""
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PySide6.QtWidgets import QApplication  # noqa: E402
from openobd.app import MainWindow, load_default_cal  # noqa: E402
from openobd.model import CalTableModel  # noqa: E402

# a synthetic VCM Scanner CSV with a WOT-ish pull
rows = []
mph = 0
for i in range(200):
    rpm = 800 + (i % 40) * 120
    mph = min(90, i * 0.5)
    app_pct = 90 if 40 < i < 120 else 12
    kr = 2.0 if i == 80 else 0.0
    spark = 22 - (6 if i == 80 else 0)
    stft = -3
    ltft = -4
    rows.append(f"{i*0.1:.1f},{rpm},{mph:.1f},{app_pct},{kr},{spark},{stft},{ltft}")

csv = ("[Log Information]\nVehicle,2010 Silverado\n[Channel Information]\n"
       "1,2,3,4,5,6,7,8\n"
       "Time,Engine Speed,Vehicle Speed,Accelerator Pedal,Knock Retard,"
       "Spark Advance,Short Term FT,Long Term FT\n"
       "s,RPM,mph,%,deg,deg,%,%\n"
       "[Channel Data]\n" + "\n".join(rows) + "\n")

log_path = "/tmp/smoke_log.csv"
with open(log_path, "w") as fh:
    fh.write(csv)

app = QApplication(sys.argv)
cal, path = load_default_cal()
win = MainWindow(cal, path)
win.show()

# select the Normal shift table
win._select_table("WOT Shift Speed — Normal")
assert win.current_model is not None
print("editor model rows/cols:", win.current_model.rowCount(), win.current_model.columnCount())

# load the synthetic log through the real code path
with open(log_path) as fh:
    from openobd.logbin import parse_csv
    win.log = parse_csv(fh.read(), source="smoke_log.csv")
win._render_report()
win._refresh_channel_combos()
print("mapped channels:", win.log.canonical_keys())

# apply a count overlay with x=vss
i = win.x_ch.findText("vss"); win.x_ch.setCurrentIndex(i)
win.overlay_mode.setCurrentIndex(1)  # Log count
win._apply_overlay()
ov = win.current_model.overlay
assert ov is not None, "overlay not applied"
print("overlay total binned:", ov.total_binned, "hottest cell:", ov.hottest_cell())

# mean overlay with value=knock_retard
win.v_ch.setCurrentIndex(win.v_ch.findText("knock_retard"))
win.overlay_mode.setCurrentIndex(2)
win._apply_overlay()
print("mean overlay applied, mode:", win.current_model.overlay_mode)

# dashboard: bind + a few ticks
from openobd.transport import LogReplaySource
win.dashboard.bind_source(LogReplaySource(win.log, speed=50.0))
win.dashboard.start()
for _ in range(5):
    app.processEvents()
    win.dashboard._tick()
vals = {k: g.value for k, g in win.dashboard.gauges.items()}
print("dashboard gauge sample:", {k: v for k, v in vals.items() if v is not None})
win.dashboard.stop()

# scalar edit path
win.cal.scalars[0].value = 4.10
win._set_scalar_row(0, win.cal.scalars[0])

# save round trip
out = "/tmp/smoke_out.cal.json"
win.path = out
win.save_cal()
from openobd.calspec import Calibration
back = Calibration.load(out)
assert len(back.tables) == len(cal.tables)
print("save/load OK, tables:", len(back.tables))

print("SMOKE OK")
