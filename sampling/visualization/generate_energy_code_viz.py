# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
"""Build a self-contained, interactive viewer of the energy code in force at the time of a
building's last HVAC replacement, stacked by year of original construction.

`energy_code_in_force_during_last_hvac_replacement.tsv` depends on `state_id` and
`year_bin_of_last_hvac_replacement`, which in turn depends on `year_of_simulation` and
`year_built`. Composing the two gives the quantity plotted on the stacked bar chart:

    P(code | state, year_built) = sum_bin P(bin | year_of_sim, year_built) * P(code | state, bin)

Neither TSV depends on building type, so for a single selected state the building type filter
does not change those conditional columns. What it does change is how much stock sits behind
each construction year (and, with "All states" selected, the state mixture within a year). Those
weights come from the sampler's own dependency chain:

    P(building_type, state, year_built) = sum_region sum_size_bin
        P(region) * P(bt | region) * P(size | region, bt)
        * P(state | region, bt, size) * P(year_built | region, bt, size)

`tract` and `year_built` are sampled independently given (region, building type, size bin), so
that factorization matches how the sampler actually draws them. State is the four-character
prefix of the tract GISJOIN id.

The same weights can be expressed in floor area instead of building counts. `building_area` is
drawn from the same (region, building type, size bin) conditioning, so the expected area of a
building in a cell is

    E[area | region, bt, size] = sum_range P(range | region, bt, size) * total_bldg_floor_area(range)

with the per-range areas read from `resources/options_lookup.tsv`. Multiplying each cell's
contribution by that expectation turns the building-count weights into floor-area weights.

Usage:
    python generate_energy_code_viz.py                # newest tsvs-vNN.zip
    python generate_energy_code_viz.py --version v33
    python generate_energy_code_viz.py --zip path/to/tsvs-v33.zip --out viewer.html
"""

import argparse
import io
import json
import logging
import sys
import zipfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from generate_operating_hours_viz import TSV_DIR, newest_tsv_zip, read_tsv_from_zip

logger = logging.getLogger(__name__)

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / 'energy_code_template.html'
TRACT_LOOKUP = HERE.parent / 'resources' / 'spatial_tract_lookup_table_publish_v10.csv'
OPTIONS_LOOKUP = HERE.parent.parent / 'resources' / 'options_lookup.tsv'

CODE_TSV = 'energy_code_in_force_during_last_hvac_replacement'
BIN_TSV = 'year_bin_of_last_hvac_replacement'

# Conditional distributions are well scaled (values ~1e-2), joint weights are not, so they are
# stored as conditional year distributions plus a separate (building type, state) mass.
# 6 decimals keeps row sums within 3e-5 of 1 (the viewer renormalizes) at a third less file size.
ROUND_DECIMALS = 6


def read_json_from_zip(archive, name):
    matches = [n for n in archive.namelist() if Path(n).name == f'{name}.json']
    if not matches:
        raise KeyError(f'{name}.json not found in {archive.filename}')
    return json.loads(archive.read(matches[0]))


def read_floor_areas(path=OPTIONS_LOOKUP):
    """Map each building_area option to its total_bldg_floor_area from options_lookup.tsv."""
    if not path.is_file():
        raise FileNotFoundError(f'options_lookup.tsv not found: {path}')
    areas = {}
    with open(path, encoding='utf-8') as f:
        next(f, None)                      # header
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 2 or parts[0] != 'building_area':
                continue
            # the argument's column position is not fixed, so scan the measure arguments
            for cell in parts[2:]:
                if cell.startswith('total_bldg_floor_area='):
                    areas[parts[1]] = float(cell.split('=', 1)[1])
                    break
    if not areas:
        raise ValueError(f'No building_area rows with total_bldg_floor_area found in {path}')
    logger.info('Read %d building_area floor areas from %s (%.0f-%.0f ft2)',
                len(areas), path.name, min(areas.values()), max(areas.values()))
    return areas


def option_frame(df, dep_names):
    """Return (dependency frame, option value matrix, option labels) with rows normalized.

    Options are kept in file order: energy code names are categorical, and the TSV ships them
    in chronological order within each code family.
    """
    dep_cols = [c for c in df.columns if c.startswith('Dependency=')]
    opt_cols = [c for c in df.columns if c.startswith('Option=')]
    got = [c.split('=', 1)[1] for c in dep_cols]
    if got != dep_names:
        raise ValueError(f'Expected dependencies {dep_names}, found {got}')
    values = df[opt_cols].values.astype(float)
    sums = values.sum(axis=1)
    bad = np.abs(sums - 1.0) > 1e-3
    if bad.any():
        logger.warning('%d rows do not sum to 1.0 (min %.5f); renormalizing', int(bad.sum()),
                       sums[bad].min())
    values = values / np.where(sums > 0, sums, 1.0)[:, None]
    labels = [c.split('=', 1)[1] for c in opt_cols]
    return df[dep_cols].rename(columns=lambda c: c.split('=', 1)[1]), values, labels


