# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
"""Parsing and joining the per-utility electricity bill results onto the allocated weights.

The utility_bills measure bills each building for every state its sampling region can land in,
and for every utility in that state, writing one ``<eia_id>:<values>|`` block per
(state, utility). A utility serving tracts in two states of a region therefore appears twice in
the string. Joined on (bldg_id, eia_id) as is, every repeat duplicates the allocated rows of that
building in that utility's tracts, each copy carrying the full weight (+5.5% nationally, up to
+77% in a state). The helpers here return exactly one bills row per join key, and fail loudly
when a join would change the row count.

Blocks keyed as ``<eia_id>@<state>:<values>`` (a planned measure change) carry their state and
are joined on the allocated row's state as well.
"""

import datetime
import json
import logging

import polars as pl

logger = logging.getLogger(__name__)

# Bump when the bills join changes in a way that makes cached results wrong.
# 1: original join, duplicated rows for repeated EIA ids. 2: one bills row per join key.
BILLS_JOIN_VERSION = 2
BILLS_MARKER_FILE_NAME = '_bills.json'

BILL_STATE = 'utility_bill_state'


def electricity_bills_by_utility(sim_outs, bldg_id_col, results_col, eia_id_col, value_cols,
                                 keep_cols=()):
    """One row per (building, EIA id), or per (building, EIA id, state) for state-keyed blocks.

    Repeated EIA ids in the old key format are collapsed to their first block (the building's
    first state, in the measure's order). The returned frame carries ``BILL_STATE`` (null for
    the old key format) and the measure's value columns, with empty strings as nulls and the
    EIA id and ``..usd`` columns cast to Int64.
    """
    tsc = 'tsc'
    key = '_bill_key'
    bills = (
        sim_outs
        .select([bldg_id_col, results_col, *keep_cols])
        .with_columns(pl.col(results_col).cast(pl.String))
        # Create a new row for each block in the results string
        .with_columns(pl.col(results_col).str.strip_chars_start('|').str.strip_chars_end('|').str.split('|'))
        .explode(results_col)
        .with_columns(pl.col(results_col).str.split(':').alias(tsc))
        # NOTE: Column name order must match the order in utility_bills/measure.rb!
        .with_columns(pl.col(tsc).list.to_struct('max_width', [key] + list(value_cols)))
        .unnest(tsc)
        .drop(results_col)
    )

    # Split '<eia_id>@<state>' keys; the old '<eia_id>' key has no state
    bills = bills.with_columns(
        pl.col(key).str.split_exact('@', 1).struct.rename_fields([eia_id_col, BILL_STATE])
    ).unnest(key)

    # Replace empty strings with nulls in the new columns
    new_cols = [eia_id_col, BILL_STATE] + list(value_cols)
    bills = bills.with_columns(
        [pl.when(pl.col(c) == '').then(None).otherwise(pl.col(c)).alias(c) for c in new_cols]
    )

    # Convert the EIA ID and bill column dtypes to integers
    cols_to_int = [eia_id_col] + [c for c in value_cols if '..usd' in c]
    bills = bills.with_columns([pl.col(c).cast(pl.Int64) for c in cols_to_int])

    # NOTE: need to collect here, otherwise the lazyframe query optimization breaks down
    bills = bills.collect()

    # Buildings without bill results explode to a single empty block; keep them out of the join
    n_empty = bills.select(pl.col(eia_id_col).is_null().sum()).item()
    bills = bills.filter(pl.col(eia_id_col).is_not_null())
    keys = [bldg_id_col, eia_id_col, BILL_STATE]
    repeated = bills.filter(pl.len().over(keys) > 1)
    if repeated.height:
        n_bldgs = repeated.select(pl.col(bldg_id_col).n_unique()).item()
        n_extra = repeated.height - repeated.select(keys).unique().height
        logger.info(f'Collapsed {n_extra:,} repeated electricity bill blocks in {n_bldgs:,} buildings to one row '
                    f'per {keys}, keeping the first block')
    if n_empty:
        logger.info(f'Left {n_empty:,} empty electricity bill blocks out of the join '
                    f'(buildings without bill results by utility)')
    bills = bills.unique(subset=keys, keep='first', maintain_order=True)
    return bills.lazy()


