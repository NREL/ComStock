#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import os
import pandas as pd
import comstockpostproc as cspp

logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='oedi-data-lake',  # If run not on S3, download results_up**.parquet manually #oedi-data-lake
        comstock_run_name='comstock_amy2018_r3_2025',  # Name of the run on S3
        comstock_run_version='comstock_amy2018_r3_2025',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name=None,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.06,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_cache=True, # True if CSV already made and want faster reload times
        include_upgrades=True,  # False if not looking at upgrades
        upgrade_ids_to_skip=[
            1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,30,31,32,33,34,
            35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,60,61,62,65,
            29,
            #59,
            #63,
            #64
            ], # Use [1, 3] etc. to exclude certain upgrades
        make_timeseries_plots=True,
        # TEMPORARY: All 50 states + DC for testing
        # timeseries_locations_to_plot={
        #     'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California',
        #     #'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware', 'DC': 'District of Columbia', 'FL': 'Florida', 'GA': 'Georgia',
        #     #'HI': 'Hawaii', 'ID': 'Idaho', 'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa',
        #     #'KS': 'Kansas', 'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
        #     #'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi', 'MO': 'Missouri',
        #     #'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada', 'NH': 'New Hampshire', 'NJ': 'New Jersey',
        #     #'NM': 'New Mexico', 'NY': 'New York', 'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio',
        #     #'OK': 'Oklahoma', 'OR': 'Oregon', 'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina',
        #     #'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah', 'VT': 'Vermont',
        #     #'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia', 'WI': 'Wisconsin', 'WY': 'Wyoming'
        # },
        timeseries_locations_to_plot=
        {
            #'MN': 'Minnesota',  # specify location (either county ID or state ID) and corresponding name for plots and folders.
            #'MA':'Massachusetts',
            #'OR': 'Oregon',
            #'LA': 'Louisiana',
            #'AZ': 'Arizona',
            #'TN': 'Tennessee',
            #('MA', 'NH', 'CT', 'VT', 'RI'): 'New England', # example of multiple states together - using tuples as keys
            #'G4900350': 'Salt Lake City',
            'G2500250': 'Boston', # if specifying a county, you must export county level data to S3
            'G0400130': 'Phoenix',
            'G2700530': 'Minneapolis',  # empty string key will plot national average
            #'G4804530': 'Austin',
            #('G2500250', 'G4804530'):'Baustin'  # multiple counties together - using tuples as keys
        },

        upgrade_ids_for_comparison={'GHP Combined':[0,59,63,64]} # Use {'<Name you want for comparison run folder>':[0,1,2]}; add as many upgrade IDs as needed, but plots look strange over 5
        #output_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2025/comstock_amy2018_release_1'
        )

    # Stock Estimation for Apportionment:
    stock_estimate = cspp.Apportion(
        stock_estimation_version='2025R3',  # Only updated when a new stock estimate is published
        truth_data_version='v01',  # Typically don't change this
        reload_from_cache=True, # Set to "True" if you have already run apportionment and would like to keep consistant values between postprocessing runs.
        #output_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2025/comstock_amy2018_release_1'
    )

    # Scale ComStock runs to the 'truth data' from StockE V3 estimates using bucket-based apportionment
    base_sim_outs = comstock.get_sim_outs_for_upgrade(0)
    comstock.create_allocated_weights(stock_estimate, base_sim_outs, reload_from_cache=True)

    # CBECS
    cbecs = cspp.CBECS(
        cbecs_year=2018,  # 2012 and 2018 currently available
        truth_data_version='v01',  # Typically don't change this
        color_hex='#009E73',  # Color used to represent CBECS in plots
        reload_from_csv=True  # True if CSV already made and want faster reload times
        )

    # Scale ComStock to CBECS 2018 AND remove non-ComStock buildings from CBECS
    base_sim_outs = comstock.get_sim_outs_for_upgrade(0)
    alloc_wts = comstock.get_allocated_weights()
    comstock.create_allocated_weights_scaled_to_cbecs(cbecs, base_sim_outs, alloc_wts, remove_non_comstock_bldg_types_from_cbecs=True)

    # Add utility bills onto allocated weights
    for upgrade_id in comstock.upgrade_ids_to_process:
        # up_sim_outs = comstock.get_sim_outs_for_upgrade(upgrade_id)
        # up_alloc_wts = comstock.get_allocated_weights_scaled_to_cbecs_for_upgrade(upgrade_id)
         comstock.create_allocated_weights_plus_util_bills_for_upgrade(upgrade_id)

    ## Specify geo exports

    ## county resolution, files by state and county
    #county_resolution =  {
    #                    'geo_top_dir': 'by_state_and_county',
    #                    'partition_cols': {
    #                        comstock.STATE_ABBRV: 'state',
    #                        comstock.COUNTY_ID: 'county',
    #                    },
    #                    'aggregation_levels': [comstock.COUNTY_ID], # , comstock.COUNTY_ID],  # Full tract resolution (agg=in.nhgis_tract_gisjoin)
    #                    'data_types': ['full'],
    #                    'file_types': ['parquet'],
    #                    }

    ## state level resolution, one single national file
    #state_resolution = {
    #                    'geo_top_dir': 'national_by_state',
    #                    'partition_cols': {},
    #                    'aggregation_levels': [[comstock.STATE_ABBRV, comstock.CZ_ASHRAE]],
    #                    'data_types': ['full'], # other options: 'detailed', 'basic' **If using multiple options, order must go from more detailed to less detailed.
    #                    'file_types': ['parquet'], # other options:'parquet'
    #                    }

    ## specify the export level
    ## IMPORTANT: if making county level timeseries plots, must export county level data to S3. This does not occur automatically.
    #geo_exports = [county_resolution] #county_resolution

    #for geo_export in geo_exports:
    #    for upgrade_id in comstock.upgrade_ids_to_process:
    #        #if upgrade_id == 0:
    #        #    continue
    #        #comstock.export_metadata_and_annual_results_for_upgrade(upgrade_id, [geo_export])

    #        # Also write to S3 if making timeseries plots
    #        if comstock.make_timeseries_plots: # TODO: force geo exports to county data if couunty timeseries is requested.
    #            s3_dir = f"s3://{comstock.s3_base_dir}/{comstock.comstock_run_name}/{comstock.comstock_run_name}"
    #            s3_output_dir = comstock.setup_fsspec_filesystem(s3_dir, aws_profile_name=None)
    #            comstock.export_metadata_and_annual_results_for_upgrade(upgrade_id=upgrade_id, geo_exports=[geo_export], output_dir=s3_output_dir)

    # write select results to S3 for Athena/Glue when needed for timeseries plots
    if comstock.make_timeseries_plots:
        s3_dir = f"s3://{comstock.s3_base_dir}/{comstock.comstock_run_name}/{comstock.comstock_run_name}"
        database = "enduse"
        crawler_name = comstock.comstock_run_name # used to set name of crawler, cannot include slashes
        workgroup = "eulp"  # Athena workgroup to use
        glue_service_role = "service-role/AWSGlueServiceRole-default"

    #    # Export parquet files to S3 for Athena/Glue
    #    comstock.create_sightglass_tables(s3_location=f"{s3_dir}/metadata_and_annual_results_aggregates",
    #                                        dataset_name=crawler_name,
    #                                        database_name=database,
    #                                        glue_service_role=glue_service_role)
    #    comstock.fix_timeseries_tables(crawler_name, database)
    #    comstock.create_views(crawler_name, database, workgroup)

    #################Temp for state peak demand stuff##############
    ## Timeseries peaks by state - get all state timeseries data for analysis
    #if comstock.make_timeseries_plots:
    #    from buildstock_query import BuildStockQuery
    #    from comstockpostproc.comstock_query_builder import ComStockQueryBuilder

    #    # Initialize Athena client for timeseries queries
    #    athena_client = BuildStockQuery(
    #        workgroup='vizstock',
    #        db_name='vizstock',
    #        table_name=(
    #            'comstock_amy2018_r3_2025_md_by_state_cnty_vu',
    #            'comstock_amy2018_r3_2025_ts_by_state',
    #            None
    #        ),
    #        buildstock_type='comstock',
    #        db_schema='comstock_oedi',
    #        skip_reports=True
    #    )

    #    # Initialize query builder
    #    query_builder = ComStockQueryBuilder(athena_table_name=comstock.comstock_run_name)

    #    # Build query for all states and all upgrades being processed
    #    state_ts_query = query_builder.get_state_timeseries_query(
    #        upgrade_ids=comstock.upgrade_ids_to_process,
    #        weight_view_table='comstock_amy2018_r3_2025_md_by_state_cnty_vu',
    #        demand_column='out.electricity.total.energy_consumption',
    #        timestamp_grouping='hour',
    #        states=None,  # All states
    #        include_sample_stats=True
    #    )

    #    print("================================================================================")
    #    print("STATE TIMESERIES QUERY:")
    #    print(state_ts_query)
    #    print("================================================================================")

    #    # Execute query
    #    logger.info(f"Querying timeseries data for {len(comstock.upgrade_ids_to_process)} upgrades across all states...")
    #    df_state_timeseries = athena_client.execute(state_ts_query)
    #    logger.info(f"Retrieved {len(df_state_timeseries)} timeseries records")

    #    # Add month and season columns
    #    logger.info("Adding month and season columns to timeseries data...")
    #    df_state_timeseries['time'] = pd.to_datetime(df_state_timeseries['time'])
    #    df_state_timeseries['month'] = df_state_timeseries['time'].dt.month

    #    # Define season mapping function
    #    def map_to_season(month):
    #        if 3 <= month <= 5:
    #            return 'Spring'
    #        elif 6 <= month <= 8:
    #            return 'Summer'
    #        elif 9 <= month <= 11:
    #            return 'Fall'
    #        else:
    #            return 'Winter'

    #    df_state_timeseries['season'] = df_state_timeseries['month'].apply(map_to_season)

    #    # Save results to CSV for inspection (use local path since output_dir may be S3 filesystem)
    #    output_path = os.path.abspath(os.path.join('.', 'state_timeseries_all_upgrades.csv'))
    #    df_state_timeseries.to_csv(output_path, index=False)
    #    logger.info(f"Saved state timeseries data to: {output_path}")

    #    # Calculate peak demand by state, upgrade, and season
    #    logger.info("Calculating peak demand for each state, upgrade, and season...")
    #    demand_col = 'out.electricity.total.energy_consumption'

    #    # Group by state, upgrade, and season - find the maximum consumption
    #    df_peak_demand = df_state_timeseries.groupby(['state', 'upgrade', 'season']).agg({
    #        demand_col: 'max',
    #        'sample_count': 'first',  # Keep one sample_count (same for all rows in a state/upgrade/season)
    #        'units_count': 'first'    # Keep one units_count
    #    }).reset_index()

    #    # Rename column for clarity
    #    df_peak_demand.rename(columns={demand_col: 'peak_demand'}, inplace=True)

    #    # Save peak demand results
    #    peak_output_path = os.path.abspath(os.path.join('.', 'state_peak_demand_by_upgrade_season.csv'))
    #    df_peak_demand.to_csv(peak_output_path, index=False)
    #    logger.info(f"Saved peak demand data ({len(df_peak_demand)} state/upgrade/season combinations) to: {peak_output_path}")

    #################Temp for state peak demand stuff##############

    # Create measure run comparisons; only use if run has measures
    comparison = cspp.ComStockMeasureComparison(comstock, timeseries_locations_to_plot=comstock.timeseries_locations_to_plot, make_comparison_plots = comstock.make_comparison_plots, make_timeseries_plots = comstock.make_timeseries_plots)



    # Export dictionaries corresponding to the exported columns
    #comstock.export_data_and_enumeration_dictionary()

# Code to execute the script
if __name__=="__main__":
    main()
