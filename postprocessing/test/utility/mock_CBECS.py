from unittest.mock import patch, MagicMock
import pandas as pd
import polars as pl
import logging
import comstockpostproc
from unittest.mock import patch


class MockCBECS:

    def __init__(self):
        self.patcher = patch('boto3.client')
        self.mock_boto3_client = self.patcher.start()
        self.dummy_client = MagicMock()
        self.mock_boto3_client.return_value = self.dummy_client

        self.patcher_read_delimited_truth_data_file_from_S3 = patch('comstockpostproc.cbecs.CBECS.read_delimited_truth_data_file_from_S3')
        self.mock_read_delimited_truth_data_file_from_S3 = self.patcher_read_delimited_truth_data_file_from_S3.start()
        self.mock_read_delimited_truth_data_file_from_S3.side_effect = self.mock_read_delimited_truth_data_file_from_S3_action

        self.patcher__read_csv = patch('comstockpostproc.cbecs.CBECS._read_csv')
        self.mock__read_csv = self.patcher__read_csv.start()
        self.mock__read_csv.side_effect = self.mock__read_csv_action

    def mock_read_delimited_truth_data_file_from_S3_action(self, s3_file_path, delimiter):
        logging.info('reading from path: {} with delimiter {}'.format(s3_file_path, delimiter))
        return pd.DataFrame()
    
    def mock__read_csv_action(self, **kwargs):
        logging.info('Mocking read_csv from CBECS')
        path = kwargs["file_path"]
        if "CBECS_2018_microdata.csv" in path:
            filePath =  "/truth_data/v01/EIA/CBECS/CBECS_2018_microdata.csv"
        elif "CBECS_2018_microdata_codebook.csv" in path:
            filePath =  "/truth_data/v01/EIA/CBECS/CBECS_2018_microdata_codebook.csv"

        del kwargs["file_path"]
        return pd.read_csv(filePath, **kwargs)

    def stop(self):
        self.patcher.stop()
        self.patcher_read_delimited_truth_data_file_from_S3.stop()
        self.patcher__read_csv.stop()