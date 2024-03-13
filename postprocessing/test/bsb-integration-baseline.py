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
        self.widePath = "../output/ComStock bsb-integration-test-baseline 2018/ComStock wide.csv"
    
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

        # Scale both ComStock runs to CBECS 2018 AND remove non-ComStock buildings from CBECS
        # This is how weights in the models are set to represent national energy consumption
        comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

        # Uncomment this to correct gas consumption for a ComStock run to match CBECS
        # Don't typically want to do this
        # comstock_a.correct_comstock_gas_to_match_cbecs(cbecs)

        # Export CBECS and ComStock data to wide and long formats for Tableau and to skip processing later
        cbecs.export_to_csv_wide()  # May comment this out if CSV output isn't needed
        comstock.export_to_csv_wide()  # May comment this out if CSV output isn't needed
        # comstock_a.export_to_csv_long()  # Long format useful for stacking end uses and fuels

        # Compare multiple ComStock runs to one another and to CBECS
        comparison = cspp.ComStockToCBECSComparison(
            cbecs_list=[cbecs],
            comstock_list = [comstock],
            make_comparison_plots=True
            )

        # Export the comparison data to wide format for Tableau
        comparison.export_to_csv_wide()

    def test_2_verifyExistance(self):
        assert os.path.isfile(self.widePath)

    def test_3_verifyWideShape(self):
        wide = pd.read_csv(self.widePath)
        assert wide.shape == (4, 892)

    def test_4_verifyWideColumns(self):
        wide = pd.read_csv(self.widePath)
        assert (wide.completed_status == "Success").all()
