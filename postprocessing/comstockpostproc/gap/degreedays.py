import os
import re
import csv
import boto3
import logging
import botocore
import pandas as pd
from datetime import datetime
from collections import defaultdict
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

YEARS = list(range(2013, 2024))
FREQS = ['Daily', 'Monthly']

class DegreeDays(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', freq='Daily', year='All', reload_from_csv=True):
        """
        A class to process state population-weighted degree-day information.

        Args:
            truth_data_version
            freq (String): one of 'Daily', 'Monthly'
                Daily population-weighted degree-days from https://ftp.cpc.ncep.noaa.gov/htdocs/degree_days/weighted/daily_data/
                Monthly population-weighted degree-days from https://ftp.cpc.ncep.noaa.gov/htdocs/products/analysis_monitoring/cdus/degree_days/archives/Heating%20degree%20Days/monthly%20states/
            year (Int, List, String): year of data to return, from 2013 - 2023, or list of years in that range, or 'All' for all years
        
        Attributes:
            data (DataFrame): processed dataframe. 
                Freq of 'Daily' will produce a dataframe with DateTime index at frequency 'day', with column headers as tuples of (state abbrev, 'cdd/hdd'). Only includes CONUS states and DC.
                e.g.: 
                |                     |   ('AL', 'cdd') |   ('AR', 'cdd') |   ('AZ', 'cdd') |
                |:--------------------|----------------:|----------------:|----------------:|
                | 2013-01-01 00:00:00 |               0 |               0 |               0 |
                | 2013-01-02 00:00:00 |               0 |               0 |               0 |
                | 2013-01-03 00:00:00 |               0 |               0 |               0 |

                Freq of 'Monthly' will produce a dataframe with tuple of ('year', 'month') as index and cols of tuples of ('MONTH', 'cdd/hdd'). Includes all states and DC as 'DISTRICT COLUMBIA'.
                e.g.:
                |            |   ('ALABAMA', 'cdd') |   ('ALASKA', 'cdd') |   ('ARIZONA', 'cdd') |
                |:-----------|---------------------:|--------------------:|---------------------:|
                | (2013, 4)  |                  166 |                1122 |                   82 |
                | (2013, 8)  |                    0 |                 216 |                    0 |
                | (2013, 12) |                  541 |                1569 |                  495 |
        """

        self.truth_data_version = truth_data_version

        if freq in FREQS:
            self.freq = freq
        else:
            logger.error(f"Freq input should be one of {FREQS}. Received: {freq}.")

        self.reload_from_csv = reload_from_csv
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')

        # make directories
        for p in [self.truth_data_dir, self.processed_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        # process year input
        year_str = year
        if year == 'All':
            self.year = YEARS
        elif isinstance(year, int) & (year in YEARS):
            self.year = [year]
        elif isinstance(year, list) & all(y in YEARS for y in year):
            self.year = year
            year = [str(i) for i in year]
            year_str = '_'.join(year)
        else:
            logger.error(f"Year input should be 'All' or one or more of years in {YEARS}. Received: {year}.")
    
        self.processed_filename = f'pop-wtd_deg-days_{self.freq}_{year_str}.csv'


        if self.reload_from_csv:
            processed_path = os.path.join(self.processed_dir, self.processed_filename)
            if os.path.exists(processed_path):
                logger.info('Reloading data from csv')
                if self.freq == 'Daily':
                    read_args = {'header': [0,1], 'index_col': 0, 'parse_dates':True}
                else:
                    read_args = {'header': [0,1], 'index_col': [0,1], 'skipinitialspace':True}

                self.data = pd.read_csv(processed_path, **read_args)
            else:
                logger.warning(f'No procesesd data found for {self.processed_filename}. Processing from truth data.')
                self.load_and_process_truth_data()
        else:
            self.load_and_process_truth_data()


    def load_and_process_truth_data(self):
        if self.freq == 'Daily':
            degree_days = pd.DataFrame()

            for y in self.year:
                local_dir = os.path.join(self.truth_data_dir, f'{self.freq} degree days', str(y))
                if not os.path.exists(local_dir):
                    os.makedirs(local_dir)

                year_data = pd.DataFrame()
                for k, v in {'cdd':'Cooling', 'hdd':'Heating'}.items():
                    file_name = f'StatesCONUS.{v}.txt'
                    local_path = os.path.join(local_dir, file_name)
                    s3_file_path = f'truth_data/{self.truth_data_version}/degree days/daily population-weighted/{y}/{file_name}'
                    if not os.path.exists(local_path):
                        logger.info(f'downloading {y} state population-weighted daily degree-days from S3')
                        bucket_name = 'eulp'
                        try:
                            self.s3_client.download_file(bucket_name, s3_file_path, local_path)
                        except:
                            logger.error(f'Could not download file from s3: {s3_file_path}')

                    df = pd.read_csv(local_path, delimiter='|', skiprows=3, index_col='Region')
                    df = df.T
                    df.index = pd.to_datetime(df.index, format='%Y%m%d')
                    df.columns = pd.MultiIndex.from_product([df.columns, [k]])
                    year_data = pd.concat([year_data, df], axis=1)

                degree_days = pd.concat([degree_days, year_data], axis=0)

            logger.info(f'Saving processed data to {self.processed_dir}/{self.processed_filename}')
            degree_days.to_csv(os.path.join(self.processed_dir, self.processed_filename))

            self.data = degree_days

        elif self.freq == 'Monthly':
            # these text files are not delimited, but column-formatted, so parse with regex and organize as 
            # dict of dicts with tuple keys, where {(year, month): {(state, hdd/cdd): value}}
            # value is 'Month Total', i.e. the first numeric column

            all_data = defaultdict(dict)

            for y in self.year:
                local_dir =  os.path.join(self.truth_data_dir, f'{self.freq} degree days', str(y))
                if not os.path.exists(local_dir):
                    os.makedirs(local_dir)
                
                    # setup s3 resource
                    s3_resource = boto3.resource('s3')
                    bucket = s3_resource.Bucket('eulp')
                    s3_files_path = f'truth_data/{self.truth_data_version}/degree days/monthly population-weighted/{y}'

                    for obj in bucket.objects.filter(Prefix=s3_files_path):
                        
                        file_name = os.path.basename(obj.key)
                        local_file_path = os.path.join(local_dir, file_name)

                        if not os.path.exists(local_file_path):
                            logger.info('downloading %s from s3..' % file_name)
                            try:
                                bucket.download_file(obj.key, local_file_path)
                            except:
                                logger.error(f'Could not download file from s3: {obj.key}')
                                exit()

                # process downloaded files
                files = [f for f in os.listdir(local_dir) if os.path.isfile(os.path.join(local_dir, f))]
                for f in files:
                    local_file_path = os.path.join(local_dir, f)

                    # parse text file
                    parsed_data = {}
                    with open(local_file_path, 'r') as infile:
                        file_info = f.split('_')
                        mode = file_info[1].replace('.txt', '')
                        if mode == 'Cooling':
                            dd = 'cdd'
                        else:
                            dd == 'hdd'
                        
                        # read file
                        lines = infile.readlines()

                        # skip header information and regional totals
                        data_lines = lines[15:66]
                        month = datetime.strptime(file_info[0], '%b %Y').month

                        for line in data_lines:
                            if line.strip():
                                # state names in all caps, may include one space, e.g. 'NEW YORK'
                                # names separated by values by at least one space
                                match = re.match(r"^(\s[A-Z]+(?:\s?[A-Z]+)*)(?:\s{1,})(.*)$", line)
                                if match:
                                    state_name = match.group(1).strip()
                                    values = match.group(2).split() # all values, we only want first
                                    parsed_data[(state_name, dd)] = values[0]

                    all_data[(y, month)].update(parsed_data)

            df = pd.DataFrame.from_dict(all_data, orient='index')
            df.index.set_names(['year', 'month'], inplace=True)

            logger.info(f'Saving processed data to {self.processed_dir}/{self.processed_filename}')
            df.to_csv(os.path.join(self.processed_dir, self.processed_filename))
            
            self.data = df
