# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
"""Build a self-contained, interactive viewer of ComStock building operating hours.

Reads the ``weekday_start_time``, ``weekend_start_time``, ``weekday_duration`` and
``weekend_duration`` TSVs out of a ``sampling/tsvs/tsvs-vNN.zip`` archive and writes a
single HTML file with the probability distributions embedded as JSON.

The start time TSVs give P(start | building_type); the duration TSVs give
P(duration | building_type, start_time). End time is start + duration, so the marginal
end time distribution for a building type is the start-weighted mixture of the
conditional duration distributions:

    P(end = e) = sum_s P(start = s) * P(duration = e - s | s)

Usage:
    python generate_operating_hours_viz.py                # newest tsvs-vNN.zip
    python generate_operating_hours_viz.py --version v33
    python generate_operating_hours_viz.py --zip path/to/tsvs-v33.zip --out viewer.html
"""

import argparse
import io
import json
import logging
import re
import sys
import zipfile
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

HERE = Path(__file__).resolve().parent
TSV_DIR = HERE.parent / 'tsvs'
TEMPLATE = HERE / 'operating_hours_template.html'

DAY_TYPES = ('weekday', 'weekend')
# Probabilities are rounded before being embedded in the HTML to keep the file small.
ROUND_DECIMALS = 7
# Rows whose probabilities sum to something further than this from 1.0 are logged.
SUM_TOLERANCE = 1e-3


def newest_tsv_zip(tsv_dir=TSV_DIR):
    """Return the path to the highest-numbered tsvs-vNN.zip in tsv_dir."""
    versioned = []
    for path in tsv_dir.glob('tsvs-v*.zip'):
        match = re.match(r'tsvs-v(\d+)\.zip$', path.name)
        if match:
            versioned.append((int(match.group(1)), path))
    if not versioned:
        raise FileNotFoundError(f'No tsvs-v*.zip archives found in {tsv_dir}')
    return max(versioned)[1]


def read_tsv_from_zip(archive, name):
    """Read a TSV named <name>.tsv from anywhere inside the open zipfile."""
    matches = [n for n in archive.namelist() if Path(n).name == f'{name}.tsv']
    if not matches:
        raise KeyError(f'{name}.tsv not found in {archive.filename}')
    with archive.open(matches[0]) as f:
        return pd.read_csv(io.BytesIO(f.read()), sep='\t')


def split_columns(df):
    """Return (dependency columns, option columns, option values as floats)."""
    dep_cols = [c for c in df.columns if c.startswith('Dependency=')]
    opt_cols = [c for c in df.columns if c.startswith('Option=')]
    opt_vals = [float(c.split('=', 1)[1]) for c in opt_cols]
    # Keep options in ascending numeric order regardless of column order in the file.
    order = np.argsort(opt_vals)
    opt_cols = [opt_cols[i] for i in order]
    opt_vals = [opt_vals[i] for i in order]
    return dep_cols, opt_cols, opt_vals


def normalize_rows(values, label):
    """Normalize each non-empty row to sum to 1, logging rows that were off.

    All-zero rows are left as zeros; the caller decides whether they matter.
    """
    values = np.asarray(values, dtype=float)
    sums = values.sum(axis=1)
    off = (np.abs(sums - 1.0) > SUM_TOLERANCE) & (sums > 0)
    if off.any():
        logger.warning('%s: %d of %d rows did not sum to 1.0 (min %.5f, max %.5f); renormalizing',
                       label, int(off.sum()), len(sums), sums[off].min(), sums[off].max())
    safe = np.where(sums > 0, sums, 1.0)
    return values / safe[:, None]


