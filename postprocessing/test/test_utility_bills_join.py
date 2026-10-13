# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import json
import os

import fsspec
import polars as pl
import pytest
from polars.testing import assert_frame_equal

from comstockpostproc import utility_bills_join as ubj
from comstockpostproc.comstock import ComStock
from comstockpostproc.naming_mixin import NamingMixin as N

VALS = N.UTIL_ELEC_BILL_VALS


def block(key, mean):
    """One '<key>:<values>' block in the measure's field order, every ..usd field = mean."""
    vals = []
    for c in VALS:
        if c == N.UTIL_ELEC_BILL_NUM_BILLS:
            vals.append('3')
        elif 'label' in c:
            vals.append(f'rate_{key}')
        else:
            vals.append(str(mean))
    return f'{key}:' + ':'.join(vals)


def bills_string(*blocks):
    return '|' + '|'.join(blocks) + '|'


def state_string(**by_state):
    return '|' + '|'.join(f'{st}:{v}' for st, v in by_state.items()) + '|'


# Building 1 is in a region spanning ID and WA; utility 100 serves tracts in both states,
# so the measure writes it twice (with each state's escalation). Building 2 is single-state.
SIM_OUTS = pl.DataFrame({
    N.BLDG_ID: [1, 2],
    N.FLR_AREA: [1000.0, 2000.0],
    N.UTIL_BILL_ELEC_RESULTS: [
        bills_string(block('100', 1000), block('200', 1500), block('100', 1100)),
        bills_string(block('300', 2000)),
    ],
    N.UTIL_BILL_STATE_ELEC_RESULTS: [state_string(ID=900, WA=950), state_string(WY=1900)],
    N.UTIL_BILL_STATE_GAS_RESULTS: [state_string(ID=10, WA=11), state_string(WY=20)],
    N.UTIL_BILL_STATE_PROPANE_RESULTS: [state_string(ID=0, WA=0), state_string(WY=0)],
    N.UTIL_BILL_STATE_FUEL_OIL_RESULTS: [state_string(ID=0, WA=0), state_string(WY=0)],
}).with_columns(pl.col(N.UTIL_BILL_ELEC_RESULTS).cast(pl.Categorical))

# 10 allocated rows; tracts T1/T3 (ID) and T2 (WA) are served by utility 100
TRACT_TO_UTIL = pl.DataFrame({
    N.TRACT_ID: ['T1', 'T2', 'T3', 'T4', 'T5'],
    N.UTIL_BILL_EIA_ID: [100, 100, 100, 200, 300],
})
DRAW = pl.DataFrame({
    N.BLDG_ID: [1, 1, 1, 1, 1, 1, 2, 2, 2, 2],
    N.TRACT_ID: ['T1', 'T2', 'T3', 'T1', 'T4', 'T4', 'T5', 'T5', 'T5', 'T5'],
    N.STATE_ABBRV: ['ID', 'WA', 'ID', 'ID', 'ID', 'WA', 'WY', 'WY', 'WY', 'WY'],
    N.BLDG_WEIGHT: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
})


def parse(sim_outs=SIM_OUTS):
    return ubj.electricity_bills_by_utility(
        sim_outs.lazy(), N.BLDG_ID, N.UTIL_BILL_ELEC_RESULTS, N.UTIL_BILL_EIA_ID, VALS).collect()


def test_repeated_eia_id_collapses_to_first_block():
    bills = parse()
    assert bills.select(N.BLDG_ID, N.UTIL_BILL_EIA_ID).rows() == [(1, 100), (1, 200), (2, 300)]
    assert bills.filter(pl.col(N.UTIL_BILL_EIA_ID) == 100)[N.UTIL_BILL_ELEC].item() == 1000
    assert bills[ubj.BILL_STATE].null_count() == bills.height
    assert bills.schema[N.UTIL_BILL_ELEC] == pl.Int64
    assert bills.schema[N.UTIL_BILL_EIA_ID] == pl.Int64


def old_join(sim_outs, draw):
    """The bills-by-utility join as it was on main 3c103063 (comstock.py:2450-2500)."""
    res, eia = N.UTIL_BILL_ELEC_RESULTS, N.UTIL_BILL_EIA_ID
    bills = sim_outs.select([N.BLDG_ID, res, N.FLR_AREA]).with_columns(pl.col(res).cast(pl.String))
    bills = bills.with_columns(pl.col(res).str.strip_chars_start('|').str.strip_chars_end('|').str.split('|')).explode(res)
    bills = bills.with_columns(pl.col(res).str.split(':').alias('tsc'))
    new_cols = [eia] + VALS
    bills = bills.with_columns(pl.col('tsc').list.to_struct('max_width', new_cols)).unnest('tsc')
    bills = bills.with_columns([pl.when(pl.col(c) == '').then(None).otherwise(pl.col(c)).alias(c) for c in new_cols])
    bills = bills.with_columns([pl.col(c).cast(pl.Int64) for c in [c for c in VALS if '..usd' in c] + [eia]])
    return draw.join(bills, on=[N.BLDG_ID, eia], how='left')