def build_conditionals(archive):
    """P(code | state, hvac bin) and P(hvac bin | year_built), plus their axes."""
    code_df = read_tsv_from_zip(archive, CODE_TSV)
    deps, code_vals, codes = option_frame(code_df, ['state_id', 'year_bin_of_last_hvac_replacement'])

    states = sorted(deps['state_id'].unique())
    bins_ = list(dict.fromkeys(deps['year_bin_of_last_hvac_replacement'].astype(str)))

    state_ix = {s: i for i, s in enumerate(states)}
    bin_ix = {b: i for i, b in enumerate(bins_)}
    p_code = np.zeros((len(states), len(bins_), len(codes)))
    seen = np.zeros((len(states), len(bins_)), dtype=bool)
    for row, (s, b) in enumerate(zip(deps['state_id'], deps['year_bin_of_last_hvac_replacement'])):
        i, j = state_ix[s], bin_ix[str(b)]
        p_code[i, j] = code_vals[row]
        seen[i, j] = True
    if not seen.all():
        logger.warning('%s: %d of %d (state, bin) combinations missing',
                       CODE_TSV, int((~seen).sum()), seen.size)

    # P(hvac bin | year_built), averaged over the year_of_simulation distribution.
    sim_df = read_tsv_from_zip(archive, 'year_of_simulation')
    _, sim_vals, sim_years = option_frame(sim_df, [])
    sim_weight = {int(y): float(p) for y, p in zip(sim_years, sim_vals[0]) if p > 0}
    logger.info('year_of_simulation distribution: %s', sim_weight)

    bin_df = read_tsv_from_zip(archive, BIN_TSV)
    bdeps, bin_vals, bin_opts = option_frame(bin_df, ['year_of_simulation', 'year_built'])
    # The two TSVs list the bins in opposite order, so align them by label rather than position.
    if set(str(b) for b in bin_opts) != set(bins_):
        raise ValueError(f'{BIN_TSV} options do not match the {CODE_TSV} bin dependency values')
    bin_cols = [bin_ix[str(b)] for b in bin_opts]

    years = sorted(int(y) for y in bdeps['year_built'].unique())
    year_ix = {y: i for i, y in enumerate(years)}
    p_bin = np.zeros((len(years), len(bins_)))
    covered = 0.0
    for sim_year, weight in sim_weight.items():
        mask = bdeps['year_of_simulation'].astype(int) == sim_year
        if not mask.any():
            logger.warning('%s has no rows for year_of_simulation=%s; its %.1f%% weight is dropped',
                           BIN_TSV, sim_year, 100 * weight)
            continue
        covered += weight
        for row_ix, yb in zip(np.flatnonzero(mask.values), bdeps.loc[mask, 'year_built'].astype(int)):
            p_bin[year_ix[yb], bin_cols] += weight * bin_vals[row_ix]
    if covered <= 0:
        raise ValueError(f'No {BIN_TSV} rows matched the year_of_simulation distribution')
    p_bin /= covered

    # Construction years later than the simulation year have no replacement-year distribution
    # (the building does not exist yet), so drop them from the axis.
    keep = p_bin.sum(axis=1) > 0
    if not keep.all():
        logger.info('Dropping %d construction year(s) with no %s rows for the simulation year: %s',
                    int((~keep).sum()), BIN_TSV, [years[i] for i in np.flatnonzero(~keep)])
        years = [y for y, k in zip(years, keep) if k]
        p_bin = p_bin[keep]

    return {'states': states, 'bins': bins_, 'codes': codes, 'years': years,
            'p_code': p_code, 'p_bin': p_bin}


