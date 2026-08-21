"""
chanlayout — the ONE selection + grouping model behind the Live Data page.

Both views on Live Data — the compact tile grid and the Chart vs. Time strip
chart — derive what they show from a single ChannelLayout, so hiding a field
removes it from BOTH views and adding it back restores it to both; the two
views cannot disagree about what is selected. The layout also owns the chart's
lane grouping (HP Tuners VCM-Scanner-style user channel groups): the user
composes the graph by dragging tiles into the graphed-channels table (or via
the menus), moving any chartable channel into an existing lane or a new one.
stripchart.LANE_PRESETS is only the *default* graph, used until the user
customizes; a customized lane list IS the graph, exactly.

The one asymmetry is stated, not silent: a channel the store cannot chart
(text kind, or no numeric sample yet) is tile-only — it can be shown or hidden
like any other field, but it never gets a trace, and the UI labels it so.

Persistence is a JSON blob global to the app (truck-mcp store channel names
are stable across sessions), written by the page into QSettings under
SETTINGS_KEY. A saved layout must degrade, never crash: garbage JSON loads as
the defaults; channels named in a saved layout but absent from the bound
session simply don't resolve (they stay saved for the next drive that has
them). New channels a customized layout has never seen appear as tiles — the
palette is always complete — and join the graph only when the user drags
them in.

No Qt in this module — pure stdlib, unit-testable.
"""
from __future__ import annotations

import json
from typing import Optional, Sequence

from .stripchart import build_lanes

SETTINGS_KEY = "livedata/layout"
_FORMAT_VERSION = 1


class ChannelLayout:
    """Visible-field set + chart lane grouping, shared by tiles and chart.

    ``hidden`` is the set of channel names removed from both views.
    ``lanes`` is either None — meaning "use the LANE_PRESETS defaults via
    build_lanes" — or the user's explicit lane assignment as an ordered list
    of channel-name lists. Names in ``lanes`` that the bound session lacks
    are kept in the saved layout but skipped at resolve time.
    """

    def __init__(self, hidden: Optional[Sequence[str]] = None,
                 lanes: Optional[list[list[str]]] = None):
        self.hidden: set[str] = set(hidden or ())
        self.lanes: Optional[list[list[str]]] = lanes

    # -- persistence -------------------------------------------------------- #
    def to_json(self) -> str:
        return json.dumps({"v": _FORMAT_VERSION,
                           "hidden": sorted(self.hidden),
                           "lanes": self.lanes})

    @classmethod
    def from_json(cls, text) -> "ChannelLayout":
        """Load a saved layout, degrading to the defaults on ANY malformed
        input — a bad settings blob must never take down the page."""
        try:
            data = json.loads(text)
        except (TypeError, ValueError):
            return cls()
        if not isinstance(data, dict):
            return cls()
        hidden = {n for n in (data.get("hidden") or [])
                  if isinstance(n, str)} if isinstance(
                      data.get("hidden"), list) else set()
        lanes_raw = data.get("lanes")
        lanes: Optional[list[list[str]]] = None
        if isinstance(lanes_raw, list):
            lanes = []
            seen: set[str] = set()
            for lane in lanes_raw:
                if not isinstance(lane, list):
                    continue
                clean = []
                for n in lane:
                    if isinstance(n, str) and n not in seen:
                        seen.add(n)
                        clean.append(n)
                if clean:
                    lanes.append(clean)
            if not lanes:
                lanes = None
        return cls(hidden=hidden, lanes=lanes)

    def is_default(self) -> bool:
        return not self.hidden and self.lanes is None

    def reset(self):
        self.hidden.clear()
        self.lanes = None

    # -- selection (drives BOTH views) -------------------------------------- #
    def is_hidden(self, name: str) -> bool:
        return name in self.hidden

    def hide(self, name: str):
        self.hidden.add(name)

    def show(self, name: str):
        self.hidden.discard(name)

    def tile_names(self, session_names: Sequence[str]) -> list[str]:
        """The tiles to build for a session: every session channel not hidden,
        in stable sorted order (text/tile-only channels included — the tile
        grid is the complete raw view of what the store holds)."""
        return sorted(n for n in session_names if n not in self.hidden)

    # -- grouping (drives the chart) ---------------------------------------- #
    def chart_lanes(self, chartable_names: Sequence[str]) -> list[list[str]]:
        """The chart's lanes for a session's chartable channels. Default
        (lanes is None): every visible chartable channel, grouped by the
        presets. Customized: the lanes ARE the graph, exactly — the user
        composes it by dragging tiles into the graphed-channels table (or via
        the menus), so nothing is auto-appended behind their back; the tile
        grid remains the always-complete palette of every field."""
        visible = [n for n in chartable_names if n not in self.hidden]
        if self.lanes is None:
            return build_lanes(visible)
        present = set(visible)
        resolved = [[n for n in lane if n in present] for lane in self.lanes]
        return [lane for lane in resolved if lane]

    def is_graphed(self, name: str, chartable_names: Sequence[str]) -> bool:
        return any(name in lane for lane in self.chart_lanes(chartable_names))

    def move_to_lane(self, name: str, lane_index: Optional[int],
                     chartable_names: Sequence[str]):
        """Assign ``name`` to lane ``lane_index`` (None or out-of-range means
        a NEW lane at the bottom) — this is also how a channel is ADDED to
        the graph, e.g. by dropping its tile on the graphed-channels table.
        First customization materializes the current resolved grouping so the
        edit applies to what the user is looking at, not an unrelated
        default. Empty lanes are pruned."""
        if self.lanes is None:
            self.lanes = self.chart_lanes(chartable_names)
        # Remove from wherever it is (keep empties until after the insert so
        # lane_index still points at the lane the user picked).
        for lane in self.lanes:
            if name in lane:
                lane.remove(name)
        if lane_index is None or not (0 <= lane_index < len(self.lanes)):
            self.lanes.append([name])
        else:
            self.lanes[lane_index].append(name)
        self.lanes = [lane for lane in self.lanes if lane]

    def remove_from_chart(self, name: str,
                          chartable_names: Sequence[str]):
        """Take ``name`` off the graph WITHOUT hiding its tile — the field
        stays on the palette, it just no longer plots."""
        if self.lanes is None:
            self.lanes = self.chart_lanes(chartable_names)
        for lane in self.lanes:
            if name in lane:
                lane.remove(name)
        self.lanes = [lane for lane in self.lanes if lane]