def test_matches_old_join_without_the_duplicate_copies():
    draw = DRAW.with_row_index('row').join(TRACT_TO_UTIL, on=N.TRACT_ID, how='left')
    old = old_join(SIM_OUTS, draw)
    bills = ubj.electricity_bills_by_utility(SIM_OUTS.lazy(), N.BLDG_ID, N.UTIL_BILL_ELEC_RESULTS,
                                             N.UTIL_BILL_EIA_ID, VALS, keep_cols=[N.FLR_AREA])
    bills, keys = ubj.bills_join_keys(bills, N.BLDG_ID, N.UTIL_BILL_EIA_ID, N.STATE_ABBRV)
    new = draw.join(bills.collect(), on=keys, how='left')

    # Same columns, in the same order, with the same dtypes
    assert new.schema == old.schema
    # The old join copied building 1's four utility-100 rows (utility 100 is in its string twice)
    assert old.height == DRAW.height + 4
    assert new.height == DRAW.height
    # Every new row is the old row built from the utility's first block (mean 1000, not 1100)
    old_first = old.filter(pl.col(N.UTIL_BILL_ELEC) != 1100)
    assert_frame_equal(new.sort('row'), old_first.sort('row'))


def test_empty_results_string_is_dropped():
    sim_outs = SIM_OUTS.with_columns(pl.col(N.UTIL_BILL_ELEC_RESULTS).cast(pl.String))
    sim_outs = pl.concat([sim_outs, sim_outs.head(1).with_columns(
        pl.lit(3).cast(sim_outs.schema[N.BLDG_ID]).alias(N.BLDG_ID),
        pl.lit('').alias(N.UTIL_BILL_ELEC_RESULTS))])
    assert 3 not in parse(sim_outs)[N.BLDG_ID].to_list()


def test_state_keyed_blocks_parse_and_join_on_state():
    sim_outs = SIM_OUTS.with_columns(pl.Series(N.UTIL_BILL_ELEC_RESULTS, [
        bills_string(block('100@ID', 1000), block('200@ID', 1500), block('100@WA', 1100), block('200@WA', 1600)),
        bills_string(block('300@WY', 2000)),
    ]))
    bills = parse(sim_outs)
    assert bills.height == 5
    assert sorted(bills.filter(pl.col(N.UTIL_BILL_EIA_ID) == 100)[ubj.BILL_STATE].to_list()) == ['ID', 'WA']

    bills, keys = ubj.bills_join_keys(bills.lazy(), N.BLDG_ID, N.UTIL_BILL_EIA_ID, N.STATE_ABBRV)
    assert keys == [N.BLDG_ID, N.UTIL_BILL_EIA_ID, N.STATE_ABBRV]
    joined = DRAW.join(TRACT_TO_UTIL, on=N.TRACT_ID).join(bills.collect(), on=keys, how='left')
    assert joined.height == DRAW.height
    # Row 2 (WA, utility 100) gets WA's bill, rows 1/3/4 (ID) get ID's
    assert joined[N.UTIL_BILL_ELEC].to_list()[:6] == [1000, 1100, 1000, 1000, 1500, 1600]


def test_mixed_key_formats_raise():
    sim_outs = SIM_OUTS.with_columns(pl.Series(N.UTIL_BILL_ELEC_RESULTS, [
        bills_string(block('100@ID', 1000)), bills_string(block('300', 2000))]))
    with pytest.raises(ValueError, match='mix state-keyed'):
        ubj.bills_join_keys(parse(sim_outs).lazy(), N.BLDG_ID, N.UTIL_BILL_EIA_ID, N.STATE_ABBRV)


def test_assert_unique_on_names_offending_key():
    lf = pl.LazyFrame({'a': [1, 1, 2], 'b': [5, 5, 6]})
    with pytest.raises(ValueError, match='1 duplicated join keys'):
        ubj.assert_unique_on(lf, ['a', 'b'], 'frame')
    ubj.assert_unique_on(pl.LazyFrame({'a': [1, 2]}), ['a'], 'frame')


