# Community tow-tune consensus — 2010 Silverado 5.3 LMG (E38) + 6L80 (T43), 4.11s, 35s, AFM-deleted, E10

Researched 2026-08-24 (web sweep of HP Tuners forum, SilveradoSierra, LS1TECH,
PerformanceTrucks, CorvetteForum, EFILive, Sonnax). This is the "tow"
reference the merge policy cites. It deliberately is NOT a `.cal.json`: the
community publishes strategies and ranges, not cell values, and fabricating
tables is forbidden. Where a strategy maps onto this platform's harvest it is
noted; apply manual edits in the editor with this file as provenance.

## 1. TCC lockup for towing
Lock MORE, not less — lockup is the biggest trans-temp reducer. GM's own
Tow/Haul = **Pattern A** tables (TCC in 3rd–5th vs Normal's 4th–6th; locks as
low as 2nd near WOT). The truck already selects these via the Tow/Haul button,
so *stock Pattern A tables ARE the tow consensus* → merge keeps them stock.
- Cap TCC regulator/solenoid pressure ≤75–80 psi (stamped-steel lockup piston
  cracks under aggressive zero-slip + high-pressure recipes).
- Conflict in community: "zero all slip tables" vs "the woven-carbon lining is
  designed to slip". Safer camp for a stock converter towing: earlier lockup,
  modest pressure, no zero-slip chase. Mirror params: TCC Pressure Regulator
  Gain/Offset (pids 5670/5671), TCC Desired Pressure (5672), TCC Desired Slip
  tables (35000+), TCC Apply/Release Pattern A (15285, 15293).
- Verify TCC apply MPH cells sit below real cruise speeds after any tire/gear
  rescale (a documented failure: apply at 43 mph @ 19% TPS meant it never
  locked in normal driving).

Sources: forum.hptuners.com/showthread.php?108820 ·
silveradosierra.com/threads/tuning-6l80-convertor-with-hptuners.744560 ·
corvetteforum.com/forums/c6-scan-and-tune/2345942 ·
silveradosierra.com/threads/6l80-6l90-tc-lock-up.706137 ·
forum.efilive.com/archive/index.php/t-18246.html

## 2. Line pressure / shift pressure
**Max Pressure / Max Line Pressure tables are inert clamps on a stock 6L80**
(they already sit near pump capacity; actual PCS1 pressure follows the
reported engine torque). Never rule-route or raise them expecting effect —
the only hardware increase is a Sonnax boost valve.
Effective levers: per-clutch **shift pressure** tables (+20–50 psi in towing
load cells, paired with modestly shorter shift times), and an accurate
**torque model** — the TCM schedules pressure from delivered torque.
After pressure/shift-time edits: clear adapts + garage-shift/fast-learn
relearn, or the TCM ignores the change.

Sources: forum.hptuners.com/showthread.php?93840 ("Line pressure. Everyone is
wrong") · performancetrucks.net/forums/...-510712 · tbssowners.com/threads/11599 ·
silveradosierra.com/threads/read-this-if-you-are-swapping-6l80-tcm.646842

## 3. Shift points with 4.11 + 35"
4.11 + 35" ≈ stock 3.42 + 32" effective — post-rescale shift MPH should land
near stock RPM. #24's WOT shift-speed rescale is the verified fix and the
merge keeps it (rule: WOT Shift Speed → sheet24). Notes: shift tables are
MPH-commanded (edit those, not RPM views); 4-5/5-6 upshifts are governed by
the D1 Safety tables (pid 15305) if high gears won't engage; for towing, make
holds/delays in Pattern A tables; hand-verify anything the HPT Gear/Tire
wizard auto-scales (documented mis-scale report).

Sources: hptuners.com/articles/gear-tire-adjustment-guide-for-vcm-suite ·
corvetteforum.com/forums/c6-scan-and-tune/4777172 ·
g8board.com/threads/65550 · performancetrucks.net/forums/...-485699

## 4. Torque management / abuse mode
**Keep TM and abuse mode ENABLED on a towing truck** — TM unloads the
clutches mid-shift; multiple reports that deleting it kills 6L80s. Acceptable:
trim shift torque reduction to ~50–75% of stock for crisper shifts. Never
zero garage-shift torque reduction, never raise Trans Max Torque / TCC Limit
Torque (pid 5420) past stock-converter protection. "Disable abuse mode" is
drag-strip advice — wrong direction for towing.

Sources: hptuners.eu/help/vcm_editor_parameters_gm_trans_tm.htm ·
ls1tech.com/forums/automatic-transmission/1079222 ·
performancetrucks.net/forums/...-308928 · forum.hptuners.com/showthread.php?38029

## 5. Spark/knock on E10
E38 blends High↔Low octane tables via the knock-driven octane scaler. For
towing on 87 E10: pull timing in cells that repeatedly show KR (both tables;
low-octane first) instead of living on sensor feedback; keep the low-octane
table a genuinely conservative safety net; transient KR blips are normal,
**sustained KR under steady towing load is a tune error**; never flatten low
up to high or disable knock sensors.

Sources: silveradosierra.com/threads/608010 · performancetrucks.net/...-501188 ·
forum.hptuners.com/showthread.php?42153

## 6. Cooling
Community fan-on advice (~185–195°F low / 195–205°F high, above t-stat) is
for electric-fan ECT tables — **this truck's harvest exposes airflow-based
clutch-fan scalars (lb/h, pids 2145–2149), not ECT fan-on temps**, so the
advice does not map onto a mirror parameter; no override is made. Trans temp
management = TCC lockup coverage (§1) + external cooler; leave hot-mode
protections enabled.

Sources: gm-trucks.com/forums/topic/246381 · ls1tech.com/forums/246694 ·
forum.hptuners.com/showthread.php?35985 · performancetrucks.net/...-543694

## 7. AFM/DoD delete companions (E38)
All cylinder-deactivation flags off; DTCs P3400–P3497 → No Error Reported
after a mechanical delete; VVT phasing tables must have no V4-conditioned
logic live; neutralize DoD-specific TCC slip entries (pids 5631/5632 exist in
the mirror); after a mechanical cam/lifter delete, recalibrate idle airflow,
VE/MAF and the torque model (a stale torque model corrupts 6L80 pressure
scheduling). Software-off ≠ mechanical delete.

Sources: forum.hptuners.com/showthread.php?112078 ·
silveradosierra.com/how-to-articles/t71745 · streettunedai.com/blogs/news ·
ewaltsautotuning.com/tuning/p/afm-dod-delete

## 8. "Won't move under load / won't reverse trailer / strong creep" causes
Tune-side candidates: torque model reporting low (TCM under-pressures the
clutches → slips only when loaded; reverse's 3-5-R clutch slips first);
pressure/TM edits without an adapt relearn (clear adapts + garage-shift learn:
~20× R-D, 10× N-D, 10× N-R at idle, brake on); wrong OS / mismatched T43
segment; raised idle/Desired Torque low-RPM offset (creep). **No documented
6L80 tune cause applies TCC at standstill.**
Mechanical impostors (Sonnax-documented, more common at 100k+ mi): cracked
1-2-3-4 apply piston, stuck 1-2-3-4 / 3-5-R regulator valves, displaced #1/#5
checkballs, popped 1-2-3-4 snap ring — these produce exactly "no move
forward / no reverse".

Sources: sonnax.com/tech_resources/1216 · sonnax.com/tech_resources/51 ·
forum.hptuners.com/showthread.php?88988 · ls1tech.com/forums/1968310
