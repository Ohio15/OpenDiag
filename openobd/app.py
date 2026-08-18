"""
OpenOBD GUI — HP-Tuners-style calibration viewer/editor + log overlay +
live/replay dashboard, for truck-mcp.

Tabs
----
  Editor      : tree of tables (by category) -> editable heatmapped grid with
                stock diff + optional log overlay (operation-count / mean-value).
  Scalars     : editable list of single-value parameters with stock diff.
  Log         : load a VCM Scanner CSV / plain CSV, see the regime report, and
                push a table overlay from any two channels.
  Dashboard   : gauges fed by a DataSource — LogReplaySource today, GtDataSource
                when the OBDX Pro GT transport (gt.py) is wired.

Run:  python -m openobd.app  [optional path to a .cal.json]
"""
from __future__ import annotations

import os
import sys
from collections import deque
from typing import Optional

from PySide6.QtCore import Qt, QTimer, QPointF
from PySide6.QtGui import QAction, QColor, QPainter, QPen, QPolygonF, QFont
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
    QTreeWidget, QTreeWidgetItem, QTableView, QTabWidget, QSplitter, QLabel,
    QComboBox, QCheckBox, QPushButton, QFileDialog, QTextEdit, QTableWidget,
    QTableWidgetItem, QHeaderView, QMessageBox, QGroupBox,
)

from .calspec import Calibration
from .logbin import (
    Log, Overlay, parse_csv, analyze_log, bin_log_to_table, detect_shift_points,
    CANONICAL,
)
from .model import CalTableModel, HeatmapDelegate
from .transport import DataSource, LogReplaySource, GtDataSource, Sample

# Friendly gauge specs: canonical key -> (label, unit, min, max)
GAUGE_SPECS = [
    ("rpm", "Engine Speed", "RPM", 0, 6500),
    ("vss", "Vehicle Speed", "mph", 0, 120),
    ("map", "MAP", "kPa", 0, 105),
    ("tps", "Throttle", "%", 0, 100),
    ("app", "Pedal", "%", 0, 100),
    ("spark", "Spark Adv", "°", -10, 45),
    ("knock_retard", "Knock Retard", "°", 0, 15),
    ("ect", "Coolant", "°F", 0, 260),
    ("iat", "Intake Air", "°F", 0, 200),
    ("tft", "Trans Temp", "°F", 0, 300),
    ("stft", "STFT", "%", -25, 25),
    ("ltft", "LTFT", "%", -25, 25),
    ("fuel_press", "Fuel Press", "psi", 0, 75),
    ("voltage", "Voltage", "V", 10, 15),
    ("gear", "Gear", "", 0, 6),
    ("ethanol", "Ethanol", "%", 0, 100),
]


