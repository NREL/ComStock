import boto3
import botocore
from glob import glob
import json
import logging
import numpy as np
import os
import pandas as pd

from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.units_mixin import UnitsMixin
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

logger = logging.getLogger(__name__)

class Apportion(NamingMixin, UnitsMixin, S3UtilitiesMixin):
    def __init__(self, stock_estimation_version, truth_data_version, bootstrap_coefficient=3):
        """
        A class to apportion the sampled data to the known set of buildings in the U.S.
        Args:

            stock_estimation_version (str): The stock estimation dataset to use for apportionment. This
            is produced through the StockE process and underlies the distributions represented in the TSVs.
            truth_data_version (str): The version/location to retrieve truth/starting data. Truth data
            may change for certain data sources over time, although unlikely for CBECS.
        """

        # Initialize members
        logger.info('Initializing Apportion class')
        self.stock_estimation_version = stock_estimation_version
        self.truth_data_version = truth_data_version
        self.bootstrap_coefficient = bootstrap_coefficient
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.dataset_name = f'Stock Estimation {self.stock_estimation_version}'
        self.truth_data_dir = os.path.join(current_dir, '..', 'truth_data', self.truth_data_version)
        self.resource_dir = os.path.join(current_dir, 'resources')
        self.output_dir = os.path.join(current_dir, '..', 'output', self.dataset_name)
        self.data_file_name = f'{self.stock_estimation_version}_building_estimate.parquet'
        self.hvac_size_bins_name = f'{self.stock_estimation_version}_hvac_system_size_bin.tsv'
        self.tract_list_name = f'{self.stock_estimation_version}_tract_list.csv'
        self.sampling_regions_name = 'sampling_regions_v1.json'
        self.ca_cz_tract_2010_name = 'cec_cz_by_tract_2010_lkup.json'
        self.ca_cz_tract_2020_name = 'cec_cz_by_tract_2020_lkup.json'
        self.hvac_system_type_name = 'hvac_system_type.tsv'
        self.space_heating_fuel_type_name = 'heating_fuel.tsv'
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))
        logger.info(f'Creating {self.dataset_name}')
        
        # Algorithmic specific parameters
        self.samples_per_model = 3
        self.sampling_breaks = ['sampling_region', 'prototype', 'floor_area_category']


        # Make directories
        for p in [self.truth_data_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        # Load and transform truth data
        self.download_data()
        self.load_data()
        self.infer_tracts()
        self.add_sampling_regions()
        self.add_sqft_bins()
        self.normalize_building_type_values()
        self.upsample_hvac_system_fuel_types()

        logger.info('Finished processing Apportion class truth data')
        logger.debug('\nDesired Truth Data columns after adding all data')
        for c in self.data.columns:
            logger.debug(c)

    BUILDING_TYPE_NAME_MAPPER={
        'full_service_restaurant': 'FullServiceRestaurant',
        'small_office': 'SmallOffice',
        'warehouse': 'Warehouse',
        'strip_mall': 'RetailStripmall',
        'small_hotel': 'SmallHotel',
        'retail': 'RetailStandalone',
        'quick_service_restaurant': 'QuickServiceRestaurant',
        'outpatient': 'Outpatient',
        'medium_office': 'MediumOffice',
        'large_office': 'LargeOffice',
        'large_hotel': 'LargeHotel',
        'hospital': 'Hospital',
        'primary_school': 'PrimarySchool',
        'secondary_school': 'SecondarySchool'
    }

    CEN_DIV_LKUP={
        'G090': 'New England', 'G230': 'New England', 'G250': 'New England', 'G330': 'New England',
        'G440': 'New England', 'G500': 'New England', 'G340': 'Middle Atlantic', 'G360': 'Middle Atlantic',
        'G420': 'Middle Atlantic', 'G180': 'East North Central', 'G170': 'East North Central',
        'G260': 'East North Central', 'G390': 'East North Central', 'G550': 'East North Central',
        'G190': 'West North Central', 'G200': 'West North Central', 'G270': 'West North Central',
        'G290': 'West North Central', 'G310': 'West North Central', 'G380': 'West North Central',
        'G460': 'West North Central', 'G100': 'South Atlantic', 'G110': 'South Atlantic', 'G120': 'South Atlantic',
        'G130': 'South Atlantic', 'G240': 'South Atlantic', 'G370': 'South Atlantic', 'G450': 'South Atlantic',
        'G510': 'South Atlantic', 'G540': 'South Atlantic', 'G010': 'East South Central', 'G210': 'East South Central',
        'G280': 'East South Central', 'G470': 'East South Central', 'G050': 'West South Central',
        'G220': 'West South Central', 'G400': 'West South Central', 'G480': 'West South Central', 'G040': 'Mountain',
        'G080': 'Mountain', 'G160': 'Mountain', 'G350': 'Mountain', 'G300': 'Mountain', 'G490': 'Mountain',
        'G320': 'Mountain', 'G560': 'Mountain', 'G020': 'Pacific', 'G060': 'Pacific', 'G150': 'Pacific',
        'G410': 'Pacific', 'G530': 'Pacific'
    }

    def download_data(self):
        
        logger.info('Downloading data required for Apportionment class')

        # Expected buildings estimate from StockE V3 analysis
        file_path = os.path.join(self.truth_data_dir, self.data_file_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.data_file_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')    

        # HVAC system size cuttof bins associated with the TSV files to define size bin levels in the building estimate
        file_path = os.path.join(self.truth_data_dir, self.hvac_size_bins_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.hvac_size_bins_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, '\t')    

        # Mapping of all allowable trackts within a given county, many tracts per county
        file_path = os.path.join(self.truth_data_dir, self.tract_list_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.tract_list_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')    

        # Mapping of all non-CA counties to sampling regions
        file_path = os.path.join(self.truth_data_dir, self.sampling_regions_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.sampling_regions_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')    

        # Mapping of all 2010 CA census tracts to CEC climate zones
        file_path = os.path.join(self.truth_data_dir, self.ca_cz_tract_2010_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.ca_cz_tract_2010_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')    

        # Mapping of all 2020 CA census tracts to CEC climate zones
        file_path = os.path.join(self.truth_data_dir, self.ca_cz_tract_2020_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.ca_cz_tract_2020_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')    

        # Probabilities of hvac system type as a function of heating fuel type, census division and building type
        file_path = os.path.join(self.truth_data_dir, self.hvac_system_type_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.hvac_system_type_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, '\t')    

        # Probabilities of heating fuel type as a function of county and building type
        file_path = os.path.join(self.truth_data_dir, self.space_heating_fuel_type_name)
        if not os.path.exists(file_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/StockE/{self.space_heating_fuel_type_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, '\t')    

    def load_data(self):
        # Load raw microdata and codebook and decode numeric keys to strings using codebook
        logger.info('Loading data required for Apportionment class')

        # Load building stock estimate from StockE V3
        file_path = os.path.join(self.truth_data_dir, self.data_file_name)
        self.data = pd.read_parquet(file_path)

        # Load size bin mapping using the hvac_system_size_bin TSV file
        file_path = os.path.join(self.truth_data_dir, self.hvac_size_bins_name)
        self.hvac_size_bin_df = pd.read_csv(file_path, low_memory=False, sep='\t')

        # Load tract list for tract infrence
        file_path = os.path.join(self.truth_data_dir, self.tract_list_name)
        self.tract_list = pd.read_csv(file_path, low_memory=False)

        # Load non-CA sampling region lookup
        file_path = os.path.join(self.truth_data_dir, self.sampling_regions_name)
        with open(file_path, 'r') as rfobj:
            self.sampling_region_lkup = json.load(rfobj)

        # Load CA 2010 tract to CEC climate zone lookup
        file_path = os.path.join(self.truth_data_dir, self.ca_cz_tract_2010_name)
        with open(file_path, 'r') as rfobj:
            self.ca_cz_2010_lkup = json.load(rfobj)

        # Load CA 2020 tract to CEC climate zone lookup
        file_path = os.path.join(self.truth_data_dir, self.ca_cz_tract_2020_name)
        with open(file_path, 'r') as rfobj:
            self.ca_cz_2020_lkup = json.load(rfobj)

        # Load probabilities of hvac system type
        file_path = os.path.join(self.truth_data_dir, self.hvac_system_type_name)
        self.hvac_system_type_prob = pd.read_csv(file_path, low_memory=False, sep='\t')

        # Load probabilities of space heating fuel type
        file_path = os.path.join(self.truth_data_dir, self.space_heating_fuel_type_name)
        self.heating_fuel_type_prob = pd.read_csv(file_path, low_memory=False, sep='\t')

    @staticmethod
    def _generate_level1_distributions(full_tracts):
        
        # To be used for assignment level 1.

        # Create distribution of buildings by building_type, county, and tract.
        building_tract_distributions = full_tracts[['building_type', 'county', 'last6']]\
            .groupby(['building_type', 'county', 'last6'])\
            .value_counts()\
            .to_frame()\
            .rename(columns={'count':'building_tract_count'})\
            .reset_index()

        # Create distribution of buildings by prototype and county.
        # This dataframe is used to normalize the building_tract_distributions dataframe.
        building_county_distributions = full_tracts[['building_type', 'county']]\
            .groupby(['building_type', 'county'])\
            .value_counts()\
            .to_frame()\
            .rename(columns={'count':'building_county_count'})\
            .reset_index()

        # Normalize the building_tract_distributions. Calculate a cumulative sum of the probabilities
        # for each prototype-county combination. 
        building_tract_distributions = building_tract_distributions.merge(
            building_county_distributions, on=['building_type', 'county']
        )
        building_tract_distributions['fraction'] = \
            building_tract_distributions['building_tract_count'] / building_tract_distributions['building_county_count']
        building_tract_distributions['cumsum_fraction'] = building_tract_distributions.groupby(
            ['building_type', 'county']
        )['fraction'].cumsum()
        building_tract_distributions = building_tract_distributions.sort_values(['cumsum_fraction'])
        building_tract_distributions = building_tract_distributions[
            ['building_type', 'county', 'last6', 'cumsum_fraction']
        ]

        return building_tract_distributions

    @staticmethod
    def _generate_level2_distributions(full_tracts):
        
        # To be used for assignment level 2.

        # Create distribution  of buildings by county, and tract.
        tract_distributions = full_tracts[['county', 'last6']]\
            .groupby(['county', 'last6'])\
            .value_counts()\
            .to_frame()\
            .rename(columns={'count':'tract_count'})\
            .reset_index()

        # Create distribution of buildings by county.
        # This dataframe is used to normalize the tract_distributions dataframe.
        county_distributions = full_tracts[['county']]\
            .groupby(['county'])\
            .value_counts()\
            .to_frame()\
            .rename(columns={'count':'county_count'})\
            .reset_index()

        # Normalize the tract_distributions. Calculate a cumulative sum of the probabilities
        # for each county. 
        tract_distributions = tract_distributions.merge(county_distributions, on=['county'])
        tract_distributions['fraction'] = tract_distributions['tract_count']/tract_distributions['county_count']
        tract_distributions['cumsum_fraction'] = tract_distributions.groupby(['county'])['fraction'].cumsum()
        tract_distributions = tract_distributions.sort_values(['cumsum_fraction'])
        tract_distributions = tract_distributions[['county', 'last6', 'cumsum_fraction']]
        
        return tract_distributions

    @staticmethod
    def _generate_level3_distributions(folder_path, use_raw_data=False):
        
        # To be used for assignment level 3.

        # Generate a list of tracts in each county. 
        # This is to be used as a last fallback case for assigning tracts.
        # For example, if an unassigned building belongs in a county that has only that one building
        # then we cannot calculate distributions to assign a tract to it. Therefore we use this data to
        # assign it at random to any available tract within the county.

        # This data was directly downloaded from https://www2.census.gov/geo/maps/dc10map/tract/
        if use_raw_data:
            file_list = glob(folder_path + "*/*/*.txt")
            tract_list = pd.DataFrame(pd.read_csv(file_list[0], delimiter=';', dtype={'CODE':str}))
            for i in range(1,len(file_list)):
                if 'SP_' in file_list[i]:
                    continue
                data = pd.read_csv(file_list[i], delimiter=';', dtype={'CODE':str})
                df = pd.DataFrame(data)
                tract_list = pd.concat([tract_list,df])

            tract_list['county'] = 'G' + tract_list['CODE'].str[0:2] + '0' + tract_list['CODE'].str[2:5] + '0'
            tract_list['tract'] = tract_list['county'] + tract_list['CODE'].str[5:]

            tract_list[['county', 'tract']].to_csv('tract_list.csv', index=False)
        else:
            tract_list = pd.read_csv(folder_path+"tract_list.csv") # This is a preprocessed file.
            
        tract_list['last6'] = tract_list.tract.str[-6:]
        tract_list = tract_list[['county', 'tract', 'last6']]
        tract_list['dummy'] = 1

        tract_list['counter'] = tract_list.groupby('county')['dummy'].cumsum()
        tract_list['number_of_tracts'] = tract_list['county'] \
                                        .map(tract_list.groupby('county')['counter'].agg('max'))
        tract_list['cumsum_fraction'] = tract_list['counter']/tract_list['number_of_tracts']
        tract_list = tract_list.sort_values('cumsum_fraction')
        tract_list = tract_list.drop(columns=['dummy', 'tract', 'counter', 'number_of_tracts'])
        
        return tract_list

    @staticmethod
    def _assign_tracts(null_tracts, building_tract_distributions, tract_distributions, tract_list):

        # The idea here is that the random number assinged to each row in null_tracts will be matched 
        # to the closest forward value in the cumulative distribution (e.g, building_tract_distributions) 
        # calculated above. The other keys (building_type, county) are matched exactly. Same idea for 
        # level 2 and 3.

        #Create a column with an indicator with the type of assignment, 
        # 0 - Assignment level 0: Original assignment from raw data. No re-assignemnt.
        # 1 - Assignment level 1: through building type and county distributions.
        # 2 - Assignment level 2: through county-only distributions.
        # 3 - Assignment level 3: through tract list (tract list from US Census).
        # 4 - Assignment level 4: Unassigned (likely bad data).

        # Join the fallback level 1 option
        null_tracts = pd.merge_asof(
            null_tracts, 
            building_tract_distributions.rename(columns={'last6': 'last6_l1', 'cumsum_fraction': 'cumsum_fraction_l1'}), 
            by=['building_type', 'county'], 
            direction="forward", 
            left_on="random_values", 
            right_on="cumsum_fraction_l1"
        )

        # Join for level 2 option
        null_tracts = pd.merge_asof(
            null_tracts, 
            tract_distributions.rename(columns={'last6': 'last6_l2', 'cumsum_fraction': 'cumsum_fraction_l2'}), 
            by=['county'], 
            direction="forward", 
            left_on="random_values", 
            right_on="cumsum_fraction_l2"
        )

        # Join for level 3 option
        null_tracts = pd.merge_asof(
            null_tracts, 
            tract_list.rename(columns={'last6': 'last6_l3', 'cumsum_fraction': 'cumsum_fraction_l3'}), 
            by=['county'], 
            direction="forward", 
            left_on="random_values", 
            right_on="cumsum_fraction_l3"
        )
        
        conditions = [
            null_tracts['last6_l1'].notnull(), null_tracts['last6_l2'].notnull(), null_tracts['last6_l3'].notnull()
        ] 
        choices = [
            null_tracts['county'] + null_tracts['last6_l1'], null_tracts['county'] + null_tracts['last6_l2'],
            null_tracts['county'] + null_tracts['last6_l3']
        ]
        level = [1, 2, 3]

        null_tracts['tract'] = np.select(conditions, choices, default=np.nan)

        null_tracts['tract_assignment_type'] = np.select(conditions, level, default=4)

        null_tracts = null_tracts.drop([
            'random_values', 'last6_l1', 'cumsum_fraction_l1', 'last6_l2', 'cumsum_fraction_l2', 'last6_l3', 'cumsum_fraction_l3'
        ], axis=1)

        return null_tracts

    def infer_tracts(self):
        # This wraps all other functions to run the tract-level resampling
        if ~any([na_tract in self.data['tract'].unique() for na_tract in [None, np.nan, '999999']]):
            return
        
        # Impose manual checking of a failing expression as that's very much not expected at present...
        logger.info('Apportioning any missing tracts in truth data')
        print('Please confirm that there are unset tracts in the self.data building estimation:')
        breakpoint()

        # Create a dataframe containing only rows with tract!=null.
        # This is to calculate the distributions of buildings in counties by building_type.
        df = self.data.copy(deep=True)
        df['tract'] = np.where(df.tract.str[-6:] == '999999', None, df['tract'])
        full_tracts = df.loc[df['tract'].notnull()]
        full_tracts['last6'] = full_tracts.tract.str[-6:]

        #Distribution for level 1 assignments
        building_tract_distributions = self._generate_level1_distributions(full_tracts)

        #Distribution for level 2 assignments
        tract_distributions = self._generate_level2_distributions(full_tracts)

        # Distribution for level 3 assignments
        # This method is preserved here as it will be used to rebuild the tract_list csv for 2020 census tracts when we upgrade
        # tract_list = self._generate_level3_distributions(folder_path, use_raw_data = False)

        # Create the complement of full_tracts, i.e., a datafram with only null tracts.
        # Assign random values from 0 to 1 to each row. This will be used for assignment to actual tracts.
        # The random values are then sorted because the join will be an "as_of" join that requires left 
        # and right dataframes to be sorted by the join keys.
        null_tracts = df.loc[df['tract'].isnull()]
        null_tracts['random_values'] = np.random.rand(len(null_tracts))
        null_tracts = null_tracts.sort_values(['random_values'])

        null_tracts = self._assign_tracts(null_tracts, building_tract_distributions, tract_distributions, self.tract_list)

        full_tracts = full_tracts.drop(['last6'], axis=1)
        full_tracts['tract_assignment_type'] = 0
        df = pd.concat([null_tracts, full_tracts])

        self.data = df.copy(deep=True)

    def add_sampling_regions(self):
        """Apply sampling regions on a county basis for calculation of distributions.

        :param df: input pandas dataframe where each row is a single building
        :type df: pandas.DataFrame
        :return: an updated dataframe with a 'sampling_region' column that is defined by sampling_region_lkup.json
        :rtype: pandas.DataFrame

        """

        # Check to see if this is needed:
        if 'sampling_region' in list(self.data):
            return

        # Make sure we don't do anything unintended with pointers...
        logger.info('Assigning sampling region ids to truth data')
        df = self.data.copy(deep=True)

        # Calculate the new column on a county basis
        df.loc[:, 'sampling_region'] = df.county.map(self.sampling_region_lkup)

        # Calculate CEC Climate Zones for California using first the 2010 then 2020 census tract lookups
        df.loc[df.state == 'G060', 'cz'] = df.loc[df.state == 'G060', 'tract'].apply(
            lambda x: self.ca_cz_2010_lkup.get(x, self.ca_cz_2020_lkup.get(x, np.nan))
        )

        # Check to see if any of the CA rows don't have a CZ - if so report and error.
        if any(df.loc[df.state == 'G060', 'cz'].isna()):
            print('\nCalifornia CEC Climate Zone mapping failed for the following tracts:')
            print(f'{list(df.loc[df.state == "G060", "tract"][df.loc[df.state == "G060", "cz"].isna()].unique())}')
            raise RuntimeError('Unable to determine all CEC Climate Zones for California tracts.')

        # Finish calculating sampling regions with CA regions
        ca_regions_lkup = {
            'CEC1': 100,
            'CEC2': 100,
            'CEC3': 101,
            'CEC4': 102,
            'CEC5': 102,
            'CEC6': 103,
            'CEC7': 103,
            'CEC8': 104,
            'CEC9': 105,
            'CEC10': 106,
            'CEC11': 107,
            'CEC12': 107,
            'CEC13': 108,
            'CEC14': 109,
            'CEC15': 109,
            'CEC16': 110
        }
        df.loc[df.state == 'G060', 'sampling_region'] = df.loc[df.state == 'G060', 'cz'].map(ca_regions_lkup)

        # Check for nans and if not return
        if any(df.sampling_region.isna()):
            print('\nSampling region calculation resulted in counties with missing regions:')
            print(f'{df.loc[df.sampling_region.isna(), "county"].unique()}')

        df['sampling_region'] = df['sampling_region'].astype(int)
        self.data = df.copy(deep=True)

    def add_sqft_bins(self):
        if 'size_bin' in list(self.data):
            return
        
        raise NotImplementedError('This does not yet exist - if it is needed someone needs to write this...')
    
    def normalize_building_type_values(self):
        """Change the building type names from nice snake_case to nasty UpperCamelCase eww"""

        # Apply mapping
        df = self.data.copy(deep=True)
        df.loc[:, 'building_type'] = df.loc[:, 'building_type'].map(self.BUILDING_TYPE_NAME_MAPPER)

        # If there are any non-mapped values left in building_type alert and throw and error
        leftovers = set(df.building_type.unique()) - set(self.BUILDING_TYPE_NAME_MAPPER.values())
        if len(leftovers) > 0:
            logger.error('Building type values from the building estimate not expected by the building type mapper:')
            logger.error(f'{leftovers}')
            breakpoint()
            raise RuntimeError('Unable to process the specified building type enumerations.')
        
        self.data = df.copy(deep=True)

    def upsample_hvac_system_fuel_types(self):
        """Do a thing"""

        logger.info('Upsampling truth data with fuel type and HVAC system type')
        df = self.data.copy(deep=True)

        # Begin by bootstraping to the desired degree
        df = df.loc[df.index.repeat(self.bootstrap_coefficient), :]

        # Apply the census divion mapper here (helpfully called region) for efficiencies sake
        df.loc[:, 'cen_div'] = df.loc[:, 'state'].map(self.CEN_DIV_LKUP)

        # Load in the heating fuel type proability TSV and process it to merge w/ the truth dataset
        hfdf = self.heating_fuel_type_prob.copy(deep=True)
        fcols = [col.replace('Option=', '') for col in hfdf.columns if 'Option=' in col]
        hfdf.columns = [col.replace('Dependency=', '').replace('Option=', '') for col in hfdf.columns]
        hfdf.loc[:, 'building_type'] = hfdf.loc[:, 'building_type'].map(self.BUILDING_TYPE_NAME_MAPPER)
        df = df.merge(hfdf, left_on=['building_type', 'county'], right_on=['building_type', 'county_id'])

        # Use the merged probabilities to sample in fuel type
        # Note this can be made fuel type enumeration agnostic by looping over fcols but it is very not readable
        df.loc[: , 'ft_rand'] = np.random.rand(df.shape[0])
        df.loc[:, 'heating_fuel'] = 'DistrictHeating'
        df.loc[df.loc[:, 'ft_rand'] >= df.loc[:, 'DistrictHeating'], 'heating_fuel'] = 'Electricity'
        df.loc[df.loc[:, 'ft_rand'] >= df.loc[:, ['DistrictHeating', 'Electricity']].sum(axis=1), 'heating_fuel'] = 'FuelOil'
        df.loc[df.loc[:, 'ft_rand'] >= df.loc[:, ['DistrictHeating', 'Electricity', 'FuelOil']].sum(axis=1), 'heating_fuel'] = 'NaturalGas'
        df.loc[df.loc[:, 'ft_rand'] >= df.loc[:, ['DistrictHeating', 'Electricity', 'FuelOil', 'NaturalGas']].sum(axis=1), 'heating_fuel'] = 'Propane'
        df = df.drop(fcols + ['ft_rand'], axis=1)

        # Load in the hvac system type probability TSV and process it to merge with the truth dataset
        logger.info('Sampling fuel type onto truth data')
        hsdf = self.hvac_system_type_prob.copy(deep=True)
        hcols = [col.replace('Option=', '') for col in hsdf.columns if 'Option=' in col]
        hsdf.columns = [col.replace('Dependency=', '').replace('Option=', '') for col in hsdf.columns]
        hsdf.loc[:, 'building_type'] = hsdf.loc[:, 'building_type'].map(self.BUILDING_TYPE_NAME_MAPPER)
        df = df.merge(hsdf, left_on=['building_type', 'heating_fuel', 'cen_div'], right_on=['building_type', 'heating_fuel', 'census_region'])

        # Use the merged probabilities to sample in fuel type
        # Note this is system type agnostic due to the enumeration county and not readable - refer above for the idea
        # TODO can wenyi find a less dumb way to do this?
        logger.info('Sampling HVAC system type onto truth data')
        df.loc[: , 'hs_rand'] = np.random.rand(df.shape[0])
        df.loc[:, 'system_type'] = hcols[0]
        calced_systems = [hcols[0]]
        for h in hcols[1:]:
            df.loc[df.loc[:, 'hs_rand'] >= df.loc[:, calced_systems].sum(axis=1), 'system_type'] = h
            calced_systems += [h]
        df = df.drop(hcols + ['hs_rand'], axis=1)
        df.loc[:, 'hvac_and_fueltype'] = df.loc[:, 'system_type'] + '_' + df.loc[:, 'heating_fuel']

        self.data = df.copy(deep=True)