def bills_join_keys(bills, bldg_id_col, eia_id_col, state_col):
    """Join keys for a frame from electricity_bills_by_utility.

    State-keyed results join on the allocated row's state too. A run mixing both key formats
    has no single correct join and raises.
    """
    n_keyed, n_total = bills.select(
        pl.col(BILL_STATE).is_not_null().sum(), pl.len()
    ).collect().row(0)
    if n_keyed == 0:
        return bills.drop(BILL_STATE), [bldg_id_col, eia_id_col]
    if n_keyed != n_total:
        raise ValueError(f'Electricity bill results mix state-keyed and unkeyed blocks '
                         f'({n_keyed:,} of {n_total:,} keyed); the runs need the same utility_bills measure version')
    return bills.rename({BILL_STATE: state_col}), [bldg_id_col, eia_id_col, state_col]


def assert_unique_on(lf, keys, what):
    """Raise if a right-hand join frame has more than one row for any key, naming examples."""
    dups = (
        lf.group_by(keys).agg(pl.len().alias('_n'))
        .filter(pl.col('_n') > 1)
        .sort('_n', descending=True)
        .collect()
    )
    if dups.height:
        raise ValueError(f'{what} has {dups.height:,} duplicated join keys {keys}; joining it would duplicate '
                         f'allocated rows and inflate the weights. First offending keys:\n{dups.head(5)}')


def assert_row_count_preserved(n_before, n_after, what):
    if n_before != n_after:
        raise ValueError(f'{what} changed the allocated weights row count from {n_before:,} to {n_after:,} '
                         f'({n_after - n_before:+,}); every copy of a row carries its full weight')


def read_bills_marker(bills_root, fs):
    path = f'{bills_root}/{BILLS_MARKER_FILE_NAME}'
    if not fs.exists(path):
        return None
    with fs.open(path, 'r') as f:
        return json.load(f)


def write_bills_marker(bills_root, fs):
    path = f'{bills_root}/{BILLS_MARKER_FILE_NAME}'
    if fs.exists(path):
        return
    marker = {
        'bills_join_version': BILLS_JOIN_VERSION,
        'written': datetime.datetime.now().isoformat(timespec='seconds'),
    }
    with fs.open(path, 'w') as f:
        json.dump(marker, f, indent=2)


def bills_cache_version(bills_root, fs):
    """Bills join version a cache was built with; unmarked caches predate the marker (version 1)."""
    marker = read_bills_marker(bills_root, fs)
    return (marker or {}).get('bills_join_version', 1)


def retire_stale_bills_cache(bills_root, fs):
    """Rename a bills cache built by an older join so it is rebuilt.

    The folder becomes ``<bills_root>.stale_bills_join_v<N>_<timestamp>``, the convention used
    for stale caches in the output folders. Returns the new path, or None if nothing was renamed.
    """
    if not fs.exists(bills_root):
        return None
    marker = read_bills_marker(bills_root, fs)
    version = (marker or {}).get('bills_join_version', 1)
    if version >= BILLS_JOIN_VERSION:
        return None
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    stale_path = f'{bills_root}.stale_bills_join_v{version}_{stamp}'
    reason = 'has no ' + BILLS_MARKER_FILE_NAME if marker is None else f'is bills join version {version}'
    logger.warning(f'{bills_root} {reason}; its weights are inflated by repeated EIA ids in the bill results. '
                   f'Moving it to {stale_path} and rebuilding the bills (current version {BILLS_JOIN_VERSION}).')
    fs.mv(bills_root, stale_path, recursive=True)
    return stale_path