def collect_day_type(archive, day_type):
    """Build the JSON-ready distribution payload for one day type."""
    start_df = read_tsv_from_zip(archive, f'{day_type}_start_time')
    dur_df = read_tsv_from_zip(archive, f'{day_type}_duration')

    start_deps, start_opt_cols, start_times = split_columns(start_df)
    dur_deps, dur_opt_cols, durations = split_columns(dur_df)

    if start_deps != ['Dependency=building_type']:
        raise ValueError(f'{day_type}_start_time.tsv: unexpected dependencies {start_deps}')
    expected_dur_deps = ['Dependency=building_type', f'Dependency={day_type}_start_time']
    if sorted(dur_deps) != sorted(expected_dur_deps):
        raise ValueError(f'{day_type}_duration.tsv: unexpected dependencies {dur_deps}')

    start_df = start_df.rename(columns={'Dependency=building_type': 'building_type'})
    dur_df = dur_df.rename(columns={'Dependency=building_type': 'building_type',
                                    f'Dependency={day_type}_start_time': 'start_time'})
    dur_df['start_time'] = dur_df['start_time'].astype(float)

    building_types = sorted(start_df['building_type'].unique())

    start_pmf = normalize_rows(start_df.set_index('building_type')
                                       .loc[building_types, start_opt_cols].values,
                               f'{day_type}_start_time')

    # Conditional duration pmf: [building_type][start_time][duration]
    dur_lookup = dur_df.set_index(['building_type', 'start_time'])
    dur_pmf = np.zeros((len(building_types), len(start_times), len(durations)))
    missing = []
    for i, bt in enumerate(building_types):
        for j, st in enumerate(start_times):
            try:
                dur_pmf[i, j] = dur_lookup.loc[(bt, st), dur_opt_cols].values.astype(float)
            except KeyError:
                missing.append((bt, st))
    if missing:
        logger.warning('%s_duration.tsv: %d (building_type, start_time) combinations missing; '
                       'treated as zero probability. First few: %s',
                       day_type, len(missing), missing[:5])
    empty_dur = dur_pmf.sum(axis=2) <= 0
    for i, bt in enumerate(building_types):
        dur_pmf[i] = normalize_rows(dur_pmf[i], f'{day_type}_duration [{bt}]')

    # Start times that get sampled but have no duration distribution behind them. Their
    # probability mass cannot be placed on the end-time axis, so the viewer reports it
    # rather than quietly dropping it.
    gaps = []
    for i, bt in enumerate(building_types):
        for j, st in enumerate(start_times):
            if empty_dur[i, j] and start_pmf[i, j] > 0:
                gaps.append({'bt': i, 'start': j, 'p': round(float(start_pmf[i, j]), ROUND_DECIMALS)})
    if gaps:
        worst = max(gaps, key=lambda g: g['p'])
        logger.warning('%s: %d (building_type, start_time) pairs have non-zero start probability '
                       'but an all-zero duration row; largest is %s @ %s (%.2f%% of stock)',
                       day_type, len(gaps), building_types[worst['bt']],
                       start_times[worst['start']], 100 * worst['p'])

    return {
        'start_times': start_times,
        'durations': durations,
        'building_types': building_types,
        # start_pmf[bt_index][start_index]
        'start_pmf': np.round(start_pmf, ROUND_DECIMALS).tolist(),
        # dur_pmf[bt_index][start_index][duration_index]
        'dur_pmf': np.round(dur_pmf, ROUND_DECIMALS).tolist(),
        'gaps': gaps,
    }


def build_payload(zip_path):
    """Read every day type out of the archive and assemble the viewer payload."""
    with zipfile.ZipFile(zip_path) as archive:
        day_types = {dt: collect_day_type(archive, dt) for dt in DAY_TYPES}

    building_types = day_types[DAY_TYPES[0]]['building_types']
    for dt, payload in day_types.items():
        if payload['building_types'] != building_types:
            only_here = sorted(set(payload['building_types']) - set(building_types))
            only_there = sorted(set(building_types) - set(payload['building_types']))
            raise ValueError(f'Building types differ between day types. {dt} only: {only_here}; '
                             f'{DAY_TYPES[0]} only: {only_there}')

    version = re.sub(r'^tsvs-|\.zip$', '', Path(zip_path).name)
    return {
        'source': Path(zip_path).name,
        'version': version,
        'generated': datetime.now().strftime('%Y-%m-%d %H:%M'),
        'building_types': building_types,
        'day_types': {dt: {k: v for k, v in payload.items() if k != 'building_types'}
                      for dt, payload in day_types.items()},
    }


def render_html(payload, template_path=TEMPLATE):
    """Substitute the payload into the HTML template."""
    template = template_path.read_text(encoding='utf-8')
    if '__DATA__' not in template:
        raise ValueError(f'{template_path} does not contain the __DATA__ placeholder')
    data_json = json.dumps(payload, separators=(',', ':'))
    # Guard against the JSON prematurely closing the inline <script> block.
    data_json = data_json.replace('</', '<\\/')
    return template.replace('__DATA__', data_json)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', help='TSV version to read, e.g. v33. Defaults to the newest '
                                          'tsvs-v*.zip in sampling/tsvs.')
    parser.add_argument('--zip', dest='zip_path', help='Explicit path to a tsvs zip archive. '
                                                       'Overrides --version.')
    parser.add_argument('--out', help='Output HTML path. Defaults to '
                                      'sampling/visualization/operating_hours_<version>.html')
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
    logger.info('Loaded %d building types, %d start times, %d durations',
                len(payload['building_types']),
                len(payload['day_types']['weekday']['start_times']),
                len(payload['day_types']['weekday']['durations']))

    out_path = Path(args.out) if args.out else HERE / f"operating_hours_{payload['version']}.html"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_html(payload), encoding='utf-8')
    logger.info('Wrote %s (%.1f MB)', out_path, out_path.stat().st_size / 1e6)
    return 0


if __name__ == '__main__':
    sys.exit(main())
