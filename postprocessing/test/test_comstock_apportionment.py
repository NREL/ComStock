# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
"""Unit tests for comstockpostproc.probability_merge.merge_probability_table (added 2026-09, stock-estimation
plan WS1), the validated join used by Apportion.upsample_hvac_system_fuel_types.

Synthetic frames only; no S3, no truth data. The behaviours pinned here are the ones the previous inner merge
got wrong: a duplicated TSV key must be an error rather than a silent double count, an unmatched key must be
reported and either filled from a documented fallback or raised, and the row count must never change.
The module is loaded by path so the test runs without the AWS dependencies the package __init__ pulls in.
"""
import importlib.util
import logging
import os

import numpy as np
import pandas as pd
import pytest

_PATH = os.path.join(os.path.dirname(__file__), '..', 'comstockpostproc', 'probability_merge.py')
_spec = importlib.util.spec_from_file_location('probability_merge', _PATH)
probability_merge = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probability_merge)


class Apportion:  # thin alias so the tests read like the call site
    merge_probability_table = staticmethod(probability_merge.merge_probability_table)


OPTS = ['PSZ', 'VAV', 'PTAC']


def _truth():
    return pd.DataFrame({
        'building_type': ['retail', 'retail', 'retail', 'hospital', 'hospital'],
        'size_bin': [0, 0, 1, 1, 1],
        'heating_fuel': ['Propane', 'NaturalGas', 'NaturalGas', 'Electricity', 'DistrictHeating'],
        'cen_div': ['West North Central'] * 5,
        'sqft': [10.0, 20.0, 30.0, 400.0, 500.0],
    })


def _prob(rows):
    return pd.DataFrame(rows, columns=['building_type', 'size_bin', 'heating_fuel', 'census_region'] + OPTS)


KEYS_L = ['building_type', 'size_bin', 'heating_fuel', 'cen_div']
KEYS_R = ['building_type', 'size_bin', 'heating_fuel', 'census_region']


def test_duplicated_key_is_an_error():
    prob = _prob([
        ['retail', 0, 'Propane', 'West North Central', 1.0, 0.0, 0.0],
        ['retail', 0, 'Propane', 'West North Central', 0.0, 0.0, 1.0],   # the WS1 defect: a second Propane row
        ['retail', 0, 'NaturalGas', 'West North Central', 0.5, 0.5, 0.0],
    ])
    with pytest.raises(ValueError, match='duplicated dependency keys'):
        Apportion.merge_probability_table(_truth(), prob, KEYS_L, KEYS_R, OPTS, 'test')


def test_matched_rows_keep_count_and_values():
    prob = _prob([
        ['retail', 0, 'Propane', 'West North Central', 1.0, 0.0, 0.0],
        ['retail', 0, 'NaturalGas', 'West North Central', 0.5, 0.5, 0.0],
        ['retail', 1, 'NaturalGas', 'West North Central', 0.2, 0.8, 0.0],
        ['hospital', 1, 'Electricity', 'West North Central', 0.0, 1.0, 0.0],
        ['hospital', 1, 'DistrictHeating', 'West North Central', 0.0, 0.9, 0.1],
    ])
    merged, diag = Apportion.merge_probability_table(_truth(), prob, KEYS_L, KEYS_R, OPTS, 'test', area_col='sqft')
    assert len(merged) == 5
    assert diag['unmatched_rows'] == 0 and diag['fallback'] == []
    assert merged.loc[merged.heating_fuel == 'DistrictHeating', 'PTAC'].item() == pytest.approx(0.1)


def test_unmatched_key_falls_back_to_documented_mean(caplog):
    caplog.set_level(logging.WARNING)
    prob = _prob([
        ['retail', 0, 'Propane', 'West North Central', 1.0, 0.0, 0.0],
        ['retail', 0, 'NaturalGas', 'West North Central', 0.5, 0.5, 0.0],
        ['retail', 1, 'NaturalGas', 'West North Central', 0.2, 0.8, 0.0],
        ['hospital', 1, 'Electricity', 'West North Central', 0.0, 1.0, 0.0],
        # no DistrictHeating row in West North Central; two other divisions have one
        ['hospital', 1, 'DistrictHeating', 'New England', 0.0, 0.8, 0.2],
        ['hospital', 1, 'DistrictHeating', 'Pacific', 0.0, 0.6, 0.4],
    ])
    merged, diag = Apportion.merge_probability_table(
        _truth(), prob, KEYS_L, KEYS_R, OPTS, 'test',
        fallback_on=[['building_type', 'size_bin', 'heating_fuel'], ['building_type', 'heating_fuel']], area_col='sqft')
    assert len(merged) == 5, 'a left join never drops a building'
    assert diag['unmatched_rows'] == 1
    assert diag['unmatched_area_share'] == pytest.approx(500.0 / 960.0)
    assert diag['fallback'][0]['keys'] == ['building_type', 'size_bin', 'heating_fuel'] and diag['fallback'][0]['rows'] == 1
    row = merged.loc[merged.heating_fuel == 'DistrictHeating', OPTS].iloc[0]
    assert row.to_numpy() == pytest.approx([0.0, 0.7, 0.3])
    assert 'no probability row' in caplog.text and 'filled from the mean' in caplog.text


