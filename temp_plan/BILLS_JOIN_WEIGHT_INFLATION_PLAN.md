# Plan: exported weights are ~5.5% high because the utility-bills join duplicates rows

Written 2026-10-07 from the dashboard session (PR #463). Branch for this work: off `main`
(`3c103063`), its own worktree, pushes to the branch only, PR to main. The owner commits,
pushes and opens the PR; the session prepares the changes.

## 1. What is wrong, with the evidence

**Symptom.** Every dashboard built so far shows exported floor area +4.6% to +6.9% above
CBECS 2018 by building type (+5.4% stock-wide), although `create_allocated_weights_scaled_to_cbecs`
scales each type to CBECS exactly. Tracked as X4 / PR-B / gotcha 3 in
`temp_plan/RESULTS_DASHBOARD_PLAN.md` on `ccaradon/calibration-qaqc`.

**The allocation draw and the CBECS scaling are right.** The inflation enters AFTER them, in
`ComStock.create_allocated_weights_plus_util_bills_for_upgrade` (comstock.py:2397 on main):

1. The `utility_bills` reporting measure (`measures/utility_bills/measure.rb`:389-557) bills the
   building for every state its sampling region can land in, and for every utility in that
   state. It writes one block `<eia_id>:<45 stats>|` per (state, utility) into
   `out.utility_bills.electricity_utility_bill_results`, **without the state**. 28 of the 61
   sampling regions span 2-4 states (`resources/sampling_region_to_tracts.json`), so a utility
   serving tracts in two states of a region appears twice in the string, once per state (the
   `state_eia_map` dedupe at :335 is per state only). The two blocks differ only by the state's
   rate escalation (`pct_inc = (2022 - rate_start_year) * state_elec_ann_incr`, :505).
2. Postprocessing explodes that string into one row per block and left-joins it onto the
   allocated weights on `(bldg_id, in.electric_utility_eia_code)` (comstock.py:2459-2500). A
   repeated EIA id matches every allocated row of that building in that utility's tracts twice
   (or three or four times), and every copy carries the full weight.

**Measured on the fanfix run's local caches, 2026-10-07**
(`output/ComStock str_100k_new_sample_plugfix_fanfix`, probes in
`scratchpad/alloc/probe_bills_fanout.py` and `probe_duplicate_blocks.py`):

| | rows | weight |
|---|---|---|
| `cached_ComStock_alloc_wts_scaled_to_cbecs.parquet` (input to the bills stage) | 14,007,775 | 4,513,892 |
| `cached_allocated_weights_plus_bills/upgrade=0` (what is exported) | 14,784,334 | — |
| fan-out implied by the repeated EIA ids alone | 14,784,334 (**exact match**) | 4,771,436 (+5.71%) |

- 29,454 of 103,605 baseline models (28.4%) repeat an EIA id; every one of them is a
  multi-state building. 1,863,703 blocks for 1,799,775 unique (bldg, eia) pairs.
- Of the 63,928 repeated blocks, 30,642 are byte-identical and 33,286 differ; the mean bill
  differs by a median 8.3% (p90 14.8%, max 20.6%) between repeats — the state escalation.
- The state-average strings (`state_average_*_cost_results`) have one block per state, no
  repeats, so the state-bill joins (:2561) are clean; `tract_to_elec_util_v2.csv` is one row
  per tract (108,660), so the tract→utility join (:2444) is clean too.
- **The inflation is far from uniform by state**, which matters more than the 5% national
  figure: ID +77%, VA +62%, ND +60%, SD +49%, WI +42%, IA +33%, KS +22%, IN +22% …
  while many states (WY, SC, HI, …) are exactly 0%. National by-type totals look like a
  flat +5% only because the affected states average out.

**What inherits it.** Everything built from the bills stage: `metadata_and_annual_results`
and `_aggregates` (national, by_state, by_state_and_county, by_state_and_puma), the Athena
tables crawled from them, the results dashboards, SightGlass loads, and the published
releases since the bills join was introduced (energy, GHG, bills and floor area alike, by the
per-state factors above). The dashboard deliberately reads the data as is (gotcha 3).

## 2. The fix

### 2a. Postprocessing (this PR) — stop the fan-out

Factor the string parsing out of `create_allocated_weights_plus_util_bills_for_upgrade` into a
testable helper (e.g. `_electricity_bills_by_utility(sim_outs) -> LazyFrame`) and make it return
**exactly one row per (bldg_id, eia_id[, state])**. Two levels, decide which (question 1):

- **B — minimal, weights exact.** Collapse repeated (bldg, eia) blocks to one (first block; or
  the mean of the numeric fields with the first labels). Weights, floor area, energy and GHG
  become exact. Bills on the ~5% of allocated rows that were duplicated carry one state's
  escalation instead of their own (median 8% off on those rows only). Half a day.
- **A — state-exact bills as well.** Recover each block's state: blocks are written in the
  order of the building's state list (the same order as its `state_average_electricity_cost_results`
  string), and within a state in the order utilities first appear in the region's tracts; the
  measure's own `sampling_region_to_tracts.json` + `tract_to_elec_util_v2.csv` give, per
  (sampling region, state), the ordered utility list. Reconstruct `(bldg, eia, state)` and join
  on the allocated row's state too (`in.state` is on the draw). Fall back to B where the
  reconstruction is ambiguous, and log how often. One to two days, more test surface.

