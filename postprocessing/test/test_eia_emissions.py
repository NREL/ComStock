# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import pytest
import logging

import comstockpostproc.comstock
import comstockpostproc.eia
import comstockpostproc.comstock_to_eia_comparison

def test_eia_emissions():
    comstock = comstockpostproc.comstock.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='cycle3_euss_10k_short_1of6_1651_3',  # Name of the run on S3
        comstock_run_version='cycle3_euss_10k_short_1of6_1651_3',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name='cycle3_euss_10k_short_1of6_1651_3',  # Typically same as comstock_run_name or None
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',
        acceptable_failure_percentage=0.9,
        drop_failed_runs=True,
        color_hex='#0072B2',
        skip_missing_columns=True,
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

    eia = comstockpostproc.eia.EIA(
        year=2018,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=False,
    )

    # save cbecs csv
    cbecs.export_to_csv_wide()

    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)
    comstock.export_to_csv_wide()

    eia_list = [eia]
    comstock_list = [comstock]
    comp = comstockpostproc.comstock_to_eia_comparison.ComStockToEIAComparison(comstock_list, eia_list, make_comparison_plots=True)

    assert os.path.exists(os.path.join(comp.output_dir, 'emissions_electricity_egrid_2021_subregion.jpg'))
    assert os.path.exists(os.path.join(comp.output_dir, 'emissions_fuel_oil.jpg'))
    assert os.path.exists(os.path.join(comp.output_dir, 'emissions_natural_gas.jpg'))
    assert os.path.exists(os.path.join(comp.output_dir, 'emissions_propane.jpg'))