def test_unmatched_key_without_fallback_is_an_error():
    prob = _prob([
        ['retail', 0, 'Propane', 'West North Central', 1.0, 0.0, 0.0],
        ['retail', 0, 'NaturalGas', 'West North Central', 0.5, 0.5, 0.0],
        ['retail', 1, 'NaturalGas', 'West North Central', 0.2, 0.8, 0.0],
        ['hospital', 1, 'Electricity', 'West North Central', 0.0, 1.0, 0.0],
    ])
    with pytest.raises(ValueError, match='no fallback matched'):
        Apportion.merge_probability_table(_truth(), prob, KEYS_L, KEYS_R, OPTS, 'test', fallback_on=None)


def test_left_join_preserves_bootstrap_duplicates():
    """Bootstrapped truth rows (index repeated) must all survive and stay in order."""
    truth = _truth().loc[[0, 0, 0, 1, 1, 1]].reset_index(drop=True)
    prob = _prob([
        ['retail', 0, 'Propane', 'West North Central', 1.0, 0.0, 0.0],
        ['retail', 0, 'NaturalGas', 'West North Central', 0.5, 0.5, 0.0],
    ])
    merged, _ = Apportion.merge_probability_table(truth, prob, KEYS_L, KEYS_R, OPTS, 'test')
    assert len(merged) == 6
    assert (merged.heating_fuel.to_numpy() == truth.heating_fuel.to_numpy()).all()
    assert np.allclose(merged.loc[merged.heating_fuel == 'Propane', 'PSZ'], 1.0)


def test_fallback_backfills_the_right_key_column():
    """A fallback-filled row must not be left with a NaN ``census_region``.

    The right key that has its own name survives the merge as a redundant copy of the left key and is NaN
    wherever the join missed. Filling only the option columns left that NaN behind, and
    ``upsample_hvac_system_fuel_types`` asserts no column is NaN, so the first fallback raised there instead.
    """
    df = pd.DataFrame({'building_type': ['office', 'office'],
                       'size_bin': [1, 2],
                       'heating_fuel': ['NaturalGas', 'NaturalGas'],
                       'cen_div': ['Pacific', 'Mountain']})
    prob = pd.DataFrame({'building_type': ['office'], 'size_bin': [1], 'heating_fuel': ['NaturalGas'],
                         'census_region': ['Pacific'], 'PSZ': [1.0]})
    merged, diag = Apportion.merge_probability_table(
        df, prob, left_on=['building_type', 'size_bin', 'heating_fuel', 'cen_div'],
        right_on=['building_type', 'size_bin', 'heating_fuel', 'census_region'],
        option_cols=['PSZ'], label='hvac', fallback_on=[['building_type', 'heating_fuel']])

    assert diag['fallback'][0]['rows'] == 1
    assert merged['PSZ'].notna().all()
    assert merged['census_region'].notna().all(), 'fallback row left census_region NaN'
    assert merged.loc[1, 'census_region'] == 'Mountain', 'the mirrored key must follow the building'


def test_fuel_only_fallback_covers_a_building_type_with_no_row_for_that_fuel():
    """The district-heating case: heating_fuel.tsv has no size_bin dependency, so it can assign DistrictHeating
    to any size bin of a building type, while hvac_system_type.tsv only carries a district row where CBECS has
    enough district-heated records to justify the sampling bucket.

    Both of the first two fallback levels are keyed on building_type, so neither can match a type with no
    district row in any bin -- and some cells have zero district-heated CBECS records, so no TSV row could ever
    cover them. The fuel-only level keeps those buildings district-heated with the national district system mix.
    """
    prob = pd.DataFrame({
        'building_type': ['large_office', 'large_office', 'retail'],
        'size_bin': [0, 1, 0],
        'heating_fuel': ['DistrictHeating', 'DistrictHeating', 'NaturalGas'],
        'census_region': ['Pacific', 'Pacific', 'Pacific'],
        'VAV district': [1.0, 0.5, 0.0],
        'PSZ gas': [0.0, 0.5, 1.0],
    })
    # a district-heated retail building: retail has no DistrictHeating row in any bin
    df = pd.DataFrame({'building_type': ['retail'], 'size_bin': [0], 'heating_fuel': ['DistrictHeating'],
                       'cen_div': ['Mountain'], 'sqft': [1000.0]})
    keys = dict(left_on=['building_type', 'size_bin', 'heating_fuel', 'cen_div'],
                right_on=['building_type', 'size_bin', 'heating_fuel', 'census_region'],
                option_cols=['VAV district', 'PSZ gas'], label='hvac', area_col='sqft')

    with pytest.raises(ValueError, match='no fallback matched'):
        Apportion.merge_probability_table(df, prob, fallback_on=[["building_type", "size_bin", "heating_fuel"],
                                                       ['building_type', 'heating_fuel']], **keys)

    merged, diag = Apportion.merge_probability_table(
        df, prob, fallback_on=[['building_type', 'size_bin', 'heating_fuel'],
                               ['building_type', 'heating_fuel'], ['heating_fuel']], **keys)

    assert diag['fallback'][-1] == {'keys': ['heating_fuel'], 'rows': 1, 'area_share': 1.0}
    # it took the mean of the two district rows, renormalised - never the gas row
    assert merged.loc[0, 'VAV district'] == pytest.approx(0.75)
    assert merged.loc[0, 'PSZ gas'] == pytest.approx(0.25)
    assert merged['census_region'].notna().all()
