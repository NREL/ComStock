# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest
import glob

import comstockpostproc.comstock
import comstockpostproc.cbecs
import comstockpostproc.comstock_to_cbecs_comparison


def test_cbecs_plot_generation():
    comstock = comstockpostproc.comstock.ComStock(
        s3_base_dir='comstock-core/test',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='com_os340_stds_030_10k_test_1',  # Name of the run on S3
        comstock_run_version='com_os340_stds_030_10k_test_1',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.10,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        athena_table_name='com_os340_stds_030_10k_test_1',
        reload_from_csv=False, # True if CSV already made and want faster reload times
        include_upgrades=False,  # False if not looking at upgrades
        upgrade_ids_to_skip=[]  # Use ['01', '03'] etc. to exclude certain upgrades
        )

    # Scale ComStock to CBECS 2012 AND remove non-ComStock buildings from CBECS
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year=2012,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=False
        )

    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # Compare one or more ComStock runs to one another and to CBECS
    comparison = comstockpostproc.ComStockToCBECSComparison(
        cbecs_list=[cbecs],
        comstock_list=[comstock],
        make_comparison_plots=True
        )

    # Export the comparison data to wide format for Tableau
    comparison.export_to_csv_wide()

    # Check that a smattering of plots do exist
    n_plots = len(glob.glob(f'{comparison.output_dir}/**/*.jpg'))
    assert n_plots > 250, 'Expected at least 250 plots for a comparison'