Either way add the **invariant that was missing**: after the bills joins,
`alloc_wts` row count must equal the scaled draw's row count — assert it (fail loudly, with the
offending key) rather than warn. A unit test with a synthetic sim-outs frame carrying a repeated
EIA id and a 10-row draw pins it.

### 2b. Cache invalidation (this PR)

Every existing `cached_allocated_weights_plus_bills/` folder is inflated and the code reuses a
folder whenever it exists. Write a small marker (`_bills.json` with `bills_join_version: 2`,
keep the name distinct from `_allocation.json`, which `ccaradon/calibration-qaqc` adds to the
same folder) and rebuild when it is absent or older, renaming the old folder
`cached_allocated_weights_plus_bills.stale_<reason>_<timestamp>` — the convention already used
in these output folders. Log the rebuild and why.

### 2c. Measure (follow-up, needs new simulations; for the measure's owner)

`measure.rb:451` writes `"#{elec_eia_id}:"`; keying the block by state as well
(e.g. `"#{elec_eia_id}@#{state_abbreviation}:"`, so the field count is unchanged) makes
future runs exact without reconstruction. The postprocessing parser should accept both forms
from the start (prefer the state in the key when present). Separate PR unless the owner wants
it here.

## 3. Verification

1. Unit tests (`postprocessing/test/test_utility_bills_join.py`): repeated EIA id → one row;
   row count preserved; state-exact assignment (if A); old and new key formats parse.
2. Fanfix run, locally, from the existing caches (no Athena needed): rebuild upgrade 0 bills →
   rows == 14,007,775; weighted floor area by building type vs `CBECS wide.csv` == 0.00%
   (today +4.6..6.9%); by-state weight totals drop by the factors above; bills totals change
   and are reported before/after.
3. Re-export the runs in use (question 2), re-crawl, rebuild their dashboards: the findings
   table's floor-area rows read 0%; the Coverage tab's weight-basis sentence follows the data.
