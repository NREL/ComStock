import os
import json
import boto3
import logging
import botocore
import pandas as pd
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

# Create logger for AWS queries
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

FILE_DICT = {
    2013: 'f8262013.xls',
    2014: 'f8262014.xls',
    2015: 'f8262015.xls',
    2016: 'f8262016.xls',
    2017: 'retail_sales_2017.xlsx',
    2018: 'retail_sales_2018.xlsx',
    2019: 'retail_sales_2019.xlsx',
    2020: 'retail_sales_2020.xlsx',
    2021: 'sales_ult_cust_2021.xlsx',
    2022: 'sales_ult_cust_2022.xlsx',
    2023: 'sales_ult_cust_2023.xlsx'
}

class EIA861(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', freq='Annual', year=2018, reload_from_csv=False, segment='All', measure='All'):
        """
        A class to load and process EIA 861 Annual and Monthly electricity sales data reported from EIA Form 861
        Args:
            truth_data_version (string): The version of EIA truth data. 'v01'
            freq (String): one of 'Annual', 'Monthly'. Default 'Annual'
            year (Int or String): The reporting year. Ignored if freq='Annual' (defaults to 2018). 
                If freq='Monthly', available years are 2013-2023 or 'All' to receive all.
            reload_from_csv (Bool): reload from processed data if available
            segment (String): one of ['Commercial', 'Residential', 'Industrial', 'Transportation', 'Total', 'All']
            measure (String): onr of ['Revenues', 'Sales', 'Customers', 'All']
        
        """
        # initialize members
        self.truth_data_version = truth_data_version
        self.frequency = freq
        self.year = year
        self.reload_from_csv = reload_from_csv
        current_dir = os.path.dirname(os.path.abspath(__file__))
        print(current_dir)
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        print(self.truth_data_dir)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')
        self.segment = segment
        self.measure = measure
        # self.monthly_data = None
        # self.annual_data = None
        self.processed_filename = f'eia861_{self.frequency}_{self.year}_{self.segment}_{self.measure}.csv'

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        # make directories
        for p in [self.truth_data_dir, self.processed_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)
        
        # reload from csv
        if self.reload_from_csv:
            logger.info('Reloading data from CSV')
            processed_path = os.path.join(self.processed_dir, self.processed_filename)
            if os.path.exists(processed_path):
                self.data = pd.read_csv(processed_path)
            else:
                logger.warning(f'No processed data found for {self.processed_filename}. Processing from truth data.')
                self.load_truth_data()
        else:
            self.load_truth_data()

    def download_truth_data(self, truth_data_filename):
        local_path = os.path.join(self.truth_data_dir, truth_data_filename)
        if not os.path.exists(local_path):
            logger.info('Downloading %s from s3...' % truth_data_filename)
            s3_file_path = f'truth_data/{self.truth_data_version}/EIA/EIA Form 861/{self.year}/{truth_data_filename}'
            print(s3_file_path)
            self.s3_client.download_file('eulp', s3_file_path, local_path)

    def load_truth_data(self):
        if self.frequency == 'Annual':
            truth_data_filename = f'Sales_Ult_Cust_{self.year}.xlsx'
            self.download_truth_data(truth_data_filename)
            self.data = self.process_annual_data(os.path.join(self.truth_data_dir, truth_data_filename))

        elif self.frequency == 'Monthly':
            if self.year == 'All':
                for year, filename in FILE_DICT.items():
                    self.download_truth_data(truth_data_filename)
            else:
                truth_data_filename = FILE_DICT[self.year]
                self.download_truth_data(truth_data_filename)
            self.data = self.process_monthly_data()
        else:
            logger.error(f'Frequency argument value {self.frequency} not supported')
            exit()
        
    def rename_columns(self, df):
        new_cols = []
        for value in df.columns.values:
            if any('Unnamed' in str for str in value):
                new_cols.append(value[2].split('\n')[0])
            else:
                unit = value[2].replace('Megawatthours', 'MWh').replace('Thousand Dollars', 'kUSD').replace('Count', 'ct')
                new_cols.append(f'{value[0]}_{value[1]}_{unit}')
        df.columns = new_cols

    def process_annual_data(self, truth_data_path):
        df = pd.read_excel(truth_data_path, sheet_name='States', header=[0,1,2], na_values=['.'])

        # rename columns
        self.rename_columns(df)

        # drop note row
        df = df[df['Data Year'] == self.year]

        # df.fillna(0, inplace=True)

        desc_cols = [
            'Data Year',
            'Utility Number',
            'Utility Name',
            'Part',
            'Service Type',
            'Data Type',
            'State',
            'Ownership',
            'BA Code'
        ]
        
        # filter according to input parameters
        data_cols = list(set(df.columns) - set(desc_cols))
        print(data_cols)
        if self.segment != 'All':
            segment_cols = [col for col in data_cols if self.segment.upper() in col]
            data_cols = segment_cols
            
        if self.measure != 'All':
            measure_cols = [col for col in data_cols if self.measure in col]
            data_cols = measure_cols

        df = df[desc_cols + data_cols]
        df[data_cols] = df[data_cols].fillna(0.0)

        return df
    
    def process_monthly_data(self):
        if self.year == 'All':
            file_dict = FILE_DICT
        else:
            file_dict = {self.year: FILE_DICT[self.year]}
        
        df = pd.DataFrame()

        for year, filename in file_dict.items():
            print(filename)
            if year == 2013:
                sheet_name = 'Retail Sales - States'
            else: sheet_name = 'Sales Ultimate Cust. -States'

            monthly_df = pd.read_excel(os.path.join(self.truth_data_dir, filename), sheet_name=sheet_name, header=[0,1,2])

            self.rename_columns(monthly_df)

            if year in [2022, 2023]:
                tot_name = 'State Total'
            else: tot_name = 'Total EPM'
        
            totals = monthly_df.loc[monthly_df['Utility Name'] == tot_name].copy()

            numeric_cols = [col for col in totals.columns if any(ext in col for ext in ['Revenue', 'Sales', 'Customers'])]
            for col in numeric_cols:
                totals[col] = pd.to_numeric(totals[col])

            # filter according to input parameters
            data_cols = numeric_cols
            if self.segment != 'All':
                data_cols = [col for col in numeric_cols if self.segment.upper() in col]
            
            if self.measure != 'All':
                data_cols = [col for col in numeric_cols if self.measure in col]
            
            totals = totals[['Year', 'Month', 'Utility Name'] + data_cols]
            totals[data_cols] = totals[data_cols].fillna(0.0)

            totals.reset_index(drop=True, inplace=True)

            df = pd.concat([df, totals], axis=0)
        
        return df