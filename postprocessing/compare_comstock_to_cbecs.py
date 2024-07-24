#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging

import comstockpostproc as cspp

logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='lower_sat_stpt_10k_v3',  # Name of the run on S3
        comstock_run_version='lower_sat_stpt_10k_v3',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name= None,  # Typically same as comstock_run_name or None
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv', # Download buildstock.csv manually
        acceptable_failure_percentage=0.2,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for exportb
        reload_from_csv=False,  # True if CSV already made and want faster reload times
        include_upgrades=True,  # False if not looking at upgrades
        upgrade_ids_to_skip=[]  # Use [1, 3] etc. to exclude certain upgrades
    )

    # CBECS
    cbecs = cspp.CBECS(
        cbecs_year=2012,  # 2012 and 2018 currently available
        truth_data_version='v01',  # Typically don't change this
        color_hex='#009E73',  # Color used to represent CBECS in plots
        reload_from_csv=False  # True if CSV already made and want faster reload times
        )

    # From Feburary 2024 EUSS Full Run
    national_scaling_factors = {
                'Hospital': 7.40279973438571,
                'SecondarySchool': 7.61402397003761,
                'Outpatient': 4.08817512805358,
                'LargeHotel': 9.52500448561723,
                'FullServiceRestaurant': 7.56685751697572,
                'RetailStripmall': 1.87065215852945,
                'RetailStandalone': 3.20458438519356,
                'PrimarySchool': 9.72943522508755,
                'QuickServiceRestaurant': 8.53126424238864,
                'SmallOffice': 8.72605822017302,
                'SmallHotel': 3.3063363735822,
                'MediumOffice': 9.32502232347711,
                'LargeOffice': 5.75996046109096,
                'Warehouse': 3.23792487389949
            }

    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True, use_hard_coded_scaling_weights=False, scaling_factors=national_scaling_factors)
    comstock.export_to_csv_wide()

    # Make a comparison by passing in a list of CBECs and ComStock runs to compare
    # upgrade_id can be 'All' or the upgrade number
    comp = cspp.ComStockToCBECSComparison(cbecs_list=[cbecs], comstock_list=[comstock], upgrade_id='All',make_comparison_plots=True, make_hvac_plots=True)

    comp.export_to_csv_wide()

# Code to execute the script
if __name__ == "__main__":
    main()