def build_weights(archive, states, years, floor_areas):
    """Joint P(building_type, state, year_built), by building count and by floor area."""
    _, region_vals, region_opts = option_frame(read_tsv_from_zip(archive, 'sampling_region'), [])
    p_region = {r: float(p) for r, p in zip(region_opts, region_vals[0])}

    bt_deps, bt_vals, building_types = option_frame(
        read_tsv_from_zip(archive, 'building_type'), ['sampling_region'])
    p_bt = {str(r): bt_vals[i] for i, r in enumerate(bt_deps['sampling_region'])}

    sz_deps, sz_vals, size_bins = option_frame(
        read_tsv_from_zip(archive, 'size_bin'), ['sampling_region', 'building_type'])
    p_size = {(str(r), bt): sz_vals[i] for i, (r, bt)
              in enumerate(zip(sz_deps['sampling_region'], sz_deps['building_type']))}

    # Expected floor area of a building in each (region, building type, size bin) cell.
    ba_deps, ba_vals, ba_opts = option_frame(
        read_tsv_from_zip(archive, 'building_area'),
        ['sampling_region', 'building_type', 'size_bin'])
    unknown = [o for o in ba_opts if o not in floor_areas]
    if unknown:
        raise ValueError(f'building_area options missing from options_lookup.tsv: {unknown}')
    area_of_option = np.array([floor_areas[o] for o in ba_opts])
    mean_area = {(str(r), bt, str(sz)): float(ba_vals[i] @ area_of_option)
                 for i, (r, bt, sz) in enumerate(zip(ba_deps['sampling_region'],
                                                     ba_deps['building_type'],
                                                     ba_deps['size_bin']))}

    year_built = read_json_from_zip(archive, 'year_built')
    tracts = read_json_from_zip(archive, 'tract')

    state_ix = {s: i for i, s in enumerate(states)}
    year_ix = {y: i for i, y in enumerate(years)}
    bt_ix = {bt: i for i, bt in enumerate(building_types)}

    # weights[bt][state][year] accumulates the joint probability, by building count and by
    # floor area. building_area is drawn from the same conditioning as tract and year_built, so
    # a cell's expected area is a scalar multiplier on that cell's contribution.
    weights = np.zeros((len(building_types), len(states), len(years)))
    area_weights = np.zeros_like(weights)
    missing_size, missing_year, missing_tract, off_axis_years = 0, 0, 0, 0.0
    missing_area = 0

    for region, pr in p_region.items():
        if pr <= 0:
            continue
        bt_probs = p_bt.get(str(region))
        if bt_probs is None:
            logger.warning('sampling_region %s absent from building_type.tsv; skipped', region)
            continue
        for bt, pbt in zip(building_types, bt_probs):
            if pbt <= 0:
                continue
            size_probs = p_size.get((str(region), bt))
            if size_probs is None:
                missing_size += 1
                continue
            for size, psz in zip(size_bins, size_probs):
                if psz <= 0:
                    continue
                yb = year_built.get(str(region), {}).get(bt, {}).get(str(size))
                tr = tracts.get(str(region), {}).get(bt, {}).get(str(size))
                if yb is None:
                    missing_year += 1
                    continue
                if tr is None:
                    missing_tract += 1
                    continue
                # State is the four-character prefix of the tract GISJOIN id.
                by_state = defaultdict(float)
                for tract_id, p in tr.items():
                    by_state[tract_id[:4]] += p
                state_total = sum(by_state.values())

                year_arr = np.zeros(len(years))
                for y, p in yb.items():
                    idx = year_ix.get(int(y))
                    if idx is None:
                        off_axis_years += p
                        continue
                    year_arr[idx] = p
                year_total = year_arr.sum()
                if state_total <= 0 or year_total <= 0:
                    continue
                year_arr /= year_total

                cell = pr * pbt * psz
                area = mean_area.get((str(region), bt, str(size)))
                if area is None:
                    missing_area += 1
                    area = 0.0
                for st, ps in by_state.items():
                    si = state_ix.get(st)
                    if si is None:
                        logger.warning('tract prefix %s is not a state in %s; skipped', st, CODE_TSV)
                        continue
                    contribution = (cell * ps / state_total) * year_arr
                    weights[bt_ix[bt], si] += contribution
                    area_weights[bt_ix[bt], si] += contribution * area

    for label, count in (('size_bin', missing_size), ('year_built', missing_year),
                         ('tract', missing_tract), ('building_area', missing_area)):
        if count:
            logger.warning('%d (region, building type, size bin) combinations missing from %s',
                           count, label)
    if off_axis_years > 0:
        logger.warning('year_built entries outside the %s year axis carried %.4g total weight',
                       BIN_TSV, off_axis_years)

    total = weights.sum()
    logger.info('Joint weights sum to %.6f before normalization', total)
    weights /= total
    area_total = area_weights.sum()
    if area_total <= 0:
        raise ValueError('Floor-area weights are all zero; check building_area.tsv coverage')
    # area_total / total is the stock-average building floor area, a useful sanity check.
    logger.info('Mean building floor area across the stock: %.0f ft2', area_total / total)
    area_weights /= area_total
    return building_types, weights, area_weights


