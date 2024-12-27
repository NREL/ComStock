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
import polars as pl
import json
import gzip
import tarfile
from io import BytesIO

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

    def read_delimited_truth_data_file_from_S3(self, s3_file_path, delimiter):
        """
        Read a delimited truth data file from AWS S3.

        Args:
            s3_file_path (string): File path on AWS S3 without the bucket name
            delimiter (string): The delimiter to use with pd.read_csv(...)
        Return:
            df (pd.DataFrame): DataFrame read from the s3_file_path
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

        # Read file into memory
        if '.parquet' in local_path:
            df = pd.read_parquet(local_path)
        elif '.json' in local_path:
            with open(local_path, 'r') as rfobj:
                lkup = json.load(rfobj)
            return lkup
        else:
            try:
                df = pd.read_csv(local_path, delimiter=delimiter)
            except UnicodeDecodeError:
                df = pd.read_csv(local_path, delimiter=delimiter, encoding='latin-1')

        return df

    def write_polars_csv_to_s3_or_local(self, data: pl.DataFrame, out_fs, out_path):
        # s3_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2024/comstock_amy2018_release_2/junk_data/'

        import s3fs

        # If local, write uncompressed CSV
        if not isinstance(out_fs, s3fs.core.S3FileSystem):  # s3 doesn't need folder creation
            data.write_csv(out_path)
            return True

        # Create a tar archive in memory that contains the CSV
        tar_buffer = BytesIO()
        with tarfile.open(mode='w', fileobj=tar_buffer) as tar:
            # Get CSV data
            csv_buffer = BytesIO()
            data.write_csv(csv_buffer)
            csv_buffer.seek(0)

            # Create a TarInfo object with file metadata
            tarinfo = tarfile.TarInfo(name='output.csv')
            tarinfo.size = len(csv_buffer.getvalue())

            # Add the CSV data to the tar archive
            tar.addfile(tarinfo, csv_buffer)

        file_name = out_path.split('/')[-1]
        print(f'file_name: {file_name}')
        # Compress the tar archive with gzip
        tar_buffer.seek(0)
        with open(f'{file_name}.csv.gz', 'wb') as f_out:
            with gzip.GzipFile(filename=f'{file_name}.csv', mode='wb', fileobj=f_out) as gz:
                gz.write(tar_buffer.getvalue())

        # Upload directly to S3
        bucket_name = out_path.split('/')[0]
        print(f'bucket_name: {bucket_name}')
        s3_key = '/'.join(out_path.split('/')[1:]) + '.gz'
        print(f's3_key: {s3_key}')
        s3_client = boto3.client('s3')
        try:
            tar_buffer.seek(0)
            s3_client.upload_fileobj(
                tar_buffer,      # File-like object
                bucket_name,     # Bucket name
                s3_key          # S3 object key
            )
            print(f"Successfully uploaded to s3://{bucket_name}/{s3_key}")
        except Exception as e:
            print(f"Upload failed: {str(e)}")
        finally:
            # Clean up
            csv_buffer.close()
            tar_buffer.close()

        # Clean up
        csv_buffer.close()
        tar_buffer.close()
