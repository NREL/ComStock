from unittest.mock import patch, MagicMock
import pandas as pd
from unittest.mock import patch


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
        # self.mock_isfile_on_S3.return_value = True
        self.mock_isfile_on_S3.side_effect = self.mock_isfile_on_S3_action

        self.patcher_upload_data_to_S3 = patch('comstockpostproc.comstock.ComStock.upload_data_to_S3')
        self.mock_upload_data_to_S3 = self.patcher_upload_data_to_S3.start()
        # self.mock_upload_data_to_S3.return_value = None
        self.mock_upload_data_to_S3.side_effect = self.mock_upload_data_to_S3_action

        self.patcher_read_delimited_truth_data_file_from_S3 = patch('comstockpostproc.comstock.ComStock.read_delimited_truth_data_file_from_S3')
        self.mock_read_delimited_truth_data_file_from_S3 = self.patcher_read_delimited_truth_data_file_from_S3.start()
        self.mock_read_delimited_truth_data_file_from_S3.side_effect = self.mock_read_delimited_truth_data_file_from_S3_action

    def mock_upload_data_to_S3_action(self, file_path, s3_file_path):
        print('Uploading {}...'.format(file_path))

    def mock_read_delimited_truth_data_file_from_S3_action(self, s3_file_path, delimiter):
        print('reading from path: {} with delimiter {}'.format(s3_file_path, delimiter))
        return pd.DataFrame()

    def mock_isfile_on_S3_action(self, bucket, file_path):
        print('Mocking isfile_on_S3')
        return True

    def stop(self):
        self.patcher.stop()
        self.patcher_isfile_on_S3.stop()
        self.patcher_upload_data_to_S3.stop()
        self.patcher_read_delimited_truth_data_file_from_S3.stop()