# --------------------------------------------------------------------------- #
# A self-contained gauge: label, value, bar, rolling sparkline. No deps.
# --------------------------------------------------------------------------- #
class Gauge(QWidget):
    def __init__(self, key, label, unit, vmin, vmax):
        super().__init__()
        self.key = key
        self.label = label
        self.unit = unit
        self.vmin = float(vmin)
        self.vmax = float(vmax)
        self.value: Optional[float] = None
        self.history: deque = deque(maxlen=120)
        self.setMinimumSize(190, 90)

    def set_value(self, v: Optional[float]):
        self.value = v
        if v is not None:
            self.history.append(v)
        self.update()

    def _frac(self, v: float) -> float:
        span = (self.vmax - self.vmin) or 1.0
        return max(0.0, min(1.0, (v - self.vmin) / span))

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        p.fillRect(0, 0, w, h, QColor(28, 30, 34))
        p.setPen(QColor(70, 74, 80))
        p.drawRect(0, 0, w - 1, h - 1)

        # label
        p.setPen(QColor(150, 200, 255))
        f = QFont(); f.setPointSize(8); p.setFont(f)
        p.drawText(8, 16, self.label)

        # value
        p.setPen(QColor(240, 240, 240))
        fv = QFont(); fv.setPointSize(16); fv.setBold(True); p.setFont(fv)
        txt = "—" if self.value is None else f"{self.value:g}"
        p.drawText(8, 44, txt)
        p.setPen(QColor(160, 160, 160))
        fu = QFont(); fu.setPointSize(8); p.setFont(fu)
        p.drawText(8 + p.fontMetrics().horizontalAdvance(txt) + 40, 44, self.unit)

        # bar
        bar_y = h - 26
        p.fillRect(8, bar_y, w - 16, 6, QColor(50, 54, 60))
        if self.value is not None:
            frac = self._frac(self.value)
            col = QColor(80, 190, 120)
            if self.key == "knock_retard" and self.value >= 1:
                col = QColor(220, 70, 60)
            elif self.key in ("stft", "ltft") and abs(self.value) > 10:
                col = QColor(230, 180, 50)
            p.fillRect(8, bar_y, int((w - 16) * frac), 6, col)

        # sparkline
        if len(self.history) >= 2:
            spark_top = 50
            spark_h = bar_y - spark_top - 4
            lo = min(self.history); hi = max(self.history)
            span = (hi - lo) or 1.0
            pts = QPolygonF()
            n = len(self.history)
            for i, val in enumerate(self.history):
                x = 8 + (w - 16) * (i / (n - 1))
                y = spark_top + spark_h * (1 - (val - lo) / span)
                pts.append(QPointF(x, y))
            p.setPen(QPen(QColor(120, 170, 240), 1.2))
            p.drawPolyline(pts)
        p.end()