4. Add a change-doc entry (the `documentation/` change docs added by #449) describing the
   correction and the per-state magnitude, for the next release notes.

## 4. Sequencing and interactions

- `ccaradon/calibration-qaqc` (PR #463) also edits `create_allocated_weights_plus_util_bills_for_upgrade`
  (the `_allocation.json` marker check at the top) and `create_allocated_weights`. Land this fix
  on main first — small and reviewable — then the dashboard branch merges main as usual; keep
  this fix's edits in the new helper to make that merge trivial.
- Closes X4 / PR-B / gotcha 3 in the dashboard plan once the runs it compares are re-exported.
- Published releases (OEDI): `git log -S util_bills_by_eia_id` dates the join; every release
  exported since is affected. Owner's decision: re-export, or a known-issue note with the
  per-state factors.
- Hospital resampling and the measure-failure work are unaffected (they do not read the bills
  stage).
- **Branch `claude/comstock-column-audit-9db305`** (session "ComStock column audit", worktree
  `.claude/worktrees/comstock-baseline-weights-766b02`, active 2026-10-08, pushed) also edits
  `create_allocated_weights_plus_util_bills_for_upgrade`: commit `c372f7d1` rewrites the
  state-average fill block (~:2563-2574 on main) so `num_bills` is no longer nulled. The
  inflation fix lives 60-100 lines above it (the explode + join, :2459-2500) plus an assertion
  after the joins; keep it there and the two merge without a conflict. Land the inflation fix
  first; the column-audit PR rebases.

## 5. Work plan

1. Branch + worktree (section 6). Copy this plan to `temp_plan/BILLS_JOIN_WEIGHT_INFLATION_PLAN.md`
   there, untracked unless the owner wants it in the PR.
2. Reproduce on the fanfix caches with the two probe scripts (15 s each); keep their numbers in
   this file.
3. Implement 2a (B first; A if chosen) + the row-count assertion + tests.
4. Implement 2b; run the fanfix rebuild (verification 2); record before/after.
5. README (postprocessing, bills paragraph) and change doc.
6. Owner commits and opens the PR; after merge, re-export the agreed runs and rebuild the
   dashboards (dashboard session), then update the dashboard plan's X4/PR-B/gotcha 3.

## 6. Branch and worktree recipe

Main checkout is on `main` @ `3c103063` = `origin/main` (2026-10-07). Global
`branch.autoSetupMerge=simple` is set, so a branch made from local `main` has NO upstream;
the first Desktop "Publish branch" sets `origin/<branch>`. Before any push, `git status -sb`
in the worktree must show `## <branch>` with no `...origin/main`.

Option 1 — new Code-tab session with worktree isolation: the app makes
`.claude/worktrees/<slug>` from the main checkout's HEAD (= main) and names the branch
`claude/<slug>` (branch prefix setting is "claude"; switch it to `ccaradon` first if the branch
should carry your prefix). Option 2 — from a terminal in the repo:

    git worktree add -b ccaradon/fix_bills_join_weight_inflation .claude/worktrees/bills-join-weight-inflation main

then open a session in that folder. Desktop follows the branch into the worktree for commits.

## 7. Open questions (answers change the work)

1. B (weights exact) or A (weights + state-exact bills)?
2. Which runs to re-export after merge: fanfix, plugfix, new_sample, fixes_ts, baseline_10k,
   the hospital runs, `sdr_2025_r4_103224_baseline_2`? Published releases: re-export or note?
3. Cache handling: marker + `.stale_` rename (recommended) or a new cache folder name?
4. Measure change 2c in this PR or its own?
5. Branch name. (The `comstock-baseline-weights-766b02` worktree is taken by the column-audit
   session; the branch of that name is an unused leftover equal to main — a fresh app-made
   worktree is the clean start.)

## 8. Implementation and verification, 2026-10-13

Branch `ccaradon/fix_bills_join_weight_inflation` (from local `main` @ `3c103063`, no upstream).
Level **B** chosen; repeated (bldg, eia) blocks keep the **first** block (the building's first state).
Cache handling: marker + `.stale_` rename.

- `comstockpostproc/utility_bills_join.py` (new): `electricity_bills_by_utility` (parse + collapse,
  also accepts the 2c `<eia>@<state>:` key and then joins on `in.state`; a run mixing both formats
  raises), `assert_unique_on` (every right-hand join frame: tract map, bills by utility, the four
  state-average frames), `assert_row_count_preserved` (after the joins), `_bills.json` marker
  (`bills_join_version: 2`) and `retire_stale_bills_cache`
  (`cached_allocated_weights_plus_bills.stale_bills_join_v1_<YYYYmmdd-HHMMSS>`).
- `comstock.py`: `create_allocated_weights_plus_util_bills_for_upgrade` uses the helpers;
  `get_allocated_weights_plus_util_bills_for_upgrade` refuses an unmarked/old cache (the export
  reads through it).
- `test/test_utility_bills_join.py`: 10 tests (collapse, empty strings, state-keyed parse + join,
  mixed formats, uniqueness/row-count guards, stale rename + marker, the full bills stage on a
  10-row draw, the getter guard, a fanned-out tract map refused).

Fanfix rebuild of upgrade 0 from the caches (driver in the session scratchpad,
output in the worktree's `postprocessing/output/fanfix_bills_verify`, main checkout untouched):

| | rows | weight |
|---|---|---|
| scaled draw | 14,007,775 | 4,513,892 |
| old bills cache | 14,784,334 | 4,771,436 |
| new bills cache | 14,007,775 | 4,513,892 |

- Collapsed 63,928 repeated blocks in 29,454 buildings (= the probe); 796 empty strings left out.
- Floor area vs CBECS 2018 by building type: old +4.59% (Warehouse) .. +6.93% (Hospital),
  stock-wide +5.38%; new 0.00% for all 15 types.
- By-state weight vs the draw: old ID +76.69, VA +62.30, ND +59.53, SD +48.59, WI +42.39,
  IA +33.34, KS +22.20, IN +21.91, MO +18.72 ...; new 0 for every state.
- Weighted electricity bill (mean) $122.64B -> $116.82B (-4.75%); total bill (mean)
  $154.93B -> $147.39B (-4.87%).

Not done here: README bills paragraph and the change doc (5.5), re-exports (3.3), measure change (2c).
