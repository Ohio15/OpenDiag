"""
Qt model + delegate for the calibration table editor.

CalTableModel wraps a calspec.Table as an editable QAbstractTableModel with:
  - value heatmap (min->max mapped blue->red) as cell background
  - changed-vs-stock cells outlined/bolded
  - an optional log Overlay: count histogram tint + mean-value tooltip

HeatmapDelegate paints the background; editing writes floats back into the
Table and marks the cell dirty. All Qt imports are local so the headless core
(calspec/logbin/transport) never pulls in PySide6.
"""
from __future__ import annotations

from typing import Optional

from PySide6.QtCore import Qt, QAbstractTableModel, QModelIndex
from PySide6.QtGui import QColor, QBrush, QFont
from PySide6.QtWidgets import QStyledItemDelegate

from .calspec import Table
from .logbin import Overlay


def heat_color(frac: float, alpha: int = 210) -> QColor:
    """frac in [0,1] -> blue(low) .. green .. yellow .. red(high)."""
    frac = max(0.0, min(1.0, frac))
    # 4-stop gradient
    stops = [
        (0.00, (40, 90, 200)),
        (0.40, (40, 170, 120)),
        (0.70, (230, 200, 40)),
        (1.00, (210, 55, 45)),
    ]
    for i in range(len(stops) - 1):
        f0, c0 = stops[i]
        f1, c1 = stops[i + 1]
        if frac <= f1:
            span = (f1 - f0) or 1.0
            k = (frac - f0) / span
            r = int(c0[0] + (c1[0] - c0[0]) * k)
            g = int(c0[1] + (c1[1] - c0[1]) * k)
            b = int(c0[2] + (c1[2] - c0[2]) * k)
            return QColor(r, g, b, alpha)
    r, g, b = stops[-1][1]
    return QColor(r, g, b, alpha)


def text_color_for(bg: QColor) -> QColor:
    """Black or white, whichever reads better on bg (WCAG-ish luminance)."""
    lum = 0.299 * bg.red() + 0.587 * bg.green() + 0.114 * bg.blue()
    return QColor(15, 15, 15) if lum >= 140 else QColor(235, 235, 235)


