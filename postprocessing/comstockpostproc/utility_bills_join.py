# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
"""Parsing and joining the per-utility electricity bill results onto the allocated weights.

The utility_bills measure bills each building for every state its sampling region can land in,
and for every utility in that state, writing one block per (state, utility) into the bill
results string. A utility serving tracts in two states of a region therefore has one block per
state, each raised by that state's yearly price increase. Joined on (bldg_id, eia_id) alone,
every repeat duplicated the allocated rows of that building in that utility's tracts, each copy
carrying the full weight (+5.5% nationally, up to +77% in a state). Here every block gets its
state and the join is on (bldg_id, eia_id, state), so each allocated row gets its own state's
bill; the helpers fail loudly when a join would change the row count.

Blocks from measure versions that record the state end with it, ``<eia_id>:<values>:<state>|``.
Older blocks, ``<eia_id>:<values>|``, get their state from the order the measure writes them in
(``label_block_states``).
"""

import csv
import datetime
import json
import logging
import os

import polars as pl

logger = logging.getLogger(__name__)

# Bump when the bills join changes in a way that makes cached results wrong.
# 1: original join, duplicated rows for repeated EIA ids. 2: one row per (bldg, eia), first block
# kept. 3: one row per (bldg, eia, state), so each allocated row gets its own state's bill.
BILLS_JOIN_VERSION = 3
BILLS_MARKER_FILE_NAME = '_bills.json'
STALE_REASONS = {
    1: 'its weights are inflated by repeated EIA ids in the bill results',
    2: "rows of a utility that serves several states of a sampling region carry the first state's bill",
}

BILL_STATE = 'utility_bill_state'

# The measure's (sampling region, state, utility) lists, in its order, built from its resource
# files by build_bill_state_table. test_bill_state_table_matches_measure fails when they differ.
BILL_STATES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'resources',
                                'utility_bill_states_by_sampling_region.csv')
REGION, STATE, STATE_ORDER, EIA_ID = 'sampling_region_id', 'state', 'state_order', 'eia_id'
BILL_STATES_SCHEMA = {REGION: pl.String, STATE: pl.String, STATE_ORDER: pl.Int32, EIA_ID: pl.Int64}


def build_bill_state_table(measure_resources_dir):
    """The states and utilities the utility_bills measure bills each sampling region for, in its order.

    Mirrors measure.rb:306-336: the region's tracts in file order, each tract's state from GISJOIN
    characters 2-3 and its utility from tract_to_elec_util_v2.csv; states in order of first
    appearance and, within each, its utilities. A state without utilities has one row with a null
    EIA id, because it still takes its place in the order. Write it to BILL_STATES_FILE with
    ``build_bill_state_table(<repo>/measures/utility_bills/resources).write_csv(BILL_STATES_FILE)``.
    """
    with open(os.path.join(measure_resources_dir, 'sampling_region_to_tracts.json'), encoding='utf-8') as f:
        region_tracts = json.load(f)
    fips_to_state = {}
    with open(os.path.join(measure_resources_dir, 'state_abbrev_to_fips.json'), encoding='utf-8') as f:
        for abbrev, fips in json.load(f).items():
            fips_to_state.setdefault(fips, abbrev)  # Ruby's Hash#key returns the first match
    tract_to_util = {}
    with open(os.path.join(measure_resources_dir, 'tract_to_elec_util_v2.csv'), encoding='utf-8', newline='') as f:
        for row in csv.reader(f):
            tract_to_util[row[0]] = row[1] if len(row) > 1 and row[1] != '' else None

    rows = []
    for region, tracts in region_tracts.items():
        state_utils = {}
        for tract in tracts:
            state = fips_to_state.get(tract[1:3])
            if state is None:
                raise ValueError(f'Tract {tract} of sampling region {region} has no state in state_abbrev_to_fips.json')
            utils = state_utils.setdefault(state, [])
            util = tract_to_util.get(tract)
            if util is not None and util not in utils:
                utils.append(util)
        for order, (state, utils) in enumerate(state_utils.items()):
            rows += [(region, state, order, int(u)) for u in utils] or [(region, state, order, None)]
    return pl.DataFrame(rows, schema=BILL_STATES_SCHEMA, orient='row')


def read_bill_state_table(path=None):
    return pl.read_csv(path or BILL_STATES_FILE, schema=BILL_STATES_SCHEMA)


