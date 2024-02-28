from unittest.mock import patch, MagicMock
import pandas as pd


class MockComStock:
    def __init__(self):
        self.patcher = patch('boto3.client')
        self.mock_boto3_client = self.patcher.start()
        self.dummy_client = MagicMock()
        self.mock_boto3_client.return_value = self.dummy_client

        # Mocking the S3 methods since the S3 utilitimix is base class
        # we are not able to mock the class directly
        # more information: https://stackoverflow.com/questions/38928243/patching-a-parent-class
        
        self.patcher_isfile_on_S3 = patch('comstockpostproc.comstock.ComStock.isfile_on_S3')
        self.mock_isfile_on_S3 = self.patcher_isfile_on_S3.start()
        self.mock_isfile_on_S3.return_value = True

        self.patcher_upload_data_to_S3 = patch('comstockpostproc.comstock.ComStock.upload_data_to_S3')
        self.mock_upload_data_to_S3 = self.patcher_upload_data_to_S3.start()
        self.mock_upload_data_to_S3.return_value = None

        self.patcher_read_delimited_truth_data_file_from_S3 = patch('comstockpostproc.comstock.ComStock.read_delimited_truth_data_file_from_S3')
        self.mock_read_delimited_truth_data_file_from_S3 = self.patcher_read_delimited_truth_data_file_from_S3.start()
        self.mock_read_delimited_truth_data_file_from_S3.return_value = pd.DataFrame()

    def stop(self):
        self.patcher.stop()
        self.patcher_isfile_on_S3.stop()
        self.patcher_upload_data_to_S3.stop()
        self.patcher_read_delimited_truth_data_file_from_S3.stop()
