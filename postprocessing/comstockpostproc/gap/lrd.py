import os
import json
import boto3
import logging
import botocore
import datetime
import numpy as np
import pandas as pd
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

# Create logger for AWS queries
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

UTIL_NAMES = [
    # 'AEP Ohio',
    'AES Ohio',
    # 'Appalachian Power',
    # 'BGE',
    # 'Commonwealth Edison',
    # 'Duke Energy Ohio',
    # 'Duquesne Light Company',
    # 'ERCOT',
    # 'First Energy Ohio',
    'First Energy PA',
    # 'National Grid Upstate NY',
    # 'PECO',
    'PG&E',
    # 'PSE&G',
    # 'SCE_dynamic',
    # 'SCE_static'

]

class LoadResearchData(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', utility_name=None, reload_from_csv=True, metadata_only=False):
        """
        Class to load and process Load Research Data for various utilities as hourly profiles
        """

        self.truth_data_version = truth_data_version
        self.reload_from_csv = reload_from_csv
        self.metadata_only = metadata_only
        
        if isinstance(utility_name, str) and (utility_name in UTIL_NAMES):
            self.utility_name = utility_name
        else:
            logger.error(f"{utility_name} not a recognized utility name. Options are: {','.join(UTIL_NAMES)}.")
            exit()
        
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        # make directories
        for p in [self.truth_data_dir, self.processed_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        self.processed_filename = f'LRD_{self.utility_name}_2018.csv'
        self.processed_path = os.path.join(self.processed_dir, self.processed_filename)

        # lrd_metadata.json contains information on the source and descriptions of raw LRD files, and their structure for parsing
        # TODO: upload to '2018 raw LRD' S3 dir
        metadata_path = f'truth_data/{self.truth_data_version}/LRD_data/2018 raw LRD/lrd_metadata.json'
        self.metadata = self.read_delimited_truth_data_file_from_S3(metadata_path, delimiter=',')
        if self.metadata_only:
            logger.info('Returning LRD metadata only.')
            return

        self.data = self.process_lrd_for_utility()

    def process_lrd_for_utility(self):

        if self.reload_from_csv:
            if os.path.exists(self.processed_path):
                logger.info(f'Reloading {self.utility_name} LRD from CSV')
                df = pd.read_csv(self.processed_path, index_col=0, parse_dates=True)
                return df

        # if-else ladder to call lrd-specific processing logic
        if self.utility_name == 'AES Ohio':
            return self.process_aes_ohio_lrd()
        elif self.utility_name == 'First Energy PA':
            return self.process_first_energy_pa_lrd()
        elif self.utility_name == 'PG&E':
            return self.process_pge_lrd()

    def process_aes_ohio_lrd(self):
        logger.info('Processing AES Ohio LRD')
        lrd_data = pd.DataFrame()

        lrd_info = [obj for obj in self.metadata if obj['lrd_name'] == self.utility_name]
        for i in lrd_info:
            s3_file_path = f"truth_data/{self.truth_data_version}/LRD_data/2018 raw LRD/{i['filename']}"
            print(s3_file_path)
            local_path = self.download_truth_data_file(s3_file_path)

            df = pd.read_excel(local_path, sheet_name=i['sheet_name'], header=i['header_row'], usecols=i['cols'])
            df.columns = [col.strip() for col in df.columns]
            df['Datetime'] = pd.to_datetime(df[['Year', 'Month', 'Day']])
            df['Hr Ending'] = pd.to_timedelta(df['Hr Ending'], unit='h')
            df['Datetime'] = df['Datetime'] + df['Hr Ending']
            df.set_index('Datetime', inplace=True) 
            df.sort_index(inplace=True)
            df = df.loc['2018-01-01 01:00:00': '2019-01-01 00:00:00']
            df.drop(columns=[col for col in df.columns if not any(str in col for str in i['commercial_cols'] + i['residential_cols'] + i['industrial_cols'])], inplace=True)
            
            lrd_data = pd.concat([lrd_data, df], axis=1)
        
        lrd_data.to_csv(self.processed_path)

        return lrd_data
            
    def process_first_energy_pa_lrd(self):
        logger.info('Processing First Energy PA LRD')
        lrd_data = pd.DataFrame()

        # get me
        lrd_info = [obj for obj in self.metadata if obj['lrd_name'] == self.utility_name]
        for i in lrd_info:
            abbrev = i['filename'].split('_')[1]
            s3_file_path = f"truth_data/{self.truth_data_version}/LRD_data/2018 raw LRD/{i['filename']}"
            local_path = self.download_truth_data_file(s3_file_path)
    
            df = pd.read_excel(local_path, sheet_name=i['sheet_name'], header=i['header_row'], usecols=i['cols'])
            
            hour_col = next(col for col in df.columns if 'Hour' in col)
            
            df['Date'] = df['Date'].ffill()
            df['Datetime'] = df['Date'] + pd.to_timedelta(df[hour_col], unit='h')
            df.set_index('Datetime', inplace=True)
            df.sort_index(inplace=True)
            df = df.loc['2018-01-01 01:00:00': '2019-01-01 00:00:00']
            com_col = f'{abbrev}_Commercial_Total_kWh'
            res_col = f'{abbrev}_Residential_Total_kWh'
            ind_col = f'{abbrev}_Industrial_Total_kWh'
            df[com_col] = df[i['commercial_cols']].sum(axis=1)
            df[res_col] = df[i['residential_cols']].sum(axis=1)
            df[ind_col] = df[i['industrial_cols']].sum(axis=1)

            lrd_data = pd.concat([lrd_data, df[[com_col, res_col, ind_col]]], axis=1)
        
        lrd_data.to_csv(self.processed_path)

        return lrd_data

    def process_pge_lrd(self):
        logger.info('Processing PG&E LRD')
        lrd_data = pd.DataFrame()

        def time_to_timedelta(timestring):
            hour = datetime.datetime.strptime(timestring, '%I:%M %p').hour
            if hour == 0:
                hour = 24
            return datetime.timedelta(hours=hour)
        
        lrd_info = [obj for obj in self.metadata if obj['lrd_name'] == self.utility_name][0]

        for filename in lrd_info["filenames"]:
            s3_file_path = f"truth_data/{self.truth_data_version}/LRD_data/2018 raw LRD/PG&E_{filename}_dynamic_2001.csv"
            df = self.read_delimited_truth_data_file_from_S3(s3_file_path, delimiter='\t')
            col = f'{filename}_kW'
            df = df.melt(id_vars=['Date'],
                         value_vars=df.columns[2:],
                         var_name='Hour',
                         value_name=col)
            df['Hour'] = df['Hour'].str.upper().apply(time_to_timedelta)
            df['Datetime'] = pd.to_datetime(df['Date']) + df['Hour']
            df.set_index('Datetime', inplace=True)
            df.sort_index(inplace=True)
            df = df.loc['2018-01-01 01:00:00': '2019-01-01 00:00:00']
            df = df[[col]].astype(float)

            lrd_data = pd.concat([lrd_data, df], axis=1)

        return lrd_data