class Dashboard(QWidget):
    def __init__(self):
        super().__init__()
        self.source: Optional[DataSource] = None
        self.gauges: dict[str, Gauge] = {}
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._tick)

        root = QVBoxLayout(self)
        bar = QHBoxLayout()
        self.status = QLabel("No source. Load a log, then Start replay.")
        self.btn_start = QPushButton("▶ Start")
        self.btn_stop = QPushButton("⏹ Stop")
        self.btn_start.clicked.connect(self.start)
        self.btn_stop.clicked.connect(self.stop)
        self.btn_stop.setEnabled(False)
        self.btn_connect = QPushButton("🔌 Connect GT Pro")
        self.btn_connect.clicked.connect(self.connect_gt)
        bar.addWidget(self.status, 1)
        bar.addWidget(self.btn_connect)
        bar.addWidget(self.btn_start)
        bar.addWidget(self.btn_stop)
        root.addLayout(bar)

        self.grid_host = QWidget()
        self.grid = QGridLayout(self.grid_host)
        self.grid.setSpacing(6)
        root.addWidget(self.grid_host, 1)

    def bind_source(self, source: DataSource):
        self.source = source
        avail = set(source.channels())
        # (re)build gauges for channels present in the source
        for i in reversed(range(self.grid.count())):
            w = self.grid.itemAt(i).widget()
            if w:
                w.setParent(None)
        self.gauges.clear()
        specs = [s for s in GAUGE_SPECS if s[0] in avail] or GAUGE_SPECS[:6]
        cols = 4
        for idx, (key, label, unit, lo, hi) in enumerate(specs):
            g = Gauge(key, label, unit, lo, hi)
            self.gauges[key] = g
            self.grid.addWidget(g, idx // cols, idx % cols)
        self.status.setText(f"Source bound: {len(self.gauges)} channels ready.")

    def start(self):
        if not self.source:
            self.status.setText("Load a log first (Log tab → Load Log).")
            return
        self.source.start()
        self.timer.start(100)
        self.btn_start.setEnabled(False)
        self.btn_stop.setEnabled(True)
        self.status.setText("Replaying…")

    def stop(self):
        self.timer.stop()
        if self.source:
            try:
                self.source.stop()
            except Exception:
                pass
        self.btn_start.setEnabled(True)
        self.btn_stop.setEnabled(False)
        self.status.setText("Stopped.")

    def connect_gt(self):
        """Connect the OBDX Pro GT and stream live gauges."""
        self.stop()
        self.status.setText("Connecting to OBDX Pro GT…")
        self.btn_connect.setEnabled(False)
        try:
            src = GtDataSource()
            self.bind_source(src)
            src.start()
            self.timer.start(100)
            self.btn_start.setEnabled(False)
            self.btn_stop.setEnabled(True)
            dev = getattr(src, "device", "OBDX Pro GT")
            self.status.setText(f"{dev} live — {len(self.gauges)} gauges @ {getattr(src,'port_name','')}")
        except Exception as e:
            self.status.setText(f"GT connect failed: {e}")
        finally:
            self.btn_connect.setEnabled(True)

    def _tick(self):
        if not self.source:
            return
        s: Optional[Sample] = self.source.latest()
        if not s:
            return
        for key, g in self.gauges.items():
            g.set_value(s.values.get(key))


# --------------------------------------------------------------------------- #
# Main window
# --------------------------------------------------------------------------- #
class MainWindow(QMainWindow):
    def __init__(self, cal: Calibration, path: Optional[str] = None):
        super().__init__()
        self.cal = cal
        self.path = path
        self.log: Optional[Log] = None
        self.shift_events = cal.metadata.get("shift_events")
        self.current_model: Optional[CalTableModel] = None

        self.setWindowTitle(self._title())
        self.resize(1180, 760)
        self._build_menu()

        splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(self._build_tree())
        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_editor_tab(), "Editor")
        self.tabs.addTab(self._build_scalars_tab(), "Scalars")
        self.tabs.addTab(self._build_log_tab(), "Log Analysis")
        self.dashboard = Dashboard()
        self.tabs.addTab(self.dashboard, "Dashboard")
        splitter.addWidget(self.tabs)
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setSizes([300, 880])
        self.setCentralWidget(splitter)

        # select first table
        if self.cal.tables:
            self._select_table(self.cal.tables[0].name)

    # -- chrome ------------------------------------------------------------ #
    def _title(self) -> str:
        veh = self.cal.metadata.get("vehicle", "calibration")
        name = os.path.basename(self.path) if self.path else "unsaved"
        return f"OpenOBD — {veh}  [{name}]"

    def _build_menu(self):
        m = self.menuBar().addMenu("&File")
        for label, slot, keys in [
            ("Open .cal.json…", self.open_cal, "Ctrl+O"),
            ("Save", self.save_cal, "Ctrl+S"),
            ("Save As…", self.save_cal_as, "Ctrl+Shift+S"),
            ("Export table → CSV…", self.export_csv, None),
            ("Load Log…", self.load_log, "Ctrl+L"),
        ]:
            a = QAction(label, self)
            if keys:
                a.setShortcut(keys)
            a.triggered.connect(slot)
            m.addAction(a)
        m.addSeparator()
        qa = QAction("Quit", self); qa.triggered.connect(self.close); m.addAction(qa)

        h = self.menuBar().addMenu("&Help")
        ab = QAction("About", self); ab.triggered.connect(self._about); h.addAction(ab)

    def _about(self):
        md = self.cal.metadata
        QMessageBox.information(
            self, "About OpenOBD",
            "OpenOBD — calibration viewer/editor + log overlay for truck-mcp.\n\n"
            f"Vehicle: {md.get('vehicle','')}\n"
            f"Controllers: {md.get('controllers','')}\n\n"
            + md.get("safety", ""),
        )

    # -- left tree --------------------------------------------------------- #
    def _build_tree(self) -> QWidget:
        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Tables"])
        cats: dict[str, QTreeWidgetItem] = {}
        for t in self.cal.tables:
            cat = t.category.split("/")[0] or "Uncategorized"
            if cat not in cats:
                node = QTreeWidgetItem([cat]); self.tree.addTopLevelItem(node)
                cats[cat] = node
            leaf = QTreeWidgetItem([t.name.replace("WOT Shift Speed — ", "")])
            leaf.setData(0, Qt.UserRole, t.name)
            cats[cat].addChild(leaf)
        self.tree.expandAll()
        self.tree.itemClicked.connect(self._on_tree_click)
        return self.tree

    def _on_tree_click(self, item, _col):
        name = item.data(0, Qt.UserRole)
        if name:
            self._select_table(name)
            self.tabs.setCurrentIndex(0)

    # -- editor tab -------------------------------------------------------- #
    def _build_editor_tab(self) -> QWidget:
        w = QWidget(); lay = QVBoxLayout(w)

        ctl = QHBoxLayout()
        self.heat_chk = QCheckBox("Heatmap"); self.heat_chk.setChecked(True)
        self.heat_chk.stateChanged.connect(self._toggle_heat)
        ctl.addWidget(self.heat_chk)

        ctl.addWidget(QLabel("Overlay:"))
        self.overlay_mode = QComboBox()
        self.overlay_mode.addItems(["None", "Log count", "Log mean value"])
        self.overlay_mode.currentIndexChanged.connect(self._apply_overlay)
        ctl.addWidget(self.overlay_mode)

        ctl.addWidget(QLabel("X ch:"))
        self.x_ch = QComboBox(); ctl.addWidget(self.x_ch)
        ctl.addWidget(QLabel("Y ch:"))
        self.y_ch = QComboBox(); ctl.addWidget(self.y_ch)
        ctl.addWidget(QLabel("Value:"))
        self.v_ch = QComboBox(); ctl.addWidget(self.v_ch)
        for cb in (self.x_ch, self.y_ch, self.v_ch):
            cb.addItem("(none)")
            cb.currentIndexChanged.connect(self._apply_overlay)

        self.revert_btn = QPushButton("Revert cell → stock")
        self.revert_btn.clicked.connect(self._revert_selected)
        ctl.addWidget(self.revert_btn)
        ctl.addStretch(1)
        lay.addLayout(ctl)

        self.view = QTableView()
        self.view.setItemDelegate(HeatmapDelegate(self.view))
        self.view.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        lay.addWidget(self.view, 1)

        self.table_info = QLabel(""); self.table_info.setWordWrap(True)
        self.table_info.setStyleSheet("color:#555; padding:4px;")
        lay.addWidget(self.table_info)
        return w

    def _select_table(self, name: str):
        t = self.cal.table(name)
        if not t:
            return
        events = self.shift_events if "Shift Speed" in name else None
        self.current_model = CalTableModel(t, shift_events=events)
        self.current_model.show_heatmap = self.heat_chk.isChecked()
        self.view.setModel(self.current_model)
        changed = sum(
            t.cell_changed(r, c)
            for r in range(t.n_rows) for c in range(t.n_cols)
        )
        pid = f" · HPT id {t.param_id}" if t.param_id else ""
        self.table_info.setText(
            f"<b>{t.name}</b> ({t.unit}){pid} · {changed} cell(s) changed vs "
            f"stock<br>{t.note}"
        )
        self._apply_overlay()

    def _toggle_heat(self):
        if self.current_model:
            self.current_model.set_heatmap(self.heat_chk.isChecked())

    def _revert_selected(self):
        if not self.current_model:
            return
        idx = self.view.currentIndex()
        if idx.isValid():
            self.current_model.revert_cell(idx.row(), idx.column())

    def _refresh_channel_combos(self):
        keys = ["(none)"] + (self.log.canonical_keys() if self.log else [])
        for cb in (self.x_ch, self.y_ch, self.v_ch):
            cur = cb.currentText()
            cb.blockSignals(True)
            cb.clear(); cb.addItems(sorted(set(keys), key=keys.index))
            i = cb.findText(cur)
            cb.setCurrentIndex(i if i >= 0 else 0)
            cb.blockSignals(False)
        # sensible defaults for a shift table: x=vss
        if self.log and self.x_ch.currentText() == "(none)":
            i = self.x_ch.findText("vss")
            if i >= 0:
                self.x_ch.setCurrentIndex(i)

    def _apply_overlay(self):
        if not self.current_model:
            return
        mode = self.overlay_mode.currentIndex()
        if mode == 0 or not self.log:
            self.current_model.set_overlay(None, CalTableModel.OVERLAY_NONE)
            return
        xk = self.x_ch.currentText()
        if xk == "(none)":
            self.current_model.set_overlay(None, CalTableModel.OVERLAY_NONE)
            return
        yk = self.y_ch.currentText()
        vk = self.v_ch.currentText()
        yk = None if yk == "(none)" else yk
        vk = None if vk == "(none)" else vk
        try:
            ov = bin_log_to_table(
                self.log, self.current_model.table,
                x_channel=xk, y_channel=yk, value_channel=vk,
            )
        except Exception:
            return
        m = (CalTableModel.OVERLAY_COUNT if mode == 1
             else CalTableModel.OVERLAY_MEAN)
        self.current_model.set_overlay(ov, m)

    # -- scalars tab ------------------------------------------------------- #
    def _build_scalars_tab(self) -> QWidget:
        w = QWidget(); lay = QVBoxLayout(w)
        self.scalar_tbl = QTableWidget(len(self.cal.scalars), 6)
        self.scalar_tbl.setHorizontalHeaderLabels(
            ["Parameter", "Value", "Unit", "Stock", "Δ", "Category"])
        self.scalar_tbl.horizontalHeader().setSectionResizeMode(
            0, QHeaderView.Stretch)
        for r, s in enumerate(self.cal.scalars):
            self._set_scalar_row(r, s)
        self.scalar_tbl.itemChanged.connect(self._on_scalar_edit)
        lay.addWidget(self.scalar_tbl)
        note = QLabel(self.cal.metadata.get("safety", ""))
        note.setWordWrap(True); note.setStyleSheet("color:#a33; padding:6px;")
        lay.addWidget(note)
        return w

    def _set_scalar_row(self, r, s):
        def item(text, editable=False, color=None):
            it = QTableWidgetItem(text)
            if not editable:
                it.setFlags(it.flags() & ~Qt.ItemIsEditable)
            if color:
                it.setForeground(color)
            return it
        self.scalar_tbl.blockSignals(True)
        self.scalar_tbl.setItem(r, 0, item(s.name))
        vi = item(f"{s.value:g}", editable=True)
        vi.setData(Qt.UserRole, r)
        self.scalar_tbl.setItem(r, 1, vi)
        self.scalar_tbl.setItem(r, 2, item(s.unit))
        self.scalar_tbl.setItem(
            r, 3, item("" if s.stock_value is None else f"{s.stock_value:g}"))
        delta = ""
        if s.stock_value is not None:
            d = s.value - s.stock_value
            delta = f"{d:+g}" if d else ""
        self.scalar_tbl.setItem(
            r, 4, item(delta, color=QColor(190, 60, 50) if delta else None))
        self.scalar_tbl.setItem(r, 5, item(s.category))
        self.scalar_tbl.blockSignals(False)

    def _on_scalar_edit(self, it):
        if it.column() != 1:
            return
        r = it.data(Qt.UserRole)
        if r is None:
            r = it.row()
        try:
            v = float(it.text())
        except ValueError:
            return
        self.cal.scalars[r].value = v
        self._set_scalar_row(r, self.cal.scalars[r])

    # -- log tab ----------------------------------------------------------- #
    def _build_log_tab(self) -> QWidget:
        w = QWidget(); lay = QVBoxLayout(w)
        bar = QHBoxLayout()
        b = QPushButton("Load Log…"); b.clicked.connect(self.load_log)
        bar.addWidget(b); bar.addStretch(1)
        lay.addLayout(bar)
        self.log_report = QTextEdit(); self.log_report.setReadOnly(True)
        self.log_report.setFont(QFont("Consolas", 10))
        self.log_report.setPlainText(
            "No log loaded.\n\nLoad a VCM Scanner CSV export (Log File → Export "
            "Log File → CSV) or a plain CSV. The report shows regime trims, "
            "knock events, and fuel-pressure flags; the Editor tab can then "
            "overlay the log onto any table.")
        lay.addWidget(self.log_report)
        return w

    def _render_report(self):
        if not self.log:
            return
        rep = analyze_log(self.log)
        L = []
        L.append(f"Source: {self.log.source}")
        L.append(f"Samples: {rep.n_samples}"
                 + (f"  ·  Duration: {rep.duration_s:.1f}s"
                    if rep.duration_s else ""))
        L.append(f"Channels: {', '.join(rep.channels_present)}")
        L.append("")
        L.append("── Regime trims ──")
        for rg in rep.regimes:
            s = f"  {rg.name:22s} n={rg.n:<6d}"
            if rg.combined_trim_mean is not None:
                s += f" trim {rg.combined_trim_mean:+.1f}%"
                if rg.stft_mean is not None:
                    s += f"  (STFT {rg.stft_mean:+.1f}, LTFT {rg.ltft_mean or 0:+.1f})"
            L.append(s)
        L.append("")
        L.append("── Knock ──")
        if rep.max_knock_retard is not None:
            L.append(f"  max KR: {rep.max_knock_retard:.1f}°  ·  "
                     f"{len(rep.knock_events)} event(s)")
        for e in rep.knock_events[:12]:
            if e.get("inferred"):
                L.append(f"    ~t={e.get('time_s')}  spark drop "
                         f"{e.get('spark_drop_deg')}°  @ {e.get('rpm')} rpm (inferred)")
            else:
                L.append(f"    t={e.get('time_s')}  KR {e.get('retard_deg')}°  "
                         f"@ {e.get('rpm')} rpm")
        if rep.max_knock_retard is None and not rep.knock_events:
            L.append("  none / not logged")
        L.append("")
        if rep.fuel_pressure_min is not None:
            L.append(f"── Fuel pressure ── min {rep.fuel_pressure_min:.0f}"
                     + ("  ⚠ SAG" if rep.fuel_pressure_sag else ""))
            L.append("")
        # Observed shift points — the meaningful comparison for the shift tables.
        shifts = detect_shift_points(self.log)
        wot_shifts = [s for s in shifts if s.wot]
        L.append("── Observed shift points ──")
        if not shifts:
            L.append("  none detected (need a 'gear' channel or a clear RPM drop)")
        else:
            src = "gear channel" if not shifts[0].inferred else "inferred (RPM drop)"
            L.append(f"  {len(shifts)} shift(s) via {src}; "
                     f"{len(wot_shifts)} at WOT")
            for s in (wot_shifts or shifts)[:12]:
                gear = (f"{s.from_gear}->{s.to_gear}"
                        if s.from_gear is not None else "up")
                rpm = f"{s.rpm:.0f} rpm" if s.rpm is not None else "?"
                vss = f"{s.vss:.0f} mph" if s.vss is not None else "?"
                flag = " ⚑WOT" if s.wot else ""
                L.append(f"    {gear:6s} @ {rpm:>10s}  {vss:>7s}{flag}")
            L.append("  (compare WOT shifts to the setpoint tables: target "
                     "1-2/2-3 ~5,400-5,500 RPM on 4.11/35s)")
        L.append("")
        if rep.notes:
            L.append("── Notes ──")
            for n in rep.notes:
                L.append(f"  • {n}")
        self.log_report.setPlainText("\n".join(L))

    # -- file ops ---------------------------------------------------------- #
    def open_cal(self):
        p, _ = QFileDialog.getOpenFileName(
            self, "Open calibration", "", "Calibration (*.cal.json *.json)")
        if not p:
            return
        try:
            self.cal = Calibration.load(p)
        except Exception as e:
            QMessageBox.critical(self, "Open failed", str(e)); return
        self.path = p
        # rebuild UI by re-instantiating (simplest, robust)
        new = MainWindow(self.cal, p)
        new.show()
        self.close()

    def save_cal(self):
        if not self.path:
            return self.save_cal_as()
        try:
            self.cal.save(self.path)
            self.setWindowTitle(self._title())
            self.statusBar().showMessage(f"Saved {self.path}", 4000)
        except Exception as e:
            QMessageBox.critical(self, "Save failed", str(e))

    def save_cal_as(self):
        p, _ = QFileDialog.getSaveFileName(
            self, "Save calibration", self.path or "edited.cal.json",
            "Calibration (*.cal.json *.json)")
        if not p:
            return
        self.path = p
        self.save_cal()

    def export_csv(self):
        if not self.current_model:
            return
        t = self.current_model.table
        p, _ = QFileDialog.getSaveFileName(
            self, "Export table CSV", f"{t.name}.csv", "CSV (*.csv)")
        if not p:
            return
        import csv
        with open(p, "w", newline="", encoding="utf-8") as fh:
            wtr = csv.writer(fh)
            hdr = [""] + (
                self.shift_events if ("Shift" in t.name and self.shift_events)
                else [f"{v:g}" for v in t.x_axis.values])
            wtr.writerow(hdr)
            for r in range(t.n_rows):
                ylab = (f"{t.y_axis.values[r]:g}" if t.y_axis else t.unit)
                wtr.writerow([ylab] + [f"{v:g}" for v in t.values[r]])
        self.statusBar().showMessage(f"Exported {p}", 4000)

    def load_log(self):
        p, _ = QFileDialog.getOpenFileName(
            self, "Load log", "", "Logs (*.csv);;All files (*)")
        if not p:
            return
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            self.log = parse_csv(text, source=os.path.basename(p))
        except Exception as e:
            QMessageBox.critical(self, "Load log failed", str(e)); return
        self._render_report()
        self._refresh_channel_combos()
        self.dashboard.bind_source(LogReplaySource(self.log, speed=4.0))
        self.tabs.setCurrentIndex(2)
        self.statusBar().showMessage(
            f"Loaded log: {self.log.n_samples} samples, "
            f"{len(self.log.canonical_keys())} mapped channels", 6000)


