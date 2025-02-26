import os
import json
import boto3
import logging
import botocore
import pandas as pd
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class EIA930(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', year=2018, reload_from_csv=False):
        """
        A class to load and process EIA 930 demand data by EIA Balancing Authority
        Data compiled and cleaned by Kodi Obika (NREL): https://github.nrel.gov/cobika/reeds_historic_load_data
        Reference data from https://catalystcoop-pudl.readthedocs.io/en/latest/data_dictionaries/pudl_db.html#core-eia-codes-balancing-authorities

        Other sources (not currently used): 
            - EIA Cleaned Hourly Electricity Demand Data: https://github.com/truggles/EIA_Cleaned_Hourly_Electricity_Demand_Data/ - another source for cleaaned EIA 930 data, similar to Kodi Obika's.

        Args:
            truth_data_version (string): The version of EIA truth data. 'v01'
            year (int): year of full hourly data to extract. Raw data timestamps are in UTC for years 2016-2023. Since this class
                extracts the local time full years, available options are 2017-2022 until more data is available.
            reload_from_csv (Bool): option to reload processed data from csv. If no processed data is found, will be ignored and data processed and saved.

        Attributes:
            referece_data (DataFrame): dataframe of balancing authority code, name, description, reporting timezone etc.
            data (DataFrame): dataframe with of hourly demand for calendar year 2018 for all BAs. 
                Index is timezone-naive DateTimeIndex, but set to reporting timezone to align with the calendar year. Does not include DST adjustments.
                Column headers are BA Code. Values are in MWh.
        """
        self.truth_data_version = truth_data_version
        self.year = year
        self.reload_from_csv = reload_from_csv

        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        if not os.path.exists(self.processed_dir):
            os.makedirs(self.processed_dir)
        self.processed_filename = f'eia930_{self.year}_demand.csv'

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        # get data
        self.reference_data = self.load_reference_data()
        if self.reload_from_csv:
            processed_path = os.path.join(self.processed_dir, self.processed_filename)
            if os.path.exists(processed_path):
                logger.info(f'Reloading EIA 930 {self.year} data from csv')
                self.data = pd.read_csv(processed_path, parse_dates=True, index_col=0)
            else:
                logger.warning(f'No processed data found for {self.processed_filename}. Processing from truth data.')
                self.data = self.load_demand_data()
        else:
            self.data = self.load_demand_data()

    def load_reference_data(self):
        reference_data_path = f"truth_data/{self.truth_data_version}/EIA/EIA Form 930/core_eia__codes_balancing_authorities.parquet"
        df = self.read_delimited_truth_data_file_from_S3(reference_data_path, ',')
        return df

    def load_demand_data(self):
        ba_timestamps = self.reference_data
        regional_profiles = {}

        local_dir = os.path.join(self.truth_data_dir, 'EIA930_regions')
        if not os.path.exists(local_dir):
            os.makedirs(local_dir)
        
        s3_resource = boto3.resource('s3')
        bucket = s3_resource.Bucket('eulp')
        s3_files_path = f'truth_data/{self.truth_data_version}/EIA/EIA Form 930/regions/'
        for obj in bucket.objects.filter(Prefix=s3_files_path):
            local_file_path = os.path.join(local_dir, os.path.basename(obj.key))
            if not os.path.exists(local_file_path):
                logger.info('Downloading %s from s3..' % os.path.basename(obj.key))
                bucket.download_file(obj.key, local_file_path)
            df = pd.read_csv(local_file_path, parse_dates=['timestamp'], index_col='timestamp')

            profile = os.path.basename(obj.key).replace('.csv', '')

            # get profile in local time
            timezone = ba_timestamps.loc[ba_timestamps['code'] == profile]['report_timezone'].iloc[0]
            # localize timestamp
            df['local_time'] = df.index.tz_localize('UTC').tz_convert(timezone)

            # extract local annual profile
            mask = (df['local_time'] > f'{self.year}-01-01 00:00:00') & \
                (df['local_time'] <= f'{self.year + 1}-01-01 00:00:00')
            
            try:
                df = df.loc[mask]
                assert(len(df.index) == 8760)
            except:
                logger.error(f'Full data not available for year {self.year}')
                exit(code=1)

            df.reset_index(inplace=True)
            regional_profiles[profile] = df['value']

        # construct new tz-naive date range for index to avoid DST adjustments
        new_index = pd.date_range(f'{self.year}-01-01 01:00:00', f'{self.year + 1}-01-01 00:00:00', freq='h')

        df = pd.DataFrame(regional_profiles)
        df.set_index(new_index, inplace=True)

        df.to_csv(os.path.join(self.processed_dir, self.processed_filename))
        
        return df

