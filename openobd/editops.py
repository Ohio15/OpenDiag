"""
editops — headless editing operations for calibration tables.

The Qt editor calls these to implement the HP-Tuners staples: selection math
(set / add / multiply / percent-scale), interpolation (horizontal / vertical /
2-D bilinear), and TSV clipboard interchange with Excel.

Every mutating helper is *pure planning*: it returns a change map
{(row, col): (old, new)} and never touches the Table, so the GUI can wrap the
result in an undo command and the core stays unit-testable without Qt.
"""
from __future__ import annotations

from typing import Optional

from .calspec import Table

Cells = list[tuple[int, int]]
Changes = dict[tuple[int, int], tuple[float, float]]


# --------------------------------------------------------------------------- #
# Selection math
# --------------------------------------------------------------------------- #
def apply_math(table: Table, cells: Cells, op: str, operand: float) -> Changes:
    """op: 'set' | 'add' | 'mul' | 'pct' (pct: +N% -> value * (1 + N/100))."""
    changes: Changes = {}
    for r, c in cells:
        old = table.values[r][c]
        if op == "set":
            new = operand
        elif op == "add":
            new = old + operand
        elif op == "mul":
            new = old * operand
        elif op == "pct":
            new = old * (1.0 + operand / 100.0)
        else:
            raise ValueError(f"unknown op {op!r}")
        if new != old:
            changes[(r, c)] = (old, new)
    return changes


# --------------------------------------------------------------------------- #
# Interpolation
# --------------------------------------------------------------------------- #
def _lerp_run(vals: list[float]) -> list[float]:
    """Linear ramp between the first and last entry, endpoints kept."""
    n = len(vals)
    if n < 3:
        return list(vals)
    a, b = vals[0], vals[-1]
    return [a + (b - a) * i / (n - 1) for i in range(n)]


def interpolate(table: Table, cells: Cells, mode: str) -> Changes:
    """
    mode 'h': per selected row, ramp between the leftmost and rightmost
              selected cell in that row.
    mode 'v': per selected column, ramp between top and bottom selected cell.
    mode '2d': bilinear across the selection's bounding rectangle from its
              four corner values (all cells in the rect are written).
    """
    if not cells:
        return {}
    changes: Changes = {}
    if mode == "h":
        rows: dict[int, list[int]] = {}
        for r, c in cells:
            rows.setdefault(r, []).append(c)
        for r, cs in rows.items():
            cs = sorted(set(cs))
            span = list(range(cs[0], cs[-1] + 1))
            new_vals = _lerp_run([table.values[r][c] for c in span])
            for c, nv in zip(span, new_vals):
                old = table.values[r][c]
                if nv != old:
                    changes[(r, c)] = (old, nv)
    elif mode == "v":
        cols: dict[int, list[int]] = {}
        for r, c in cells:
            cols.setdefault(c, []).append(r)
        for c, rs in cols.items():
            rs = sorted(set(rs))
            span = list(range(rs[0], rs[-1] + 1))
            new_vals = _lerp_run([table.values[r][c] for r in span])
            for r, nv in zip(span, new_vals):
                old = table.values[r][c]
                if nv != old:
                    changes[(r, c)] = (old, nv)
    elif mode == "2d":
        r0 = min(r for r, _ in cells); r1 = max(r for r, _ in cells)
        c0 = min(c for _, c in cells); c1 = max(c for _, c in cells)
        if r1 == r0 or c1 == c0:  # degenerate rect -> fall back to 1-D
            return interpolate(table, cells, "h" if r1 == r0 else "v")
        v00 = table.values[r0][c0]; v01 = table.values[r0][c1]
        v10 = table.values[r1][c0]; v11 = table.values[r1][c1]
        for r in range(r0, r1 + 1):
            fy = (r - r0) / (r1 - r0)
            for c in range(c0, c1 + 1):
                fx = (c - c0) / (c1 - c0)
                nv = (v00 * (1 - fx) * (1 - fy) + v01 * fx * (1 - fy)
                      + v10 * (1 - fx) * fy + v11 * fx * fy)
                old = table.values[r][c]
                if nv != old:
                    changes[(r, c)] = (old, nv)
    else:
        raise ValueError(f"unknown interpolate mode {mode!r}")
    return changes


# --------------------------------------------------------------------------- #
# Revert to stock
# --------------------------------------------------------------------------- #
def revert_cells(table: Table, cells: Cells) -> Changes:
    if table.stock_values is None:
        return {}
    changes: Changes = {}
    for r, c in cells:
        old = table.values[r][c]
        new = table.stock_values[r][c]
        if new != old:
            changes[(r, c)] = (old, new)
    return changes


def all_cells(table: Table) -> Cells:
    return [(r, c) for r in range(table.n_rows) for c in range(table.n_cols)]


def changed_cells(table: Table) -> Cells:
    return [(r, c) for r in range(table.n_rows) for c in range(table.n_cols)
            if table.cell_changed(r, c)]


# --------------------------------------------------------------------------- #
# TSV clipboard interchange (Excel round-trip)
# --------------------------------------------------------------------------- #
def to_tsv(table: Table, cells: Cells) -> str:
    """Bounding-rect TSV of the selection; unselected cells in the rect are
    empty fields (so ragged selections round-trip as Excel blanks)."""
    if not cells:
        return ""
    sel = set(cells)
    r0 = min(r for r, _ in cells); r1 = max(r for r, _ in cells)
    c0 = min(c for _, c in cells); c1 = max(c for _, c in cells)
    lines = []
    for r in range(r0, r1 + 1):
        lines.append("\t".join(
            f"{table.values[r][c]:g}" if (r, c) in sel else ""
            for c in range(c0, c1 + 1)))
    return "\n".join(lines)


def parse_tsv(text: str) -> list[list[Optional[float]]]:
    """Clipboard TSV -> grid of floats (None for blanks/non-numeric).
    Accepts trailing newline; tolerates CRLF."""
    grid: list[list[Optional[float]]] = []
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if line == "" and grid:  # trailing blank line
            continue
        row: list[Optional[float]] = []
        for cell in line.split("\t"):
            cell = cell.strip()
            try:
                row.append(float(cell)) if cell else row.append(None)
            except ValueError:
                row.append(None)
        grid.append(row)
    while grid and all(v is None for v in grid[-1]):
        grid.pop()
    return grid


def paste_grid(table: Table, r0: int, c0: int,
               grid: list[list[Optional[float]]]) -> Changes:
    """Plan pasting grid with its top-left at (r0, c0); clipped to the table,
    None cells skipped (Excel blanks leave the target untouched)."""
    changes: Changes = {}
    for dr, row in enumerate(grid):
        r = r0 + dr
        if r >= table.n_rows:
            break
        for dc, v in enumerate(row):
            c = c0 + dc
            if c >= table.n_cols or v is None:
                continue
            old = table.values[r][c]
            if v != old:
                changes[(r, c)] = (old, v)
    return changes
