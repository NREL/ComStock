#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging

import comstockpostproc as cspp


logging.basicConfig(level='INFO', force=True)  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

@profile
def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='cycle3_euss_10k_df_2',  # Name of the run on S3
        comstock_run_version='cycle3_euss_10k_df_2',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.05,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_csv=False, # True if CSV already made and want faster reload times
        include_upgrades=True,  # False if not looking at upgrades
        athena_table_name=None,
        upgrade_ids_to_skip=[],
        # upgrade_ids_to_skip=[3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32],
        # upgrade_ids_to_skip=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32]
        # upgrade_ids_for_comparison={'Andrew test': [0,1,2]} # Use {'<Name you want for comparison run folder>':[0,1,2]}
        )

    # CBECS
    # cbecs = cspp.CBECS(
    #     cbecs_year=2018,  # 2012 and 2018 currently available
    #     truth_data_version='v01',  # Typically don't change this
    #     color_hex='#009E73',  # Color used to represent CBECS in plots
    #     reload_from_csv=False  # True if CSV already made and want faster reload times
    #     )

    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    # This is how weights in the models are set to represent national energy consumption
    # comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # Uncomment this to correct gas consumption for a ComStock run to match CBECS
    # Don't typically want to do this
    # comstock_a.correct_comstock_gas_to_match_cbecs(cbecs)

    # Export CBECS and ComStock data to wide and long formats for Tableau and to skip processing later
    # cbecs.export_to_csv_wide()  # May comment this out if CSV output isn't needed
    # comstock.export_to_csv_wide()  # May comment this out if CSV output isn't needed
    # comstock.export_to_csv_long()  # May comment this out if CSV output isn't needed
    comstock.export_to_parquet_wide()
    # Create measure run comparisons; only use if run has measures
    # comparison = cspp.ComStockMeasureComparison(comstock, make_comparison_plots=True)

    # Export the comparison data to wide format for Tableau
    # comparison.export_to_csv_wide()

# Code to execute the script
if __name__=="__main__":
    main()
