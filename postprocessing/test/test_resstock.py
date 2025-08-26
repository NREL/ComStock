# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest

import comstockpostproc.resstock


def test_resstock_unit_count():
    resstock = comstockpostproc.ResStock(
        s3_base_dir='oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2021',
        resstock_run_name='resstock_amy2018_release_1',
        resstock_run_version='2021r1',
        resstock_year=2018,
        truth_data_version='v01',
        downselect_to_multifamily=False,
        reload_from_csv=False)

    resstock.export_to_csv_wide()

    # Check the total count of weights
    manual_unit_count = 133_000_000
    total_unit_count = resstock.data['weight'].sum()
    assert total_unit_count == pytest.approx(manual_unit_count, rel=0.01)

def test_resstock_multifamily_only():
    resstock = comstockpostproc.ResStock(
        s3_base_dir='oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2021',
        resstock_run_name='resstock_amy2018_release_1',
        resstock_run_version='2021r1',
        resstock_year=2018,
        truth_data_version='v01',
        downselect_to_multifamily=True,
        reload_from_csv=False)

    resstock.export_to_csv_wide()

    # Weight has been recalculated to represent the fraction of a number of buildings represented,
    # check that the number of multifamily buildings is less than the total number of dwelling units.
    manual_unit_count = 133_000_000
    total_bldg_count = resstock.data['weight'].sum()
    assert total_bldg_count < manual_unit_count