class CalTableModel(QAbstractTableModel):
    OVERLAY_NONE = 0
    OVERLAY_COUNT = 1
    OVERLAY_MEAN = 2

    def __init__(self, table: Table, shift_events: Optional[list[str]] = None):
        super().__init__()
        self.table = table
        self.shift_events = shift_events
        self.overlay: Optional[Overlay] = None
        self.overlay_mode = self.OVERLAY_NONE
        self.show_heatmap = True

    # -- shape ------------------------------------------------------------- #
    def rowCount(self, parent=QModelIndex()) -> int:
        return self.table.n_rows

    def columnCount(self, parent=QModelIndex()) -> int:
        return self.table.n_cols

    # -- headers ----------------------------------------------------------- #
    def headerData(self, section, orientation, role=Qt.DisplayRole):
        if role != Qt.DisplayRole:
            return None
        if orientation == Qt.Horizontal:
            # WOT shift tables: label columns with gear-change events.
            if self.shift_events and section < len(self.shift_events):
                return self.shift_events[section]
            ax = self.table.x_axis
            v = ax.values[section] if section < len(ax.values) else section
            return f"{v:g}{(' ' + ax.unit) if ax.unit else ''}"
        else:
            if self.table.y_axis:
                ay = self.table.y_axis
                v = ay.values[section] if section < len(ay.values) else section
                return f"{v:g}{(' ' + ay.unit) if ay.unit else ''}"
            return self.table.unit or "value"

    # -- data -------------------------------------------------------------- #
    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid():
            return None
        r, c = index.row(), index.column()
        val = self.table.values[r][c]

        if role in (Qt.DisplayRole, Qt.EditRole):
            return f"{val:g}"

        if role == Qt.BackgroundRole:
            bg = self._bg_color(r, c, val)
            return QBrush(bg) if bg is not None else None

        if role == Qt.ForegroundRole:
            bg = self._bg_color(r, c, val)
            # No explicit background -> let the palette pick the text color.
            return QBrush(text_color_for(bg)) if bg is not None else None

        if role == Qt.FontRole and self.table.cell_changed(r, c):
            f = QFont()
            f.setBold(True)
            return f

        if role == Qt.ToolTipRole:
            return self._tooltip(r, c, val)

        if role == Qt.TextAlignmentRole:
            return int(Qt.AlignCenter)
        return None

    def _bg_color(self, r: int, c: int, val: float) -> Optional[QColor]:
        # Overlay tint takes precedence when active; cells the log never
        # touched keep the palette background (None).
        if self.overlay and self.overlay_mode == self.OVERLAY_COUNT:
            counts = self.overlay.count_grid()
            mx = max((max(row) for row in counts), default=0)
            cnt = counts[r][c] if r < len(counts) and c < len(counts[r]) else 0
            if mx > 0 and cnt > 0:
                return heat_color(cnt / mx)
            return None
        if self.overlay and self.overlay_mode == self.OVERLAY_MEAN:
            means = self.overlay.mean_grid()
            flat = [m for row in means for m in row if m is not None]
            if flat:
                lo, hi = min(flat), max(flat)
                m = means[r][c] if r < len(means) and c < len(means[r]) else None
                if m is not None:
                    span = (hi - lo) or 1.0
                    return heat_color((m - lo) / span)
            return None

        if not self.show_heatmap:
            return None
        lo, hi = self.table.vmin_vmax()
        span = (hi - lo) or 1.0
        return heat_color((val - lo) / span, alpha=170)

    def _tooltip(self, r: int, c: int, val: float) -> str:
        lines = [f"value: {val:g} {self.table.unit}".strip()]
        if self.table.stock_values is not None:
            stock = self.table.stock_values[r][c]
            delta = val - stock
            lines.append(f"stock: {stock:g}  (Δ {delta:+g})")
        if self.overlay:
            counts = self.overlay.count_grid()
            means = self.overlay.mean_grid()
            if r < len(counts) and c < len(counts[r]):
                lines.append(f"log hits: {counts[r][c]}")
                m = means[r][c]
                if m is not None and self.overlay.value_channel:
                    lines.append(f"mean {self.overlay.value_channel}: {m:.2f}")
        return "\n".join(lines)

    # -- editing ----------------------------------------------------------- #
    def flags(self, index):
        if not index.isValid():
            return Qt.NoItemFlags
        return Qt.ItemIsEnabled | Qt.ItemIsSelectable | Qt.ItemIsEditable

    def setData(self, index, value, role=Qt.EditRole) -> bool:
        if role != Qt.EditRole or not index.isValid():
            return False
        try:
            fv = float(value)
        except (TypeError, ValueError):
            return False
        self.table.values[index.row()][index.column()] = fv
        self.dataChanged.emit(index, index)
        return True

    # -- helpers used by the window --------------------------------------- #
    def revert_cell(self, r: int, c: int) -> None:
        if self.table.stock_values is not None:
            self.table.values[r][c] = self.table.stock_values[r][c]
            idx = self.index(r, c)
            self.dataChanged.emit(idx, idx)

    def set_overlay(self, overlay: Optional[Overlay], mode: int) -> None:
        self.layoutAboutToBeChanged.emit()
        self.overlay = overlay
        self.overlay_mode = mode
        self.layoutChanged.emit()

    def set_heatmap(self, on: bool) -> None:
        self.show_heatmap = on
        self.layoutAboutToBeChanged.emit()
        self.layoutChanged.emit()


class HeatmapDelegate(QStyledItemDelegate):
    """Thin delegate: the model supplies BackgroundRole, so default painting
    already heatmaps. This exists as a hook for future in-cell bars/sparklines."""

    def initStyleOption(self, option, index):
        super().initStyleOption(option, index)
