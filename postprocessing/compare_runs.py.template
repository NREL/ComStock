#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging

import comstockpostproc as cspp


logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def main():
    # First ComStock run
    comstock_a = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='sampling_lighting_11079_1',  # Name of the run on S3
        comstock_run_version='sampling_lighting_11079_1',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name=None,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.25,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_csv=False, # True if CSV already made and want faster reload times
        include_upgrades=False  # False if not looking at upgrades
        )

    # Second ComStock run
    comstock_b = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='cycle_4_sampling_test_rand_985932_20240321',  # Name of the run on S3
        comstock_run_version='new_sampling_test',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name='rand_985932_20240321',  # Typically same as comstock_run_name or None
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='rand_985932_sampling_buildstock.csv', # Download buildstock.csv manually
        acceptable_failure_percentage=0.9,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#56B4E9',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_csv=False,  # True if CSV already made and want faster reload times
        include_upgrades=False  # False if not looking at upgrades
        )

    # Stock Estimation for Apportionment:
    stock_estimate = cspp.Apportion(
        stock_estimation_version='2024R2',  # Only updated when a new stock estimate is published
        truth_data_version='v01'  # Typically don't change this
    )

    # CBECS
    cbecs = cspp.CBECS(
        cbecs_year=2018,  # 2012 and 2018 currently available
        truth_data_version='v01',  # Typically don't change this
        color_hex='#009E73',  # Color used to represent CBECS in plots
        reload_from_csv=False  # True if CSV already made and want faster reload times
        )

    # First scale ComStock runs to the 'truth data' from StockE V3 estimates using bucket-based apportionment
    # Then scale both ComStock runs to CBECS 2018 AND remove non-ComStock buildings from CBECS
    # This is how weights in the models are set to represent national energy consumption
    comstock_a.add_weights_aportioned_by_stock_estimate(apportionment=stock_estimate)
    comstock_a.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)
    comstock_b.add_weights_aportioned_by_stock_estimate(apportionment=stock_estimate)
    comstock_b.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # Export CBECS and ComStock data to wide and long formats for Tableau and to skip processing later
    cbecs.export_to_csv_wide()  # May comment this out if CSV output isn't needed
    # comstock_a.create_national_aggregation()  # May comment this out if CSV output isn't needed
    # comstock_b.create_national_aggregation()  # May comment this out if CSV output isn't needed
    # TODO This (long CSV export) is not yet re-implemented
    # comstock_a.export_to_csv_long()  # Long format useful for stacking end uses and fuels
    # comstock_b.export_to_csv_long()  # Long format useful for stacking end uses and fuels

    # Compare multiple ComStock runs to one another and to CBECS
    comparison = cspp.ComStockToCBECSComparison(
        cbecs_list=[cbecs],
        comstock_list = [comstock_a, comstock_b],
        make_comparison_plots=True
    )

    # Export the comparison data to wide format for Tableau
    comparison.export_to_csv_wide()

# Code to execute the script
if __name__=="__main__":
    main()
