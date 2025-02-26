import os
import boto3
import logging
import botocore
import pandas as pd
from buildstock_query import BuildStockQuery
from comstockpostproc.gap.eia861 import EIA861
from comstockpostproc.gap.ba_geography import BAGeography

from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

# Create logger for AWS queries
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CommercialProfile(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', reload_from_saved=True, save_processed=True, comstock_version='2024_amy2018_release_1'):
        """
        A class to query commercial hourly electricity demand profiles from ComStock, allocated to Balaancing Authority. 
        """

        self.truth_data_version = truth_data_version
        self.reload_from_saved = reload_from_saved
        self.save_processed = save_processed
        self.comstock_version = comstock_version
        self.comstock_profiles_filename = f'comstock_{self.comstock_version}_load_by_state.parquet'

        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)

        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')

        # calculate BA profiles
        self.data = self.com_ba_profiles()

    def comstock_elec_hourly(self):
        """
        Queries ComStock for ending-hour total electricity by state
        """
        run = BuildStockQuery(workgroup='eulp',
                              db_name='buildstock_sdr',
                              table_name=(
                                  f'comstock_{self.comstock_version}_metadata_state_vu',
                                  f'comstock_{self.comstock_version}_by_state_vu',
                                  None
                              ),
                              db_schema='comstock_oedi',
                              buildstock_type='comstock',
                              skip_reports=True)

        query = f"""
        select
            case
                when extract(minute from "t2"."timestamp") = 0
                    and extract(second from "t2"."timestamp") = 0
                    then date_trunc('hour', "t2"."timestamp")
                else date_trunc('hour', "t2"."timestamp") + interval '1' hour
            end as "rounded_hour",
            sum("t2"."out.electricity.total.energy_consumption" * "t1"."weight") as "total_electricity",
            "t1"."state" as "state"
        from
            "comstock_{self.comstock_version}_metadata_state_vu" as "t1"
        inner join
            "comstock_{self.comstock_version}_by_state_vu" as "t2"
        on
            "t1"."bldg_id" = "t2"."bldg_id"
        where
            "t1"."upgrade" = 0 and
            "t2"."upgrade" = 0
        group by
            case
                when extract(minute from "t2"."timestamp") = 0
                    and extract(second from "t2"."timestamp") = 0
                    then date_trunc('hour', "t2"."timestamp")
                else date_trunc('hour', "t2"."timestamp") + interval '1' hour
            end,
            "t1"."state"
        order by
            "rounded_hour"
        """

        logger.info('Querying Athena for timeseries ComStock results. This will take a while.')

        df = run.execute(query)

        df.to_parquet(os.path.join(self.truth_data_dir, self.comstock_profiles_filename))

        return df
    
    def comstock_hourly_by_state(self):
        """
        Loads ComStock results from existing truth data file or by querying S3
        """

        local_path = os.path.join(self.truth_data_dir, self.comstock_profiles_filename)
        if os.path.exists(local_path):
            logger.info('Reloading ComStock timestep state profiles from truth data')
            com_load = pd.read_parquet(local_path)
        else:
            com_load = self.comstock_elec_hourly()
        
        com_load.set_index('rounded_hour', inplace=True)

        return com_load
    
    def com_ba_profiles(self):
        """
        Apportions ComStock state profiles to Balancing Authority by dividing state total load by fraction of total commercial building area found in each territory from 
        Structures dataset. This assumes that commercial-coded structure areas are equally proportional to electricity use nationwide (in each state).
        """

        processed_filename = 'com_ba_profiles.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved:
            if os.path.exists(processed_path):
                logger.info('Reloading BA Commercial Hourly Profiles from saved')
                df = pd.read_parquet(processed_path)
                return df
            else:
                logger.info(f'No processed data found for {processed_filename}. Processing from truth data.')
            
        # load comstock profiles
        com_hourly_by_state = self.comstock_hourly_by_state()

        # pivot to one col per state
        com_hourly_by_state = com_hourly_by_state.pivot_table('total_electricity', index='rounded_hour', columns='state', aggfunc='sum')

        # load county to BA mapping
        ba_tract_areas = BAGeography().balancing_authority_bldg_areas_data()
        ba_tract_com_areas = ba_tract_areas.loc[:,'All Commercial'].to_frame()

        # merge tract data to state
        ba_tract_com_areas['state_fips'] = ba_tract_com_areas.index.get_level_values('CENSUSCODE').str[:2]
        ba_tract_com_areas.set_index('state_fips', append=True, inplace=True)
        ba_state_areas = ba_tract_com_areas.groupby(['BA Code', 'state_fips']).sum()

        #  get fips to abbrev map and group BA areas by state abbrev
        state_labels = self.read_delimited_truth_data_file_from_S3(f'truth_data/{self.truth_data_version}/national_state2020.txt', '|')
        state_labels['STATEFP'] = state_labels['STATEFP'].astype(str).str.zfill(2)
        state_labels = state_labels[['STATE', 'STATEFP']].set_index('STATEFP')

        ba_state_areas = ba_state_areas.join(state_labels, on='state_fips')
        ba_state_areas.set_index([ba_state_areas.index.get_level_values(level=0), 'STATE'], inplace=True)
        ba_state_areas = ba_state_areas.reorder_levels(['STATE', 'BA Code'])
        ba_state_areas.sort_index(inplace=True)

        # commercial areas for each BA in each state
        com_ba_areas = ba_state_areas.loc[:, 'All Commercial'].to_frame()

        # total areas by state
        state_com_areas = ba_state_areas.groupby('STATE')['All Commercial'].sum().to_frame()

        # fractions of total state commercial area in each BA
        com_ba_areas['area_frac'] = com_ba_areas.divide(state_com_areas, level=0)

        # multiply state BA fractions by state profiles to get state BA profiles
        com_ba_state_profiles_data = {}
        for idx, row in com_ba_areas.iterrows():
            com_ba_state_profiles_data[idx] = com_hourly_by_state[idx[0]].mul(row['area_frac'])
        
        com_ba_state_profiles = pd.DataFrame(com_ba_state_profiles_data)

        # convert from kWh to MWh
        com_ba_state_profiles = com_ba_state_profiles / 1e3
        
        com_ba_profiles = com_ba_state_profiles.T.groupby(level=1).sum().T

        if self.save_processed:
            com_ba_profiles.to_parquet(processed_path)

        return com_ba_profiles