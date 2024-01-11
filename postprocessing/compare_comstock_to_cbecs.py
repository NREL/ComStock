#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import os

import comstockpostproc as cspp

logging.basicConfig(level='DEBUG')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='baseline_vav_mdp_adjust2',  # Name of the run on S3
        comstock_run_version='baseline_vav_mdp_adjust2',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name='baseline_vav_mdp_adjust2',  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv', # Download buildstock.csv manually
        acceptable_failure_percentage=0.9,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for exportb
        reload_from_csv=True,  # True if CSV already made and want faster reload times
        include_upgrades=False,  # False if not looking at upgrades
        upgrade_ids_to_skip=[]  # Use [1, 3] etc. to exclude certain upgrades
    )
    
    # CBECS
    cbecs = cspp.CBECS(
        cbecs_year=2018,  # 2012 and 2018 currently available
        truth_data_version='v01',  # Typically don't change this
        color_hex='#009E73',  # Color used to represent CBECS in plots
        reload_from_csv=True  # True if CSV already made and want faster reload times
        )
    
    # EIA
    eia = cspp.EIA(
        year=2018,
        truth_data_version="v01",
        reload_from_csv=True
    )
    
    # save cbecs csv
    # cbecs.export_to_csv_wide()

    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)
    # comstock.export_to_csv_wide()

    # Make a comparison by passing in a list of CBECs and ComStock runs to compare
    comp = cspp.ComStockToCBECSComparison(cbecs_list=[cbecs], comstock_list=[comstock], upgrade_id='All',make_comparison_plots=True)
    # comp = cspp.ComStockToCBECSComparison(cbecs_list=[cbecs], comstock_list=[comstock], upgrade_id='All',make_comparison_plots=False)

    comp.export_to_csv_wide()
    
# Code to execute the script
if __name__ == "__main__":
    main()