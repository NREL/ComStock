#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import pytest
import comstockpostproc as cspp
import os
import pandas as pd

logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

class TestIntegration:

    @pytest.fixture(autouse=True)
    def setup_and_teardown(self):
        self.widePath = "../output/metadata_and_annual_results/national/full/csv/baseline.csv"
        

    def test_1_Initial_comstock(self):
        # ComStock run
        logging.info('Running ComStock...')
        comstock = cspp.ComStock(
            s3_base_dir=None,  # If run not on S3, download results_up**.parquet manually
            comstock_run_name='bsb-integration-test-baseline',  # Name of the run on S3
            comstock_run_version='bsb-integration-test-baseline',  # Use whatever you want to see in plot and folder names
            comstock_year=2018,  # Typically don't change this
            athena_table_name=None,  # Typically don't change this
            truth_data_version='v01',  # Typically don't change this
            buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
            acceptable_failure_percentage=0.05,  # Can increase this when testing and high failure are OK
            drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
            color_hex='#0072B2',  # Color used to represent this run in plots
            skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
            reload_from_csv=False, # True if CSV already made and want faster reload times
            include_upgrades=False  # False if not looking at upgrades
            )

        # CBECS
        cbecs = cspp.CBECS(
            cbecs_year=2018,  # 2012 and 2018 currently available
            truth_data_version='v01',  # Typically don't change this
            color_hex='#009E73',  # Color used to represent CBECS in plots
            reload_from_csv=False  # True if CSV already made and want faster reload times
            )

        reload_flag = True #set to True only for development, turn to False when running CI.

        # Stock Estimation for Apportionment:
        stock_estimate = cspp.Apportion(
            stock_estimation_version='2024R2',  # Only updated when a new stock estimate is published
            truth_data_version='v01',  # Typically don't change this
            reload_from_cache=reload_flag
        )

        # Scale ComStock runs to the 'truth data' from StockE V3 estimates using bucket-based apportionment
        comstock.add_weights_aportioned_by_stock_estimate(apportionment=stock_estimate, reload_from_cache=reload_flag)
        # Scale ComStock run to CBECS 2018 AND remove non-ComStock buildings from CBECS
        comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)


        # Define the geographic partitions to export
        geo_exports = [
            {'geo_top_dir': 'national',
                'partition_cols': {},
                'aggregation_levels': [comstock.TRACT_ID],
                'data_types': ['full'],
                'file_types': ['csv'],
            },
        ]

        # Export the results
        comstock.export_metadata_and_annual_results(geo_exports)

    # def test_2_verifyExistance(self):
    #     assert os.path.isfile(self.widePath)

    # def test_3_verifyWideShape(self):
    #     wide = pd.read_csv(self.widePath)
    #     assert wide.shape == (4, 892)

    # def test_4_verifyWideColumns(self):
    #     wide = pd.read_csv(self.widePath)
    #     assert (wide.completed_status == "Success").all()
