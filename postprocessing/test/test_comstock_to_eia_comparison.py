#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest

import comstockpostproc.comstock
import comstockpostproc.eia
import comstockpostproc.comstock_to_eia_comparison
import comstockpostproc.cbecs


def test_plot_generation():
    # ComStock
    comstock = comstockpostproc.comstock.ComStock(
        s3_base_dir='eulp/euss_com',
        comstock_run_name='cycle2_euss_full_350k_long_2of2_1555',
        comstock_run_version='cycle2_euss_full_350k_long_2of2_1555',
        comstock_year=2018,
        truth_data_version='v01',
        buildstock_csv_name='buildstock.csv',
        acceptable_failure_percentage=0.9,
        drop_failed_runs=True,
        color_hex='#0072B2',
        skip_missing_columns=True,
        athena_table_name='cycle2_euss_full_350k_long_2of2_1555',
        reload_from_csv=False,
        include_upgrades=False
        )

    # CBECS
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year = 2018,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=False, # True since CSV already made and want faster reload times
        )

    # EIA
    eia = comstockpostproc.eia.EIA(
        year=2018,
        truth_data_version="v01",
        reload_from_csv=False
    )

    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)
    comstock.export_to_csv_wide()

    # Make a comparison by passing in a list of EIA and ComStock runs to compare
    eia_list = [eia]
    comstock_list = [comstock]
    comp = comstockpostproc.comstock_to_eia_comparison.ComStockToEIAComparison(eia_list, comstock_list)
    comp.monthly_data

    # # Generate comparison plots
    # comp.plot_monthly_energy_consumption_for_eia()