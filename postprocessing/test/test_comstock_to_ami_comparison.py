#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest

import comstockpostproc.comstock
import comstockpostproc.eia
import comstockpostproc.comstock_to_eia_comparison
import comstockpostproc.cbecs


def test_ami_plot_generation():
    # ComStock
    comstock = comstockpostproc.comstock.ComStock(
        s3_base_dir='eulp/euss_com',
        comstock_run_name='baseline_data_10k',
        comstock_run_version='baseline_data_10k',
        comstock_year=2018,
        truth_data_version='v01',
        buildstock_csv_name='buildstock.csv',
        acceptable_failure_percentage=0.9,
        drop_failed_runs=True,
        color_hex='#0072B2',
        skip_missing_columns=True,
        athena_table_name='baseline_data_10k',
        reload_from_csv=False,
        include_upgrades=False
        )

    # CBECS
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year = 2018,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=True, # True since CSV already made and want faster reload times
        )

    # AMI
    ami = comstockpostproc.ami.AMI(
        truth_data_version="v01",
        reload_from_csv=True, # True since CSV already made and want faster reload times
    )

    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    # This is how weights in the models are set to represent national energy consumption
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # Export CBECS and ComStock data to wide and long formats for Tableau and to skip processing later
    cbecs.export_to_csv_wide()  # May comment this out after run once
    comstock.export_to_csv_wide()  # May comment this out after run once