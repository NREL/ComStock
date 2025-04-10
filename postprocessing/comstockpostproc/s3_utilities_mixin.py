# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

"""
# Check, download, and upload data to/from Amazon S3

**Authors:**

- Anthony Fontanini (Anthony.Fontanini@nrel.gov)
- Andrew Parker (Andrew.Parker@nrel.gov)
"""

import os

import boto3
import logging
import botocore
import pandas as pd
import json

logger = logging.getLogger(__name__)


class S3UtilitiesMixin:
    def isfile_on_S3(self, bucket, file_path):
        """
        Check whether file exist on S3.
        Args:
            bucket (string): name of the bucket
            file_path (string): file path of the file to be checked
        Return:
            True or False (boolean)

        """
        s3 = boto3.resource('s3')
        try:
            s3.Object(bucket, file_path).load()
            return True
        except botocore.exceptions.ClientError:
            return False

    def upload_data_to_S3(self, file_path, s3_file_path):
        """
        Upload data from local computer to S3.

        Args:
            file_name (string): path to the file to be uploaded
            s3_file_path (string): target file path on S3
        """
        logger.info('Uploading {}...'.format(file_path))
        # Inputs
        bucket_name = 'eulp'
        s3_file_path = s3_file_path.replace('\\', '/')

        # Perform upload
        self.s3_client.upload_file(file_path, bucket_name, s3_file_path)

    def download_truth_data_file(self, s3_file_path):
        """
        Download a file from s3 to local truth data directory. 
        
        Args:
            s3_file_path (string): File path on AWS S3 without bucket name

        Returns:
            local_path (string): the full local path of the downloaded file
        """
        # Get inputs
        s3_file_path = s3_file_path.replace('\\', '/')
        filename = s3_file_path.split('/')[-1]
        local_path = os.path.join(
            os.path.abspath(os.path.dirname(__file__)), '..',
            'truth_data',
            self.truth_data_version,
            filename
        )

        # Check if file exists, if it doesn't query from s3
        if not os.path.exists(local_path):
            logger.info('Downloading %s from s3...' % filename)
            # Download file
            bucket_name = 'eulp'
            self.s3_client.download_file(bucket_name, s3_file_path, local_path)
        
        return local_path

    def read_delimited_truth_data_file_from_S3(self, s3_file_path, delimiter, args={}):
        """
        Read a delimited truth data file from AWS S3.

        Args:
            s3_file_path (string): File path on AWS S3 without the bucket name
            delimiter (string): The delimiter to use with pd.read_csv(...)
            args (dictionary): Optional additional parameters to pass to read_csv, e.g. {'dtype':'str'}
        Return:
            df (pd.DataFrame): DataFrame read from the s3_file_path
        """
        # # Get inputs
        # s3_file_path = s3_file_path.replace('\\', '/')
        # filename = s3_file_path.split('/')[-1]
        # local_path = os.path.join(
        #     os.path.abspath(os.path.dirname(__file__)), '..',
        #     'truth_data',
        #     self.truth_data_version,
        #     filename
        # )

        # # Check if file exists, if it doesn't query from s3
        # if not os.path.exists(local_path):
        #     logger.info('Downloading %s from s3...' % filename)
        #     # Download file
        #     bucket_name = 'eulp'
        #     self.s3_client.download_file(bucket_name, s3_file_path, local_path)

        local_path = self.download_truth_data_file(s3_file_path)

        # Read file into memory
        if '.parquet' in local_path:
            df = pd.read_parquet(local_path)
        elif '.json' in local_path:
            with open(local_path, 'r') as rfobj:
                lkup = json.load(rfobj)
            return lkup
        else:
            try:
                df = pd.read_csv(local_path, delimiter=delimiter, **args)
            except UnicodeDecodeError:
                df = pd.read_csv(local_path, delimiter=delimiter, encoding='latin-1', **args)

        return df

