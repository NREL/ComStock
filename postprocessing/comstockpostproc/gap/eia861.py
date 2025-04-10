import os
import json
import boto3
import logging
import botocore
import pandas as pd
from comstockpostproc.naming_mixin import NamingMixin
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

TYPES = ['Annual', 'Monthly', 'Short']
SEGMENTS = ['Commercial', 'Residential', 'Industrial', 'Transportation', 'Total']
MEASURES = ['Revenues', 'Sales', 'Customers']

class EIA861(NamingMixin, S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', type='Annual', year=2018, reload_from_csv=True, segment='All', measure='All'):
        """
        A class to load and process EIA 861 Annual and Monthly electricity sales data reported from EIA Form 861
        Args:
            truth_data_version (string): The version of EIA truth data. 'v01'
            type (String): one of 'Annual', 'Monthly', 'Short', or 'Meters'. Default 'Annual'
            year (Int or String): The reporting year. Ignored if freq='Annual' (defaults to 2018).
                If freq='Monthly', available years are 2013-2023 or 'All' to receive all.
            reload_from_csv (Bool): reload from processed data if available
            segment (List, String): any of ['Commercial', 'Residential', 'Industrial', 'Transportation', 'Total'], or 'All'
            measure (List, String): any of ['Revenues', 'Sales', 'Customers'], or 'All'
        """
        # initialize members
        self.truth_data_version = truth_data_version
        self.type = type
        self.year = year
        self.reload_from_csv = reload_from_csv
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')

        # process input choices
        segment_str = segment
        if segment == 'All':
            self.segment = SEGMENTS
        elif isinstance(segment, str) & (segment in SEGMENTS):
            self.segment = [segment]
        elif isinstance(segment, list) & all(string in SEGMENTS for string in segment):
            self.segment = segment
            segment_str = '_'.join(segment)
        else:
            logger.error(f"Segment input should be 'All' or one of {SEGMENTS}. Received: {segment}.")
            exit()

        measure_str = measure
        if measure == 'All':
            self.measure = MEASURES
        elif isinstance(measure, str) & (measure in MEASURES):
            self.measure = [measure]
        elif isinstance(measure, list) & all(string in MEASURES for string in measure):
            self.measure = measure
            measure_str = '_'.join(measure)
        else:
            logger.error(f"Measure input should be 'All' or any of {MEASURES}. Received: {measure}.")
            exit()

        self.processed_filename = f'eia861_{self.type}_{self.year}_{segment_str}_{measure_str}.csv'

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        # make directories
        for p in [self.truth_data_dir, self.processed_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)
        
        # get data, either by loading pre-processed csv or downloading and processing truth data
        if self.reload_from_csv:
            logger.info('Reloading data from CSV')
            processed_path = os.path.join(self.processed_dir, self.processed_filename)
            if os.path.exists(processed_path):
                self.data = pd.read_csv(processed_path, index_col=0)
            else:
                logger.warning(f'No processed data found for {self.processed_filename}. Processing from truth data.')
                self.load_truth_data()
        else:
            self.load_truth_data()

    def load_truth_data(self):
        if self.type == 'Annual':
            truth_data_filename = f'Sales_Ult_Cust_{self.year}.xlsx'
            s3_file_path =f'truth_data/{self.truth_data_version}/EIA/EIA Form 861/{self.year}/{truth_data_filename}'
            self.download_truth_data_file(s3_file_path)
            self.data = self.process_annual_data(os.path.join(self.truth_data_dir, truth_data_filename))

        elif self.type == 'Monthly':
            if self.year == 'All':
                for year, truth_data_filename in FILE_DICT.items():
                    s3_file_path = f'truth_data/{self.truth_data_version}/EIA/EIA Form 861/{year}/{truth_data_filename}'
                    self.download_truth_data_file(s3_file_path)
            else:
                s3_file_path = f'truth_data/{self.truth_data_version}/EIA/EIA Form 861/{self.year}/{FILE_DICT[self.year]}'
                self.download_truth_data_file(s3_file_path)
            self.data = self.process_monthly_data()

        elif self.type == 'Short':
            truth_data_filename = f'Short_Form_{self.year}.xlsx'  
            s3_file_path = f'truth_data/{self.truth_data_version}/EIA/EIA Form 861/{self.year}/{truth_data_filename}'
            self.download_truth_data_file(s3_file_path)
            self.data = self.process_short_data(os.path.join(self.truth_data_dir, truth_data_filename))

        elif self.type == 'Meters':
            truth_data_filename = f'Advanced_Meters_{self.year}.xlsx'
            s3_file_path = f'truth_data/{self.truth_data_version}/EIA/EIA Form 861/{self.year}/{truth_data_filename}'
            self.download_truth_data_file(s3_file_path)
            self.data = self.process_meters_data(os.path.join(self.truth_data_dir, truth_data_filename))
        else:
            logger.error(f'Type argument value {self.type} not supported')
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
        logger.info('Loading EIA 861 Annual Sales to Ultimate Consumers data')
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
        
        segment_cols = [col for col in data_cols if any(seg.upper() in col for seg in self.segment)]
        data_cols = segment_cols
            
        measure_cols = [col for col in data_cols if any(part in col for part in self.measure)]
        data_cols = measure_cols

        df = df[desc_cols + data_cols]
        df[data_cols] = df[data_cols].fillna(0.0)

        df = df.astype({'Utility Number': int})

        df.to_csv(os.path.join(self.processed_dir, self.processed_filename))

        return df
    
    def process_monthly_data(self):
        logger.info('Loading EIA 861 Monthly Sales data')

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
                data_cols = [col for col in numeric_cols if any(seg.upper() in col for seg in self.segment)]
            
            if self.measure != 'All':
                data_cols = [col for col in data_cols if any(part in col for part in self.measure)]
            
            totals = totals[['Year', 'Month', 'State'] + data_cols]
            totals[data_cols] = totals[data_cols].fillna(0.0)

            totals.reset_index(drop=True, inplace=True)

            df = pd.concat([df, totals], axis=0)
            
        df.to_csv(os.path.join(self.processed_dir, self.processed_filename))

        return df
    
    def process_short_data(self, truth_data_path):
        logger.info('Loading EIA 861 Short Form data')
        df = pd.read_excel(truth_data_path, sheet_name='861S', na_values=['.'])
        df.dropna(subset='Utility Number', inplace=True)

        df = df.astype({'Utility Number': int})

        df.to_csv(os.path.join(self.processed_dir, self.processed_filename))
        
        return df

    def process_meters_data(self, truth_data_path):
        logger.info('Loading EIA 861 Advanced Meters data')
        df = pd.read_excel(truth_data_path, sheet_name='states', header=[0,1], na_values=['.'])

        def rename_meter_cols(df):
            new_cols = []
            for value in df.columns.values:
                if any('Utility Characteristics' in str for str in value):
                    new_cols.append(value[1])
                else:
                    new_cols.append(f'{value[0]}_{value[1]}')
            df.columns = new_cols
        
        rename_meter_cols(df)
        df = df.dropna(subset='Utility Number')
        df = df.astype({'Utility Number': int})
        
        return df

        

        