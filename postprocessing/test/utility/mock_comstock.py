from unittest.mock import patch, MagicMock
import pandas as pd
import polars as pl
from unittest.mock import patch
import logging


class MockComStock:
    def __init__(self):
        self.patcher = patch('boto3.client')
        self.mock_boto3_client = self.patcher.start()
        self.dummy_client = MagicMock()
        self.mock_boto3_client.return_value = self.dummy_client
        # self.data = data

        # Mocking the S3 methods since the S3 utilitimix is base class
        # we are not able to mock the class directly
        # more information: https://stackoverflow.com/questions/38928243/patching-a-parent-class
        
        self.patcher_isfile_on_S3 = patch('comstockpostproc.comstock.ComStock.isfile_on_S3')
        self.mock_isfile_on_S3 = self.patcher_isfile_on_S3.start()
        self.mock_isfile_on_S3.side_effect = self.mock_isfile_on_S3_action

        self.patcher_upload_data_to_S3 = patch('comstockpostproc.comstock.ComStock.upload_data_to_S3')
        self.mock_upload_data_to_S3 = self.patcher_upload_data_to_S3.start()
        self.mock_upload_data_to_S3.side_effect = self.mock_upload_data_to_S3_action

        self.patcher_read_delimited_truth_data_file_from_S3 = patch('comstockpostproc.comstock.ComStock.read_delimited_truth_data_file_from_S3')
        self.mock_read_delimited_truth_data_file_from_S3 = self.patcher_read_delimited_truth_data_file_from_S3.start()
        self.mock_read_delimited_truth_data_file_from_S3.side_effect = self.mock_read_delimited_truth_data_file_from_S3_action

        self.original_read_csv = pl.read_csv 
        self.patcher__read_csv = patch('polars.read_csv')
        self.mock__read_csv = self.patcher__read_csv.start()
        self.mock__read_csv.side_effect = self.mock__read_csv_action

    def mock_upload_data_to_S3_action(self, file_path, s3_file_path):
        logging.info('Uploading {}...'.format(file_path))

    def mock_read_delimited_truth_data_file_from_S3_action(self, s3_file_path, delimiter):
        logging.info('reading from path: {} with delimiter {}'.format(s3_file_path, delimiter))
        return pd.DataFrame()

    def mock_isfile_on_S3_action(self, bucket, file_path):
        logging.info('Mocking isfile_on_S3')
        return True
    
    def mock__read_csv_action(self, *args, **kwargs):
        logging.info('Mocking read_csv from ComStock')
        filePath = None
        path = args[0]
        if "EJSCREEN" in path:
            filePath = "/truth_data/v01/EPA/EJSCREEN/EJSCREEN_Tract_2020_USPR.csv"
        elif "1.0-communities.csv" in path:
            filePath = "/truth_data/v01/EPA/CEJST/1.0-communities.csv"
        if not filePath: 
            return self.original_read_csv(*args, **kwargs)
        return self.original_read_csv(filePath, **kwargs)

    def stop(self):
        self.patcher.stop()
        self.patcher_isfile_on_S3.stop()
        self.patcher_upload_data_to_S3.stop()
        self.patcher_read_delimited_truth_data_file_from_S3.stop()
        self.patcher__read_csv.stop()