def state_names(states):
    """Map state_id (tract GISJOIN prefix) to a display name using the tract lookup table."""
    names = {}
    if TRACT_LOOKUP.is_file():
        cols = ['nhgis_tract_gisjoin', 'state_name', 'state_abbreviation']
        lookup = pd.read_csv(TRACT_LOOKUP, usecols=cols)
        lookup['state_id'] = lookup['nhgis_tract_gisjoin'].str[:4]
        for sid, grp in lookup.groupby('state_id'):
            names[sid] = f"{grp['state_name'].iloc[0]} ({grp['state_abbreviation'].iloc[0]})"
    else:
        logger.warning('%s not found; states will be labeled by id', TRACT_LOOKUP)
    missing = [s for s in states if s not in names]
    if missing:
        logger.warning('No name found for %d state ids: %s', len(missing), missing[:5])
    return [names.get(s, s) for s in states]


def build_payload(zip_path):
    floor_areas = read_floor_areas()
    with zipfile.ZipFile(zip_path) as archive:
        cond = build_conditionals(archive)
        building_types, weights, area_weights = build_weights(
            archive, cond['states'], cond['years'], floor_areas)

    # Split each joint into a (building type, state) mass and a conditional year distribution so
    # both stay numerically well scaled after rounding.
    def split(joint):
        mass = joint.sum(axis=2)
        return mass, np.divide(joint, np.where(mass > 0, mass, 1.0)[:, :, None])

    mass, year_pmf = split(weights)
    mass_area, year_pmf_area = split(area_weights)

    version = zip_path.name.replace('tsvs-', '').replace('.zip', '')
    return {
        'source': zip_path.name,
        'version': version,
        'generated': datetime.now().strftime('%Y-%m-%d %H:%M'),
        'codes': cond['codes'],
        'bins': cond['bins'],
        'years': cond['years'],
        'states': cond['states'],
        'state_names': state_names(cond['states']),
        'building_types': building_types,
        # p_code[state][bin][code]
        'p_code': np.round(cond['p_code'], ROUND_DECIMALS).tolist(),
        # p_bin[year][bin]
        'p_bin': np.round(cond['p_bin'], ROUND_DECIMALS).tolist(),
        # mass[bt][state] = P(building_type, state); year_pmf[bt][state][year] = P(year | bt, state)
        # The _area variants are the same quantities with each building weighted by its expected
        # floor area instead of counting as one building.
        'mass': np.round(mass, 9).tolist(),
        'year_pmf': np.round(year_pmf, ROUND_DECIMALS).tolist(),
        'mass_area': np.round(mass_area, 9).tolist(),
        'year_pmf_area': np.round(year_pmf_area, ROUND_DECIMALS).tolist(),
        'floor_areas': floor_areas,
    }


def render_html(payload, template_path=TEMPLATE):
    template = template_path.read_text(encoding='utf-8')
    if '__DATA__' not in template:
        raise ValueError(f'{template_path} does not contain the __DATA__ placeholder')
    return template.replace('__DATA__',
                            json.dumps(payload, separators=(',', ':')).replace('</', '<\\/'))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', help='TSV version to read, e.g. v33. Defaults to the newest '
                                          'tsvs-v*.zip in sampling/tsvs.')
    parser.add_argument('--zip', dest='zip_path', help='Explicit path to a tsvs zip archive.')
    parser.add_argument('--out', help='Output HTML path. Defaults to '
                                      'sampling/visualization/energy_code_hvac_<version>.html')
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

    if args.zip_path:
        zip_path = Path(args.zip_path)
    elif args.version:
        version = args.version if args.version.startswith('v') else f'v{args.version}'
        zip_path = TSV_DIR / f'tsvs-{version}.zip'
    else:
        zip_path = newest_tsv_zip()
    if not zip_path.is_file():
        parser.error(f'TSV archive not found: {zip_path}')
    logger.info('Reading %s', zip_path)

    payload = build_payload(zip_path)
    logger.info('%d codes, %d states, %d building types, %d construction years',
                len(payload['codes']), len(payload['states']),
                len(payload['building_types']), len(payload['years']))

    out_path = Path(args.out) if args.out else HERE / f"energy_code_hvac_{payload['version']}.html"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_html(payload), encoding='utf-8')
    logger.info('Wrote %s (%.1f MB)', out_path, out_path.stat().st_size / 1e6)
    return 0


if __name__ == '__main__':
    sys.exit(main())