def test_assert_row_count_preserved():
    ubj.assert_row_count_preserved(10, 10, 'join')
    with pytest.raises(ValueError, match='from 10 to 12'):
        ubj.assert_row_count_preserved(10, 12, 'join')


def test_stale_cache_is_renamed_and_marker_written(tmp_path):
    fs = fsspec.filesystem('file')
    root = (tmp_path / 'cached_allocated_weights_plus_bills').as_posix()
    os.makedirs(f'{root}/upgrade=0')
    stale = ubj.retire_stale_bills_cache(root, fs)
    assert stale is not None and '.stale_bills_join_v1_' in stale
    assert not os.path.exists(root) and os.path.exists(f'{stale}/upgrade=0')

    os.makedirs(f'{root}/upgrade=0')
    ubj.write_bills_marker(root, fs)
    assert ubj.read_bills_marker(root, fs)['bills_join_version'] == ubj.BILLS_JOIN_VERSION
    assert ubj.retire_stale_bills_cache(root, fs) is None
    assert os.path.exists(f'{root}/upgrade=0')


def make_comstock(tmp_path):
    """A ComStock with only what create_allocated_weights_plus_util_bills_for_upgrade reads."""
    cs = ComStock.__new__(ComStock)
    out_dir = tmp_path / 'output'
    truth_dir = tmp_path / 'truth'
    out_dir.mkdir()
    truth_dir.mkdir()
    TRACT_TO_UTIL.write_csv(truth_dir / 'tract_to_util.csv')
    cs.output_dir = {'fs': fsspec.filesystem('file'), 'fs_path': out_dir.as_posix(), 'storage_options': None}
    cs.truth_data_dir = truth_dir.as_posix()
    cs.tract_to_util_map_file_name = 'tract_to_util.csv'
    cs.weighted_utility_units = 'billion_usd'
    cs.unweighted_weighted_map = {}
    cs.data = SIM_OUTS.with_columns(pl.lit(0).alias(N.UPGRADE_ID)).lazy()
    cs.get_sim_outs_for_upgrade = lambda upgrade_id: cs.data
    cs.get_allocated_weights_scaled_to_cbecs_for_upgrade = lambda upgrade_id: DRAW.lazy().with_columns(
        pl.lit(upgrade_id).cast(pl.Int64).alias(N.UPGRADE_ID))
    return cs, out_dir.as_posix() + '/cached_allocated_weights_plus_bills'


def test_bills_stage_preserves_rows_and_weights(tmp_path):
    cs, root = make_comstock(tmp_path)
    # An inflated cache from the old join is moved aside, not reused
    os.makedirs(f'{root}/upgrade=0/in.state=ID')
    pl.DataFrame({'x': [1]}).write_parquet(f'{root}/upgrade=0/in.state=ID/cached_allocated_weights_plus_bills_upgrade0_ID.parquet')

    bills_dir = cs.create_allocated_weights_plus_util_bills_for_upgrade(0)
    out = pl.scan_parquet(f'{bills_dir}/**/*.parquet', hive_partitioning=True).collect()

    assert out.height == DRAW.height
    assert out[N.BLDG_WEIGHT].sum() == DRAW[N.BLDG_WEIGHT].sum()
    by_tract = out.filter(pl.col(N.BLDG_ID) == 1).sort(N.BLDG_WEIGHT)
    assert by_tract[N.UTIL_BILL_ELEC].to_list() == [1000, 1000, 1000, 1000, 1500, 1500]
    assert json.load(open(f'{root}/{ubj.BILLS_MARKER_FILE_NAME}'))['bills_join_version'] == ubj.BILLS_JOIN_VERSION
    assert any('.stale_bills_join_v1_' in p for p in os.listdir(tmp_path / 'output'))


def test_reading_a_stale_cache_raises(tmp_path):
    cs, root = make_comstock(tmp_path)
    os.makedirs(f'{root}/upgrade=0')
    with pytest.raises(Exception, match='older utility bills join'):
        cs.get_allocated_weights_plus_util_bills_for_upgrade(0)


def test_bills_stage_fails_on_fan_out(tmp_path):
    cs, _ = make_comstock(tmp_path)
    # A tract mapped to two utilities would duplicate rows: refuse it
    pl.concat([TRACT_TO_UTIL, TRACT_TO_UTIL.head(1)]).write_csv(f'{cs.truth_data_dir}/tract_to_util.csv')
    with pytest.raises(ValueError, match='duplicated join keys'):
        cs.create_allocated_weights_plus_util_bills_for_upgrade(0)