def label_block_states(blocks, models, bldg_id_col, eia_id_col, region_col, state_average_col, bill_states):
    """Give each block of the older format, which does not record its state, the state it was billed for.

    ``blocks`` has one row per block, in the order of each building's results string, and
    ``models`` one row per building with its sampling region and state-average electricity results.
    The measure loops over the region's states in the order its tracts first list them and, within
    each, over that state's utilities, writing a block for each utility with applicable rates
    (measure.rb:389-555). Applicability depends only on the building, so a utility has a block in
    every state it serves in the region or in none, and its k-th block belongs to the k-th of those
    states. Raises, naming the first offending buildings, if a building's state-average results list
    its states in another order than ``bill_states`` gives for its region, or if a utility's blocks
    do not match its states there: the run was simulated with other measure resource files, and its
    blocks' states cannot be told.
    """
    k, n, n_states, model_order, region_order = '_block_k', '_n_blocks', '_n_states', '_model_order', '_region_order'
    # The k-th block of each utility, counted in the order of the results string
    blocks = blocks.with_columns(
        pl.int_range(pl.len()).over(bldg_id_col, eia_id_col).alias(k),
        pl.len().over(bldg_id_col, eia_id_col).alias(n),
    )

    # Each building's state-average results must list the region's states in the measure's order
    orders = (
        bill_states.sort(REGION, STATE_ORDER)
        .group_by(REGION, maintain_order=True).agg(pl.col(STATE).unique(maintain_order=True))
        .select(pl.col(REGION).alias(region_col), pl.col(STATE).list.join(' ').alias(region_order))
    )
    checked = (
        models.join(blocks.select(bldg_id_col).unique(), on=bldg_id_col, how='semi')
        .with_columns(
            pl.col(state_average_col).str.strip_chars('|').str.split('|')
            .list.eval(pl.element().str.split(':').list.first()).list.join(' ').alias(model_order))
        .join(orders, on=region_col, how='left')
    )
    bad = checked.filter(pl.col(model_order).ne_missing(pl.col(region_order)))
    if bad.height:
        raise ValueError(
            f'{bad.height:,} buildings list their states in another order than the utility_bills measure gives for '
            f'their sampling region, so their bills cannot be matched to states; the run was simulated with other '
            f'measure resource files. First offending buildings:\n'
            f'{bad.select(bldg_id_col, region_col, model_order, region_order).head(5)}')

    # The k-th state, in the measure's order, where each utility serves tracts of each region
    states_by_k = (
        bill_states.filter(pl.col(EIA_ID).is_not_null())
        .sort(REGION, EIA_ID, STATE_ORDER)
        .select(
            pl.col(REGION).alias(region_col), pl.col(EIA_ID).alias(eia_id_col),
            pl.int_range(pl.len()).over(REGION, EIA_ID).alias(k),
            pl.len().over(REGION, EIA_ID).alias(n_states),
            pl.col(STATE).alias(BILL_STATE))
    )
    labeled = (
        blocks.join(models.select(bldg_id_col, region_col), on=bldg_id_col, how='left')
        .join(states_by_k, on=[region_col, eia_id_col, k], how='left')
    )
    bad = labeled.filter(pl.col(n).ne_missing(pl.col(n_states)))
    if bad.height:
        raise ValueError(
            f'{bad.height:,} electricity bill blocks do not match the states their utility serves in the building\'s '
            f'sampling region, so they cannot be matched to states; the run was simulated with other utility_bills '
            f'measure resource files. First offending blocks:\n'
            f'{bad.select(bldg_id_col, region_col, eia_id_col, k, n, n_states).head(5)}')

    n_repeated = labeled.filter(pl.col(n) > 1)
    logger.info(f'Matched {labeled.height:,} electricity bill blocks to their states by the utility_bills measure\'s '
                f'order; {n_repeated.height:,} of them belong to utilities billed in more than one state, in '
                f'{n_repeated.select(pl.col(bldg_id_col).n_unique()).item():,} buildings')
    return labeled.drop(region_col, k, n, n_states)