def load_default_cal() -> tuple[Calibration, Optional[str]]:
    # Candidate locations: dev tree, and PyInstaller's bundled data dir.
    candidates = []
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    candidates.append(os.path.join(here, "data", "2010_silverado_24.cal.json"))
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidates.append(os.path.join(meipass, "data",
                                       "2010_silverado_24.cal.json"))
    for seed_path in candidates:
        if os.path.exists(seed_path):
            # A frozen bundle's seed is read-only; return no path so Save prompts
            # the user for a writable location instead of failing on the bundle.
            writable_path = None if meipass and seed_path.startswith(meipass) \
                else seed_path
            return Calibration.load(seed_path), writable_path
    from . import seed_2010_silverado as s
    return s.build_with_labels(), None


def main(argv=None):
    argv = argv if argv is not None else sys.argv
    app = QApplication(argv)
    app.setStyle("Fusion")
    args = argv[1:]
    want_gt = "--gt" in args
    paths = [a for a in args if not a.startswith("-") and os.path.exists(a)]
    if paths:
        cal, path = Calibration.load(paths[0]), paths[0]
    else:
        cal, path = load_default_cal()
    win = MainWindow(cal, path)
    win.show()
    if want_gt:
        try:
            win.tabs.setCurrentWidget(win.dashboard)
        except Exception:
            pass
        QTimer.singleShot(300, win.dashboard.connect_gt)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
