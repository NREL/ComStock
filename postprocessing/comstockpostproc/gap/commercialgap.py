import os
import boto3
import logging
import botocore
import pandas as pd
from comstockpostproc.gap.eia930 import EIA930
from comstockpostproc.gap.ba_geography import BAGeography
from comstockpostproc.gap.comprofile import CommercialProfile
from comstockpostproc.gap.resprofile import ResidentialProfile
from comstockpostproc.gap.indprofile import IndustrialProfile
from comstockpostproc.gap.gap_plotting_mixin import GapPlottingMixin

# Create logger for AWS queries
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CommercialGap(GapPlottingMixin):
    def __init__(self, 
                 truth_data_version='v01', 
                 reload_from_saved=True, 
                 resstock_version='2024_amy2018_release_2', 
                 comstock_version='2024_amy2018_release_1',
                 basis_lrd_name='First Energy PA',
                 ):
        """
        A class to calculate Commercial Gap Model
        """

        self.truth_data_version = truth_data_version
        self.reload_from_saved = reload_from_saved
        self.resstock_version = resstock_version
        self.comstock_version = comstock_version
        self.basis_lrd_name = basis_lrd_name

        self.data = self.commercial_electric_gap_by_county()

    def commercial_gap_by_ba(self):
        """
        EIA930 demand by BA - (ResStock Adjusted by BA + Industrial Estimated by BA + ComStock by BA) = Commercial Gap by BA
        """

        # Load processed hourly BA demand/load profiles
        total_ba_profiles = EIA930().data
        com_ba_profiles = CommercialProfile(comstock_version=self.comstock_version).data
        res_ba_profiles = ResidentialProfile(resstock_version=self.resstock_version).data
        ind_ba_profiles = IndustrialProfile(basis_lrd_name=self.basis_lrd_name).data

        # drop cols not in total_ba_profiles
        res_cols_to_drop = [col for col in res_ba_profiles.columns if col not in total_ba_profiles.columns]
        if res_cols_to_drop:
            logger.info(f"Dropping {','.join(res_cols_to_drop)} columns from Residential profiles.")
            res_ba_profiles.drop(res_cols_to_drop, axis=1, inplace=True)

        ind_cols_to_drop = [col for col in ind_ba_profiles.columns if col not in total_ba_profiles.columns]
        if ind_cols_to_drop:
            logger.info(f"Dropping {','.join(ind_cols_to_drop)} columns from Industrial profiles.")
            ind_ba_profiles.drop(ind_cols_to_drop, axis=1, inplace=True)

        com_cols_to_drop = [col for col in com_ba_profiles.columns if col not in total_ba_profiles.columns]
        if com_cols_to_drop:
            logger.info(f"Dropping {','.join(com_cols_to_drop)} columns from Commercial profiles.")
            com_ba_profiles.drop(com_cols_to_drop, axis=1, inplace=True)
        
        gap_ba_profiles = total_ba_profiles.sub(res_ba_profiles + com_ba_profiles + ind_ba_profiles)

        return gap_ba_profiles

    def commercial_electric_gap_by_county(self):
        """
        Allocate Total Commercial Gap profiles to Counties by Structures areas
        """
        # load BA Areas, sum by BA and County
        ba_tract_areas = BAGeography().balancing_authority_bldg_areas_data()
        ba_tract_areas = ba_tract_areas.loc[:,'All Commercial'].to_frame()
        ba_tract_areas['county_fips'] = ba_tract_areas.index.get_level_values('CENSUSCODE').str[:5]
        ba_tract_areas = ba_tract_areas.set_index('county_fips', append=True)
        ba_county_areas = ba_tract_areas.groupby(['BA Code', 'county_fips']).sum()

        ba_totals = ba_county_areas.groupby('BA Code')['All Commercial'].sum().to_frame()

        ba_county_areas['ba_area_frac'] = ba_county_areas.divide(ba_totals, level=0)

        gap_ba_profiles = self.commercial_gap_by_ba()

        bas_to_drop = [ba for ba in ba_county_areas.index.get_level_values('BA Code').unique() if ba not in gap_ba_profiles.columns]
        logger.info(f"Dropping {', '.join(bas_to_drop)} from BA county areas")
        ba_county_areas.drop(bas_to_drop, level='BA Code', inplace=True)

        def census_id_to_gisjoin(id):
            state = str(id)[:2]
            county = str(id)[2:]
            return f'G{state}0{county}0'
        
        # remake index with county gisjoins
        ba_county_areas.index = pd.MultiIndex.from_arrays(
            [
                ba_county_areas.index.get_level_values('BA Code'),
                ba_county_areas.index.get_level_values('county_fips').map(lambda x: census_id_to_gisjoin(x))
            ],
            names= [
                'BA Code',
                'county_gisjoin'
            ]
        )

        ba_county_gap_profiles_data = {}
        for idx, row in ba_county_areas.iterrows():
            ba_county_gap_profiles_data[idx] = gap_ba_profiles[idx[0]].mul(row['ba_area_frac'])
        
        ba_county_gap_profiles = pd.DataFrame(ba_county_gap_profiles_data)
        # print(ba_county_gap_profiles)
        
        county_gap_profiles = ba_county_gap_profiles.T.groupby(level=1).sum().T

        # convert to kWh
        county_gap_profiles = county_gap_profiles * 1e3

        return county_gap_profiles


    def commercial_gas_gap_by_state(self):
        """
        """

        # TODO
        return None