def electricity_bills_by_utility(sim_outs, bldg_id_col, results_col, eia_id_col, value_cols,
                                 region_col, state_average_col, keep_cols=(), bill_states=None):
    """One row per (building, EIA id, state): every block of the bill results, with its state.

    Blocks that end with their state keep it; older blocks get theirs from the measure's order
    (``label_block_states``, with ``bill_states`` or the table in BILL_STATES_FILE). A run mixing
    both formats raises. The returned frame carries ``BILL_STATE`` and the measure's value columns,
    with empty strings as nulls and the EIA id and ``..usd`` columns cast to Int64. ``results_col``
    keeps each row's block string, as the join always has, so the joined output has the same
    columns as before.
    """
    tsc = 'tsc'
    fields = [eia_id_col] + list(value_cols) + [BILL_STATE]
    blocks = (
        sim_outs
        .select([bldg_id_col, results_col, *keep_cols])
        .with_columns(pl.col(results_col).cast(pl.String))
        # Create a new row for each block in the results string
        .with_columns(pl.col(results_col).str.strip_chars_start('|').str.strip_chars_end('|').str.split('|'))
        .explode(results_col)
        .with_columns(pl.col(results_col).str.split(':').alias(tsc))
        # NOTE: Field order must match utility_bills/measure.rb; the state, its last field, is null
        # in results from measure versions that do not record it
        .with_columns(pl.col(tsc).list.to_struct('max_width', fields))
        .unnest(tsc)
    )

    # Replace empty strings with nulls in the new columns
    blocks = blocks.with_columns(
        [pl.when(pl.col(c) == '').then(None).otherwise(pl.col(c)).alias(c) for c in fields]
    )

    # Convert the EIA ID and bill column dtypes to integers
    cols_to_int = [eia_id_col] + [c for c in value_cols if '..usd' in c]
    blocks = blocks.with_columns([pl.col(c).cast(pl.Int64) for c in cols_to_int])

    # NOTE: need to collect here, otherwise the lazyframe query optimization breaks down
    blocks = blocks.collect()

    # Buildings without bill results explode to a single empty block; keep them out of the join
    n_empty = blocks.select(pl.col(eia_id_col).is_null().sum()).item()
    blocks = blocks.filter(pl.col(eia_id_col).is_not_null())
    if n_empty:
        logger.info(f'Left {n_empty:,} empty electricity bill blocks out of the join '
                    f'(buildings without bill results by utility)')

    n_with_state = blocks.select(pl.col(BILL_STATE).is_not_null().sum()).item()
    if n_with_state == 0:
        models = sim_outs.select(
            bldg_id_col, pl.col(region_col).cast(pl.String), pl.col(state_average_col).cast(pl.String)).collect()
        if bill_states is None:
            bill_states = read_bill_state_table()
        blocks = label_block_states(blocks.drop(BILL_STATE), models, bldg_id_col, eia_id_col, region_col,
                                    state_average_col, bill_states)
    elif n_with_state != blocks.height:
        raise ValueError(f'Electricity bill results mix blocks with and without their state ({n_with_state:,} of '
                         f'{blocks.height:,} with it); the runs need the same utility_bills measure version')
    else:
        bad = blocks.filter(~pl.col(BILL_STATE).str.contains(r'^[A-Z]{2}$'))
        if bad.height:
            raise ValueError(f'{bad.height:,} electricity bill blocks end with something other than a state '
                             f'abbreviation, e.g. {bad[BILL_STATE].head(3).to_list()}')
        logger.info(f'Read the state of {blocks.height:,} electricity bill blocks from the bill results')

    assert_unique_on(blocks.lazy(), [bldg_id_col, eia_id_col, BILL_STATE], 'Electricity bills by utility and state')
    return blocks.lazy()


def bills_join_keys(bills, bldg_id_col, eia_id_col, state_col):
    """The bills frame and keys to join it on: building, utility and the allocated row's state."""
    return bills.rename({BILL_STATE: state_col}), [bldg_id_col, eia_id_col, state_col]


def assert_rows_find_their_state(alloc_wts, bills, keys):
    """Raise if an allocated row's utility has bills for its building but none for the row's state.

    The measure bills a utility in every state of the region where it serves tracts, so such a row
    means the allocation's tract-to-utility map and the measure's disagree. The join would quietly
    give it the state-average bill instead.
    """
    bldg_id_col, eia_id_col, _ = keys
    missing = (
        alloc_wts.select(keys).unique()
        .join(bills.select(bldg_id_col, eia_id_col).unique(), on=[bldg_id_col, eia_id_col], how='semi')
        .join(bills.select(keys), on=keys, how='anti')
        .collect()
    )
    if missing.height:
        raise ValueError(f'{missing.height:,} combinations of {keys} among the allocated rows have no electricity bill, '
                         f'although the building has bills for that utility in other states: the tract-to-utility '
                         f'map disagrees with the utility_bills measure\'s. First offending keys:\n{missing.head(5)}')


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
    logger.warning(f'{bills_root} {reason}; {STALE_REASONS.get(version, "it was built by an older bills join")}. '
                   f'Moving it to {stale_path} and rebuilding the bills (current version {BILLS_JOIN_VERSION}).')
    fs.mv(bills_root, stale_path, recursive=True)
    return stale_path
