#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import polars as pl
import comstockpostproc as cspp

logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='cycle_4_sampling_test_rand_985932_20240321',  # Name of the run on S3
        comstock_run_version='full_1M_sample',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name='rand_985932_20240321',  # Typically same as comstock_run_name or None
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='rand_985932_sampling_buildstock.csv', # Download buildstock.csv manually
        acceptable_failure_percentage=0.9,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for exportb
        reload_from_csv=False,  # True if CSV already made and want faster reload times
        include_upgrades=False,  # False if not looking at upgrades
        upgrade_ids_to_skip=[1]  # Use [1, 3] etc. to exclude certain upgrades
    )

    comstock2 = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='sampling_149325_1',  # Name of the run on S3
        comstock_run_version='euss_as_run_segmentation',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name='sampling_149325_1',  # Typically same as comstock_run_name or None
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock_20241103-1011_v98_2018_hhorsey_149325_hardsize.csv', # Download buildstock.csv manually
        acceptable_failure_percentage=0.9,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for exportb
        reload_from_csv=False,  # True if CSV already made and want faster reload times
        include_upgrades=False,  # False if not looking at upgrades
        upgrade_ids_to_skip=[]  # Use [1, 3] etc. to exclude certain upgrades
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
    # TODO This needs to be rewritten with safe column names, lazyframe usage, etc. 
    #comstock.calculate_weighted_columnal_values()

    # Scale ComStock runs to the 'truth data' from StockE V3 estimates using bucket-based apportionment
    comstock2.add_weights_aportioned_by_stock_estimate(apportionment=stock_estimate)
    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    comstock2.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)
    # TODO This needs to be rewritten with safe column names, lazyframe usage, etc. 
    #comstock.calculate_weighted_columnal_values()
    
    ## HERNAN'S WORK STARTS HERE
    # I tested the following with both comstock and comstock2 - both worked np!
    # Edit the numeric_columns_to_weight, numeric_columns_to_not_weight, and non_numeric_columns variables as needed:
    blocks3 = comstock.fkt.clone()
    blocks3 = blocks3.select([pl.col(comstock.BLDG_WEIGHT), pl.col(comstock.BLDG_ID)])
    blocks3 = blocks3.join(comstock.data, on=[pl.col(comstock.BLDG_ID)])
    numeric_columns_to_weight = {
        'in.sqft..ft2': 'total_allocated_sqft'
    }
    numeric_columns_to_not_weight = [
        'out.site_energy.total.energy_consumption_intensity..kwh_per_ft2',
        'out.electricity.total.energy_consumption_intensity..kwh_per_ft2'
    ]
    non_numeric_columns = [
        'in.comstock_building_type', 'in.hvac_system_type', 'in.size_bin_id', 'in.sampling_region_id', 
        'in.heating_fuel'
    ]
    for col_to_weight in numeric_columns_to_weight.keys():
        blocks3 = blocks3.with_columns(
            (pl.col(col_to_weight) * pl.col(comstock.BLDG_WEIGHT)).alias(numeric_columns_to_weight[col_to_weight])
        )
    cols_to_select = numeric_columns_to_not_weight + non_numeric_columns + list(numeric_columns_to_weight.values())
    blocks3 = blocks3.select(cols_to_select).collect()

    # comstock.create_national_aggregation()
    # comstock.create_geospatially_resolved_aggregations(comstock.STATE_ID, pretty_geo_col_name='state_id')
    # comstock.create_geospatially_resolved_aggregations(comstock.COUNTY_ID, pretty_geo_col_name='county_id')

    # Make a comparison by passing in a list of CBECs and ComStock runs to compare
    # upgrade_id can be 'All' or the upgrade number
    # comstock.create_plotting_lazyframe()
    # comp = cspp.ComStockToCBECSComparison(cbecs_list=[cbecs], comstock_list=[comstock], upgrade_id='All',make_comparison_plots=True)

    # comp.export_to_csv_wide()

    
# Code to execute the script
if __name__ == "__main__":
    main()