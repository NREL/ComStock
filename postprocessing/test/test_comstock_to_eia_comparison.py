#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest

import comstockpostproc.comstock
import comstockpostproc.eia
import comstockpostproc.comstock_to_eia_comparison
import comstockpostproc.cbecs


def test_plot_generation():
    # First ComStock
    comstock_bef = comstockpostproc.comstock.ComStock(
        s3_base_dir='eulp/euss_com',
        comstock_run_name='ext_wall_ins_hardsize_test_10k_v4',
        comstock_run_version='autosz_10k',
        comstock_year=2018,
        truth_data_version='v01',
        buildstock_csv_name='buildstock.csv',
        acceptable_failure_percentage=0.05,
        drop_failed_runs=True,
        color_hex='#5495ba',
        skip_missing_columns=True,
        athena_table_name=None,
        reload_from_csv=False, # True since CSV already made and want faster reload times
        include_upgrades=False)

    # need to scale comstock up to CBECS and then compare to EIA
    # CBECS
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year = 2012,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=True, # True since CSV already made and want faster reload times
        )

    # EIA
    eia = comstockpostproc.eia.EIA(
        year=2013,
        truth_data_version="v01",
        reload_from_csv=False
    )

    # Scale ComStock run to CBECS 2012 AND remove non-ComStock buildings from CBECS
    comstock_bef.add_national_scaling_weights(
        cbecs, remove_non_comstock_bldg_types_from_cbecs=True)
    comstock_bef.export_to_csv_wide()

    # Make a comparison by passing in a list of EIA and ComStock runs to compare
    eia_list = [eia]
    comstock_list = [comstock_bef]
    comp = comstockpostproc.comstock_to_eia_comparison.ComStockToEIAComparison(
        eia_list, comstock_list)
    comp.monthly_data

    # # Generate comparison plots
    # comp.plot_monthly_energy_consumption_for_eia()