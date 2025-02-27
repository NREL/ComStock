#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging

import comstockpostproc as cspp
import polars

# logging.basicConfig(level='DEBUG', force=True)  # Use DEBUG, INFO, or WARNING
logging.basicConfig(
    format='%(asctime)s %(levelname)-8s %(message)s',
    level=logging.INFO,
    datefmt='%Y-%m-%d %H:%M:%S', force=True)
logger = logging.getLogger(__name__)

# @profile
def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='eulp/euss_com',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='pv_10k_3',  # Name of the run on S3
        comstock_run_version='pv_10k_3',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.05,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_csv=False, # True if CSV already made and want faster reload times
        include_upgrades=True,  # False if not looking at upgrades
        athena_table_name='ami_comparison',
        upgrade_ids_to_skip=[],
        states={
                #'MN': 'Minnesota',  # specify state to use for timeseries plots in dictionary format. State ID must correspond correctly.
                'MA':'Massachusetts',
                'OR': 'Oregon',
                'LA': 'Louisiana',
                #'AZ': 'Arizona',
                #'TN': 'Tennessee'
                },
        # upgrade_ids_to_skip=[3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32],
        # upgrade_ids_to_skip=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32]
        upgrade_ids_for_comparison={"compare_1" : [0, 1]} # Use {'<Name you want for comparison run folder>':[0,1,2]}
        )
    
    # CBECS
    cbecs = cspp.CBECS(
        cbecs_year=2018,  # 2012 and 2018 currently available
        truth_data_version='v01',  # Typically don't change this
        color_hex='#009E73',  # Color used to represent CBECS in plots
        reload_from_csv=False  # True if CSV already made and want faster reload times
        )
    
    # logger.info(f"comstock.COLS_ENDUSE_ANN_ENGY is {comstock.COLS_ENDUSE_ANN_ENGY}")
    # missing_cols = []
    # for col in comstock.COLS_ENDUSE_ANN_ENGY:
    #     if col not in comstock.data.columns:
    #         missing_cols.append(col)

    # logger.info(f"length of COL_ENDUSE_ANN_ENGY is {len(comstock.COLS_ENDUSE_ANN_ENGY)} {'out.electricity.fans.energy_consumption..kwh' in comstock.data.columns}")
    # # logger.info(f{'out.electricity.fans.energy_consumption..kwh' in comstock.data.columns})
    # logger.info(f"missing cols are {missing_cols}, missing cols length is {len(missing_cols)}") 
    # logger.info(f"comstock.data shape: {comstock.data.describe()}")

    # raise NotImplementedError("This script is not yet complete. Please check the code and update as needed.")
    # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
    # This is how weights in the models are set to represent national energy consumption
    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # assert isinstance(comstock.data, pl.LazyFrame)
    # assert isinstance(cbecs.data, pl.LazyFrame)

    # Uncomment this to correct gas consumption for a ComStock run to match CBECS
    # Don't typically want to do this
    # comstock_a.correct_comstock_gas_to_match_cbecs(cbecs)

    # Export CBECS and ComStock data to wide and long formats for Tableau and to skip processing later
    # cbecs.export_to_csv_wide()  # May comment this out if CSV output isn't needed
    # comstock.export_to_csv_wide()  # May comment this out if CSV output isn't needed
    # comstock.export_to_csv_long()  # May comment this out if CSV output isn't needed
    # comstock.add_national_scaling_weights()
    comstock.export_to_parquet_wide()
    comstock.export_to_csv_wide()
    # Create measure run comparisons; only use if run has measures
    
    cspp.ComStockMeasureComparison(comstock, states=comstock.states, make_comparison_plots=True, make_timeseries_plots=False)
    cspp.ComStockToCBECSComparison([comstock], [cbecs], upgrade_id=0)

    # EIA
    eia = cspp.EIA(
        year=2018,
        truth_data_version="v01",
        reload_from_csv=False # True if CSV already made and want faster reload times
    )
    
    ami = cspp.AMI(
        truth_data_version='v01',
        reload_from_csv=False
    )
    comstock.download_timeseries_data_for_ami_comparison(ami, reload_from_csv=False, save_individual_regions=False)

    # comparison
    comparison = cspp.ComStockToAMIComparison(comstock, ami, make_comparison_plots=True)
    comparison.export_plot_data_to_csv_wide()

    #comparison of EIA
    comp = cspp.ComStockToEIAComparison(eia_list=[eia], comstock_list=[comstock], upgrade_id='All',make_comparison_plots=True)
    comp.export_to_csv_wide()
    # Export the comparison data to wide format for Tableau
    comparison.export_to_csv_wide()

# Code to execute the script
if __name__=="__main__":
    main()
