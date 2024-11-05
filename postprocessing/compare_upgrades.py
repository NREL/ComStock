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
<<<<<<< Updated upstream
        comstock_run_name='new_sampling_154k',  # Name of the run on S3
        comstock_run_version='new_sampling_154k',  # Use whatever you want to see in plot and folder names
=======
        comstock_run_name='elec_boiler_10k',  # Name of the run on S3
        comstock_run_version='elec_boiler_10k',  # Use whatever you want to see in plot and folder names
>>>>>>> Stashed changes
        comstock_year=2018,  # Typically don't change this
        athena_table_name=None,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
<<<<<<< Updated upstream
        acceptable_failure_percentage=0.25,  # Can increase this when testing and high failure are OK
=======
        acceptable_failure_percentage=0.025,  # Can increase this when testing and high failure are OK
>>>>>>> Stashed changes
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_csv=False, # True if CSV already made and want faster reload times
        include_upgrades=True,  # False if not looking at upgrades
        upgrade_ids_to_skip=[], # Use [1, 3] etc. to exclude certain upgrades
        make_timeseries_plots=False,
        states={
                #'MN': 'Minnesota',  # specify state to use for timeseries plots in dictionary format. State ID must correspond correctly.
<<<<<<< Updated upstream
                'MA':'Massachusetts',
=======
                #'MA':'Massachusetts',
>>>>>>> Stashed changes
                #'OR': 'Oregon',
                #'LA': 'Louisiana',
                #'AZ': 'Arizona',
                #'TN': 'Tennessee'
                },
        upgrade_ids_for_comparison={} # Use {'<Name you want for comparison run folder>':[0,1,2]}; add as many upgrade IDs as needed, but plots look strange over 5
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

    # Scale ComStock runs to the 'truth data' from StockE V3 estimates using bucket-based apportionment
    comstock.add_weights_aportioned_by_stock_estimate(apportionment=stock_estimate)
    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # Export CBECS and ComStock data to wide and long formats for Tableau and to skip processing later
<<<<<<< Updated upstream
    #cbecs.export_to_csv_wide()  # May comment this out after run once
    comstock.create_national_aggregation()
    #comstock.create_geospatially_resolved_aggregations(comstock.STATE_ID, pretty_geo_col_name='state_id')
    #comstock.create_geospatially_resolved_aggregations(comstock.COUNTY_ID, pretty_geo_col_name='county_id')
=======
    # cbecs.export_to_csv_wide()  # May comment this out after run once
    # comstock.create_national_aggregation()
    # comstock.create_geospatially_resolved_aggregations(comstock.STATE_ID, pretty_geo_col_name='state_id')
    # comstock.create_geospatially_resolved_aggregations(comstock.COUNTY_ID, pretty_geo_col_name='county_id')
>>>>>>> Stashed changes
    # TODO Long is def not working as expected anymore...
    # comstock.export_to_csv_long()  # Long format useful for stacking end uses and fuels

    # Create measure run comparisons; only use if run has measures
    comparison = cspp.ComStockMeasureComparison(comstock, states=comstock.states, make_comparison_plots = comstock.make_comparison_plots, make_timeseries_plots = comstock.make_timeseries_plots)

# Code to execute the script
if __name__=="__main__":
    main()
