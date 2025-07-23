import os
import boto3
import logging
import botocore
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.cbecs import CBECS
from comstockpostproc.units_mixin import UnitsMixin
from comstockpostproc.gap.eia861 import EIA861
from comstockpostproc.gap.eia930 import EIA930
from comstockpostproc.gap.ba_geography import BAGeography
from comstockpostproc.gap.comprofile import CommercialProfile
from comstockpostproc.gap.resprofile import ResidentialProfile
from comstockpostproc.gap.indprofile import IndustrialProfile
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin
from comstockpostproc.gap.gap_plotting_mixin import GapPlottingMixin

# Create logger for AWS queries
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CommercialGap(S3UtilitiesMixin, UnitsMixin, NamingMixin, GapPlottingMixin):
    def __init__(self, 
                 truth_data_version='v01', 
                 reload_from_saved=True, 
                 resstock_version='2024_amy2018_release_2', 
                 comstock_version='2024_amy2018_release_1',
                 basis_lrd_name='First Energy PA',
                 res_allocation_method='EIA',
                 com_allocation_method='EIA',
                 gap_allocation_method='CBECS',
                 trim_negative_gap=True
                 ):
        """
        A class to calculate Commercial Gap Model

        Args:
            truth_data_version (String): The version of truth data. 'v01'
            reload_from_saved (Bool): reload from processed data if available
            resstock_version (String): version of ResStock to query
            comstock_version (String): version of ComStock to query
            basis_lrd_name (String): name of LRD utility to use as basis for Industrial profile
            res_allocation_method (String): method to allocate residential demand profiles to BA. 
            com_allocation_method (String): method to allocate commercial demand profiles to BA.
            gap_allocation_method (String): one of ['CBECS', 'BAGeo']. The method used to allocate BA-level gap profiles to County-level. 
                'BAGeo' allocates gap demand to county by the fraction of commercial building area in each county and BA as determined by the BA geography mapping 
                    (i.e. combining Electric Retail Service Territories shapefiles by BA, de-overlapping them, then overlaying Structures data and summing total 
                    Commercial structures areas contained in each shape).
                'CBECS' allocates gap demand by using CBECS reported electricity EUI by building type and climate division, mapping the CBECS building types to the 
                    types found in the StockE dataset, and computing the total annual electricity consumption of the StockE buildings. StockE buildings are assigned 
                    to a BA using the ComStock tract to utility_id map, and matching utility_id to BA from EIA861 Sales, Short, and Advanced Metering forms. The 
                    total estimated annual energy can then be summed by county and BA, and the fraction of the total BA consumption determined for each county it serves.
            trim_negative_gap (Bool): whether to allow negative gap values. If True, negative values are set to 0. If False, negative values are kept as is.
        """

        self.truth_data_version = truth_data_version
        self.reload_from_saved = reload_from_saved
        self.resstock_version = resstock_version
        self.comstock_version = comstock_version
        self.basis_lrd_name = basis_lrd_name
        self.res_allocation_method = res_allocation_method
        self.com_allocation_method = com_allocation_method
        self.gap_allocation_method = gap_allocation_method
        self.trim_negative_gap = trim_negative_gap

        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.output_dir = os.path.join(current_dir, 'output', 'commercial_gap_model')
        self.plot_dir = os.path.join(self.output_dir, 'comparison_plots')
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        
        for p in [self.truth_data_dir, self.processed_dir, self.output_dir, self.plot_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        self.data = self.commercial_electric_gap_by_county()

        # self.save_gap_profiles()

    def save_gap_profiles(self):
        """
        Save the gap profiles to the output directory
        """
        # create output directory for each column
        for col in self.data.columns:
            col_dir = os.path.join(self.output_dir, 'by_county', 'upgrade=0', f'county={col}')
            if not os.path.exists(col_dir):
                os.makedirs(col_dir)

            logger.info(f'Saving gap profile for {col} to {col_dir}')
            # save each column as a csv file
            col_data = self.data[[col]].copy()
            col_data['upgrade'] = 0
            col_data['in.county'] = col
            col_data.rename(columns={col: 'out.electricity.total.energy_consumption..kwh'}, inplace=True)
            col_data.to_csv(os.path.join(col_dir, f'up0-{col}-gap.csv'), index=False)

    def commercial_gap_by_ba(self):
        """
        EIA930 demand by BA - (ResStock Adjusted by BA + Industrial Estimated by BA + ComStock by BA) = Commercial Gap by BA
        """

        # Load processed hourly BA demand/load profiles
        self.total_ba_profiles = EIA930().data
        com_ba_profiles = CommercialProfile(comstock_version=self.comstock_version, allocation_method=self.com_allocation_method).data
        res_ba_profiles = ResidentialProfile(resstock_version=self.resstock_version, allocation_method=self.res_allocation_method).data
        ind_ba_profiles = IndustrialProfile(basis_lrd_name=self.basis_lrd_name).data

        # calculate intersection of all BAs in profiles
        common_bas = set(self.total_ba_profiles.columns).intersection(
            com_ba_profiles.columns,
            res_ba_profiles.columns,
            ind_ba_profiles.columns
        )

        # drop cols not in common_bas
        tot_cols_to_drop = [col for col in self.total_ba_profiles.columns if col not in common_bas]
        if tot_cols_to_drop:
            logger.info(f"Dropping {', '.join(tot_cols_to_drop)} colums from Total profiles.")

        res_cols_to_drop = [col for col in res_ba_profiles.columns if col not in common_bas]
        if res_cols_to_drop:
            logger.info(f"Dropping {', '.join(res_cols_to_drop)} columns from Residential profiles.")
            self.res_ba_profiles = res_ba_profiles.drop(res_cols_to_drop, axis=1)

        ind_cols_to_drop = [col for col in ind_ba_profiles.columns if col not in common_bas]
        if ind_cols_to_drop:
            logger.info(f"Dropping {', '.join(ind_cols_to_drop)} columns from Industrial profiles.")
            self.ind_ba_profiles = ind_ba_profiles.drop(ind_cols_to_drop, axis=1)

        com_cols_to_drop = [col for col in com_ba_profiles.columns if col not in common_bas]
        if com_cols_to_drop:
            logger.info(f"Dropping {', '.join(com_cols_to_drop)} columns from Commercial profiles.")
            self.com_ba_profiles = com_ba_profiles.drop(com_cols_to_drop, axis=1)
        
        gap_ba_profiles = self.total_ba_profiles.sub(self.res_ba_profiles + self.com_ba_profiles + self.ind_ba_profiles)

        if self.trim_negative_gap:
            gap_ba_profiles.clip(lower=0, axis=1, inplace=True)
            logger.info(f"Trimming negative gap values to 0.")


        return gap_ba_profiles

    def commercial_electric_gap_by_county(self):
        """
        Allocate Total Commercial Gap profiles to Counties by Structures areas
        """
        # load gap profiles
        gap_ba_profiles = self.commercial_gap_by_ba()

        if self.gap_allocation_method == 'BAGeo':
            # load BA Areas, sum by BA and County
            ba_tract_areas = BAGeography().balancing_authority_bldg_areas_data()
            ba_tract_areas = ba_tract_areas.loc[:,'All Commercial'].to_frame()
            ba_tract_areas['county_fips'] = ba_tract_areas.index.get_level_values('CENSUSCODE').str[:5]
            ba_tract_areas = ba_tract_areas.set_index('county_fips', append=True)
            ba_county_areas = ba_tract_areas.groupby(['BA Code', 'county_fips']).sum()

            ba_totals = ba_county_areas.groupby('BA Code')['All Commercial'].sum().to_frame()

            ba_county_fracs = ba_county_areas.divide(ba_totals, level=0)
            ba_county_fracs.rename(columns={'All Commercial': 'fraction'}, inplace=True)

            # convert county census id to nhgis_county_gisjoin
            def census_id_to_gisjoin(id):
                state = str(id)[:2]
                county = str(id)[2:]
                return f'G{state}0{county}0'
            
            # remake index with county gisjoins
            ba_county_fracs.index = pd.MultiIndex.from_arrays(
                [
                    ba_county_fracs.index.get_level_values('BA Code'),
                    ba_county_fracs.index.get_level_values('county_fips').map(lambda x: census_id_to_gisjoin(x))
                ],
                names= [
                    'BA Code',
                    self.COUNTY_ID
                ]
            )

        elif self.gap_allocation_method == 'CBECS':
            ba_county_fracs = self.ba_county_fractions_from_cbecs()
        
        else:
            logger.error(f'Cannot allocate gap profiles to counties with method {self.gap_allocation_method} - not supported.')
            exit()


        bas_to_drop = [ba for ba in ba_county_fracs.index.get_level_values('BA Code').unique() if ba not in gap_ba_profiles.columns]
        logger.info(f"Dropping {', '.join(bas_to_drop)} from BA county areas")
        ba_county_fracs.drop(bas_to_drop, level='BA Code', inplace=True)

        ba_county_gap_profiles_data = {}
        for idx, row in ba_county_fracs.iterrows():
            ba_county_gap_profiles_data[idx] = gap_ba_profiles[idx[0]].mul(row['fraction'])
        
        ba_county_gap_profiles = pd.DataFrame(ba_county_gap_profiles_data)
        # print(ba_county_gap_profiles)
        
        county_gap_profiles = ba_county_gap_profiles.T.groupby(level=1).sum().T

        return county_gap_profiles


    def commercial_gas_gap_by_state(self):
        """
        """

        # TODO
        return None
    
    def plot_profiles_for_single_ba(self, ba_code):
        # extract specified ba from component dfs
        
        gap_ba_profiles = self.commercial_gap_by_ba()
        
        total = self.total_ba_profiles[[ba_code]].rename(columns={ba_code: f'{ba_code} Total Reported BA Demand'})
        ind = self.ind_ba_profiles[[ba_code]].rename(columns={ba_code: f'{ba_code} Industrial Profile (estimated)'})
        res = self.res_ba_profiles[[ba_code]].rename(columns={ba_code: f'{ba_code} Residential (ResStock adjusted)'})
        com = self.com_ba_profiles[[ba_code]].rename(columns={ba_code: f'{ba_code} ComStock Modeled'})
        gap = gap_ba_profiles[[ba_code]].rename(columns={ba_code: f'{ba_code} Commercial Gap'})

        df = pd.concat([total, ind, res, com, gap], axis=1)

        self.plot_profiles(df, df.columns, f'{ba_code} Annual Hourly Profiles', self.output_dir)


    def load_all_com_bldgs(self):
        all_bldgs_path = f'truth_data/{self.truth_data_version}/StockE/all_bldgs_with_tracts_for_gap.parquet'
        df = self.read_delimited_truth_data_file_from_S3(all_bldgs_path, delimiter=',')
        return df
    
    def correct_cbecs_other_eui(self, df, cbecs_eui_by_type_and_div):
        """
        Buildings with 'Other' type in CBECS have an unusually large electric EUI - similar to Laboratories or Restaurants. This type is mapped to the 'general' type in the buildings data, which makes up a significant portion of the square footage in certain counties, and since this type isn't mapped to a ComStock building type, this unfairly skews the 'gap' energy consumption by county.
        Instead, we assume that buildings categorized as 'general' in the buildings data are just mis-categorized of other types, and further that the distribution of those unknown types matches the distribution of correctly-categorized buildings for that state.
        So for each building with type 'general', apply an EUI calculated by the weighted average EUI of known types in that state.
        Args:
            df (pandas.DataFrame) buildings dataframe with CBECS building types 
            cbecs_eui_by_type_and_div (pandas.DataFrame) cbecs EUIs grouped by CBECS_BLDG_TYPE and CEN_DIV
        """
        logger.info("Adjusting 'general' building EUI based on state distribution of known-type buildings")

        EUI = self.col_name_to_eui(self.ANN_TOT_ELEC_KBTU)
        cbecs_eui_by_type = cbecs_eui_by_type_and_div.groupby(self.CBECS_BLDG_TYPE)[EUI].sum().to_frame()

        for state in df['state'].unique():
            state_bldgs = df.loc[df['state'] == state]
            by_type = state_bldgs.groupby(self.CBECS_BLDG_TYPE)['sqft'].sum().to_frame()
            division = state_bldgs[self.CEN_DIV].unique()[0]

            # get all CBECS euis by type for census division
            cbecs_euis_by_type_for_state = cbecs_eui_by_type_and_div.loc[cbecs_eui_by_type_and_div[self.CEN_DIV] == division]

            # get all buildings not categorized 'Other'/'general'
            by_type_filtered = by_type[by_type.index != 'Other']
            
            # merge in CBECS EUIs for known types
            by_type_filtered.reset_index(inplace=True)
            by_type_filtered = pd.merge(by_type_filtered, cbecs_euis_by_type_for_state, how='left', on=self.CBECS_BLDG_TYPE)
            
            # types in the buildings data might not be represented in the CBECS census division - in this case fill with national averages
            national_fills = cbecs_eui_by_type.rename(columns={EUI: 'National EUI'}).reset_index()
            by_type_filtered = pd.merge(by_type_filtered, national_fills, how='left', on=self.CBECS_BLDG_TYPE)
            by_type_filtered[EUI] = by_type_filtered[EUI].fillna(by_type_filtered['National EUI'])
            by_type_filtered.drop('National EUI', axis=1, inplace=True)

            # calculate know building total energy and eui
            by_type_filtered['total_electricity'] = by_type_filtered['sqft'].mul(by_type_filtered[EUI])

            state_avg_known_eui = by_type_filtered['total_electricity'].sum() / by_type_filtered['sqft'].sum()
            # print(f"{state_bldgs[self.STATE_NAME].unique()[0]} - old other EUI: {round(state_bldgs[state_bldgs[self.CBECS_BLDG_TYPE] == 'Other'][EUI].unique()[0], 3)} - new other EUI: {round(state_avg_known_eui,3)}")

            # assign this to all buildings eui
            filter = (df['state'] == state) & (df[self.CBECS_BLDG_TYPE] == 'Other')
            df.loc[filter, EUI] = state_avg_known_eui

            # update total electricity
            df.loc[filter, self.ANN_TOT_ELEC_KBTU] = df.loc[filter, 'sqft'].mul(state_avg_known_eui)

        return df

    def ba_county_fractions_from_cbecs(self):
        """
        Estimates the total annual commercial building electricity energy by county by using StockE total buildings by tract and type, and the mean electric energy intenstiy by building type from CBECS. 
        """

        processed_filename = 'gap_county_fractions_from_CBECS.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved:
            if os.path.exists(processed_path):
                logger.info('Reloading Gap County Fractions from saved')
                ba_county_fracs = pd.read_parquet(processed_path)
                return ba_county_fracs
            else:
                logger.warning(f'No processed data found for {processed_filename}.  Processing from truth data.')
                

        # mapping of StockE building types to cbecs types
        type_map = {
            'assembly': 'Other public assembly',
            'car_wash': 'Vehicle service/repair shop',
            'casino':  'Entertainment/culture',
            'distribution': 'Distribution/shipping center',
            'education': 'Multi-grade school (any K-12)',
            'entertainment': 'Entertainment/culture',
            'funeral_home': 'Other service',
            'general': 'Other',
            'grocery': 'Grocery store/food market',
            'gym': 'Recreation',
            'hospital': 'Hospital/inpatient health',
            'hotel': 'Hotel/resort',
            'hotel_casino': 'Hotel/resort',
            'industrial_other': 'Vehicle storage/maintenance',
            'institutional_dorm': 'Dormitory/fraternity/sorority',
            'institutional_healthcare': 'Nursing home/assisted living',
            'large_venue': 'Other public assembly',
            'laundry': 'Other service',
            'medical_office': 'Medical office (diagnostic)',
            'motel': 'Motel/inn/bed and breakfast',
            'office': 'Administrative/professional office',
            'office_residential': 'Mixed-use office',
            'outpatient': 'Clinic/other outpatient health',
            'parking': 'Vehicle storage/maintenance',
            'primary_school': 'Elementary school',
            'prison': 'Other public order and safety',
            'public_owned': 'Government office',
            'public_safety': 'Fire station/police station',
            'qsr': 'Fast food',
            'restaurant': 'Restaurant/cafeteria',
            'retail': 'Retail store',
            'retail_residential': 'Mixed-use office',
            'rnd': 'Laboratory',
            'secondary_school': 'High school',
            'self_storage': 'Public rental storage units',
            'service_station': 'Vehicle service/repair shop',
            'showroom': 'Other retail',
            'strip_mall': 'Strip shopping mall',
            'telco_dc_other': 'Other public order and safety',
            'trade': 'Other retail',
            'university': 'College/university',
            'warehouse': 'Non-refrigerated warehouse',
            'warehouse_refrigerated': 'Refrigerated warehouse'
        }

        # Load state-census region map
        state_table_path = f'truth_data/{self.truth_data_version}/EIA/CBECS/state_region_division_table.csv'
        state_table = self.read_delimited_truth_data_file_from_S3(state_table_path, delimiter=',')
        state_table = state_table.rename(columns={'State': self.STATE_NAME, 'State Code': self.STATE_ABBRV})
        state_table['FIPS Code'] = state_table['FIPS Code'].astype(str).str.zfill(2)

        # get EIA commercial sales by state and division - only need this for comparison chart
        eia_data = EIA861(type='Annual', segment='Commercial', measure='Sales').data
        eia_data = eia_data[eia_data['Part'] != 'C']
        eia_data = eia_data.rename(columns={'State': self.STATE_ABBRV})
        eia_data = pd.merge(eia_data, state_table, how='left', on=self.STATE_ABBRV)
        eia_data = eia_data.groupby([self.STATE_ABBRV, 'Division', 'FIPS Code'])['COMMERCIAL_Sales_MWh'].sum()

        # load all buildings
        all_bldgs = self.load_all_com_bldgs()
        all_bldgs['FIPS Code'] = all_bldgs['state'].str[1:3]
        all_bldgs = pd.merge(all_bldgs, state_table, how='left', on='FIPS Code')
        all_bldgs.rename(columns={
            'Division': self.CEN_DIV,
            'tract': self.TRACT_ID,
            'county': self.COUNTY_ID
            }, inplace=True)
        all_bldgs[self.CBECS_BLDG_TYPE] = all_bldgs['building_type'].map(type_map)

        # load CBECS
        cbecs_obj = CBECS(cbecs_year=2018, truth_data_version=self.truth_data_version, reload_from_csv=False)
        cbecs = cbecs_obj.data.collect().to_pandas()
        
        # calculate energy intensities from CBECS
        EUI = self.col_name_to_eui(self.ANN_TOT_ELEC_KBTU)
        cbecs_eui_by_type_and_div = cbecs.groupby([self.CBECS_BLDG_TYPE, self.CEN_DIV])[EUI].agg('mean').to_frame()
        cbecs_eui_by_type_and_div.reset_index(inplace=True)

        # merge cbecs EUIs by type and division into all buildings
        all_bldgs = pd.merge(all_bldgs, cbecs_eui_by_type_and_div, how='left', on=[self.CBECS_BLDG_TYPE, self.CEN_DIV])
        all_bldgs[self.ANN_TOT_ELEC_KBTU] = all_bldgs[EUI].mul(all_bldgs['sqft'])

        # correct EUI of 'general' type buildings
        all_bldgs = self.correct_cbecs_other_eui(all_bldgs, cbecs_eui_by_type_and_div)

        # sum by state, convert to MWh
        elec_by_state = all_bldgs.groupby(self.STATE_ABBRV)[self.ANN_TOT_ELEC_KBTU].sum() / 1e3
 
        # TODO: compare state estimated totals against EIA 861 reported totals in log-log plot

        # merge BAs, Utility IDs onto buildings data
        tract_utility_ba_map = CommercialProfile().tract_utility_ba_map()

        all_bldgs = pd.merge(all_bldgs, tract_utility_ba_map, how='left', on=self.TRACT_ID)

        # some of the tracts don't map to a utility and/or a BA code - report out how much this is
        na_bas = all_bldgs[all_bldgs['BA Code'].isna()]
        na_bldgs = len(na_bas.index)
        na_tracts = len(na_bas[self.TRACT_ID].unique())
        na_size_total = na_bas['sqft'].sum()
        na_size_frac = 100.0 * (na_size_total / all_bldgs['sqft'].sum())
        na_energy_total = na_bas[self.ANN_TOT_ELEC_KBTU].sum()
        na_energy_frac = 100.0 * (na_energy_total / all_bldgs[self.ANN_TOT_ELEC_KBTU].sum())

        logger.info(f"{na_bldgs} buildings in {na_tracts} tracts could not be mapped to a Balancing Authority. These represent {round(na_size_frac, 3)}% of total floor area and {round(na_energy_frac, 3)}% of estimated total electric energy.")

        all_bldgs = all_bldgs.dropna(subset='BA Code')
        # determine county ID

        # remove comstock building types to get 'gap' total load
        comstock_types = {
            'full_service_restaurant': 'FullServiceRestaurant',
            'restaurant': 'FullServiceRestaurant',
            'office': 'LargeOffice',
            'distribution': 'Warehouse',
            'hotel': 'LargeHotel',
            'model': 'SmallHotel',
            'qsr': 'QuickServiceRestaurant',
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

        gap_bldgs = all_bldgs[~all_bldgs['building_type'].isin(comstock_types.keys())]


        # sum by BA 
        by_ba = gap_bldgs.groupby('BA Code')[self.ANN_TOT_ELEC_KBTU].sum().to_frame()

        # sum estimated total energy by BA and County
        by_ba_and_county = gap_bldgs.groupby(['BA Code', self.COUNTY_ID])[self.ANN_TOT_ELEC_KBTU].sum().to_frame()

        # compute county BA fractions
        ba_county_fracs = by_ba_and_county.div(by_ba, level=0)
        ba_county_fracs.rename(columns={self.ANN_TOT_ELEC_KBTU: 'fraction'}, inplace=True)

        ba_county_fracs.to_parquet(processed_path)

        return ba_county_fracs
    
    def annual_comparison_plot(self):
        """
        Creates an annual comparison stacked barchart of reported EIA sector totals compared to modeled profile totals
        """

        logger.info('Creating Annual Comparison chart.')

        # reported totals
        reported_totals = pd.DataFrame()

        TOTAL = 'EIA930 total MWh'
        IND = 'EIA861 Industrial'
        COM = 'EIA861 Commercial'
        RES = 'EIA861 Residential'
        GAP = 'Reported Gap'

        # EIA 930 totals
        ba_profiles = EIA930().data
        total_930 = ba_profiles.sum().sum()
        
        reported_totals.at[TOTAL, 'value'] = total_930

        # EIA 861 Sales
        all_861 = EIA861(segment=['Industrial', 'Commercial', 'Residential'], measure='Sales').data
        all_861 = all_861[all_861['Part'] != 'C']
        # remove Alaska and Hawaii - don't have BAs to compare in gap
        all_861 = all_861[(all_861['State'] != 'AK') & (all_861['State'] != 'HI')]

        all_861_total = all_861[['INDUSTRIAL_Sales_MWh', 'COMMERCIAL_Sales_MWh', 'RESIDENTIAL_Sales_MWh']].sum(axis=0).to_frame()
        
        reported_totals.at[IND, 'value'] = all_861_total.loc['INDUSTRIAL_Sales_MWh'][0]
        reported_totals.at[COM, 'value'] = all_861_total.loc['COMMERCIAL_Sales_MWh'][0]
        reported_totals.at[RES, 'value'] = all_861_total.loc['RESIDENTIAL_Sales_MWh'][0]

        reported_totals.at[GAP, 'value'] = reported_totals.loc[TOTAL, 'value'] - (reported_totals.loc[IND, 'value'] + reported_totals.loc[COM, 'value'] + reported_totals.loc[RES, 'value'])

        # modeled totals
        modeled_totals = pd.DataFrame()

        COM_M = 'ComStock Total'
        RES_M = 'ResStock Adjusted Total'
        IND_M = 'Industrial Estimated Total'
        GAP_M = 'Commercial Gap'
        UGAP_M = 'Uncategorized Gap'

        gap = self.commercial_gap_by_ba()
        gap_total = gap.sum().sum()

        com_total = self.com_ba_profiles.sum().sum()
        res_total = self.res_ba_profiles.sum().sum()
        ind_total = self.ind_ba_profiles.sum().sum()

        modeled_totals.at[COM_M, 'value'] = com_total
        modeled_totals.at[RES_M, 'value'] = res_total
        modeled_totals.at[IND_M, 'value'] = ind_total

        modeled_totals.at[GAP_M, 'value'] = reported_totals.loc[COM, 'value'] - modeled_totals.loc[COM_M, 'value']
        modeled_totals.at[UGAP_M, 'value'] = gap_total - modeled_totals.loc[GAP_M, 'value']

        reported_categories = [IND, RES, COM, GAP]
        modeled_categories = [IND_M, RES_M, COM_M, GAP_M, UGAP_M]

        # reported_values = reported_totals.loc[reported_categories, 'value']
        # modeled_values = modeled_totals.loc[modeled_categories, 'value']
        print(modeled_totals)
        print(reported_totals)

        # value: [bar color, text color] 
        colors = {
            IND: ['orange','white'],
            IND_M: ['orange','white'],
            RES: ['purple','white'],
            RES_M: ['purple','white'],
            COM: ['green','white'],
            COM_M: ['green','white'],
            GAP_M: ['lightgreen','black'],
            GAP: ['grey','black'],
            UGAP_M: ['grey','black']
        }

        bar_width = 0.4

        fig, ax = plt.subplots(figsize=(12, 8))
        x = np.arange(2)
        bottom = 0
        for category in reported_categories:
            value = reported_totals.loc[category, 'value']
            ax.bar(x[0], value, width=bar_width, bottom=bottom, label=category, color=colors[category][0], edgecolor='black')
            ax.text(x[0], bottom + value / 2, category, ha='center', va='center', fontsize=10, color=colors[category][1])
            bottom += value

        bottom = 0
        for category in modeled_categories:
            value = modeled_totals.loc[category, 'value']
            ax.bar(x[1], value, width=bar_width, bottom=bottom, label=category, color=colors[category][0], edgecolor='black')
            ax.text(x[1], bottom + value / 2, category, ha='center', va='center', fontsize=10, color=colors[category][1])
            bottom += value

        ax.set_xticks(x)
        ax.set_xticklabels(['Reported', 'Modeled'])
        ax.set_ylabel('Annual Electricity Consumption (MWh)')
        ax.set_title('Annual Electricity Consumption Comparison')

        plt.tight_layout()
        fig_name = f'{ax.title.get_text()}.png'
        fig_path = os.path.join(self.plot_dir, fig_name)
        plt.savefig(fig_path, dpi=600, bbox_inches='tight')

    def monthly_comparison_plot(self):
        """
        Generates a stacked bar chart comparing EIA reported to modeled sector monthly totals
        """

        TOTAL = 'EIA930 total MWh'
        IND = 'EIA861 Industrial'
        COM = 'EIA861 Commercial'
        RES = 'EIA861 Residential'
        GAP = 'Reported Gap'
        REPORTED = [IND, RES, COM, GAP]

        ba_profiles = EIA930().data
        ba_profiles['month'] = ba_profiles.index.month
        monthly_930_totals = ba_profiles.groupby('month').sum().sum(axis=1).to_frame().rename(columns={0: 'EIA930 Total MWh'})

        all_861_monthly = EIA861(type='Monthly', segment=['Industrial', 'Commercial', 'Residential'], measure='Sales').data
        all_861_monthly_total = all_861_monthly.groupby('Month')[['RESIDENTIAL_Sales_MWh', 'INDUSTRIAL_Sales_MWh', 'COMMERCIAL_Sales_MWh']].sum()
        all_861_monthly_total.index = all_861_monthly_total.index.astype(int)

        monthly_reported = pd.merge(monthly_930_totals, all_861_monthly_total, left_index=True, right_index=True)
        monthly_reported.rename(columns={
            'COMMERCIAL_Sales_MWh': COM,
            'INDUSTRIAL_Sales_MWh': IND,
            'RESIDENTIAL_Sales_MWh': RES,
            'EIA930 Total MWh': TOTAL
            }, inplace=True)

        monthly_reported[GAP] = monthly_reported[TOTAL] - (monthly_reported[IND] + monthly_reported[COM] + monthly_reported[RES])
        monthly_reported.fillna(0.0, inplace=True)

        # monthly modeled
        COM_M = 'ComStock Total'
        RES_M = 'ResStock Adjusted Total'
        IND_M = 'Industrial Estimated Total'
        GAP_M = 'Commercial Gap'
        UGAP_M = 'Uncategorized Gap'
        MODELED = [IND_M, RES_M, COM_M, GAP_M, UGAP_M]

        def profiles_to_monthly_totals(df, name):
            df = df.shift(-1, freq='h').sum(axis=1).to_frame()
            df['month'] = df.index.month
            df_monthly = df.groupby('month').sum()
            df_monthly.rename(columns={0: name}, inplace=True)
            return df_monthly

        modeled_monthly = pd.concat([
            profiles_to_monthly_totals(self.com_ba_profiles, COM_M),
            profiles_to_monthly_totals(self.res_ba_profiles, RES_M),
            profiles_to_monthly_totals(self.ind_ba_profiles, IND_M),
        ], axis=1)

        modeled_monthly.reset_index(names='Month', inplace=True)
        modeled_monthly = modeled_monthly.merge(monthly_reported[[TOTAL, COM]], left_on='Month', right_index=True)
        modeled_monthly[GAP_M] = modeled_monthly[COM] - modeled_monthly[COM_M]
        modeled_monthly[UGAP_M] = modeled_monthly[TOTAL] - (modeled_monthly[COM_M] + modeled_monthly[RES_M] + modeled_monthly[IND_M] + modeled_monthly[GAP_M])
        modeled_monthly['Month Name'] = modeled_monthly['Month'].apply(lambda x: pd.to_datetime(str(x), format='%m').strftime('%b'))


        fig, ax = plt.subplots(figsize=(12, 6))
        bar_width = 0.4
        x = np.arange(len(monthly_reported.index))

        colors = dict(zip(REPORTED, ['orange', 'purple', 'green', 'grey']))
        colors.update(dict(zip(MODELED, ['orange', 'purple', 'green', 'lightgreen', 'grey'])))

        btm_rep = np.zeros(len(monthly_reported.index))
        for col in REPORTED:
            ax.bar(x - (bar_width / 2), monthly_reported[col], width=bar_width, bottom=btm_rep, label=col, color=colors[col], edgecolor='black', hatch='xx')
            btm_rep += monthly_reported[col]

        btm_mod = np.zeros(len(modeled_monthly.index))
        for col in MODELED:
            ax.bar(x + (bar_width / 2), modeled_monthly[col], width=bar_width, bottom=btm_mod, label=col, color=colors[col], edgecolor='black')
            btm_mod += modeled_monthly[col]

        ax.set_xticks(x)
        ax.set_xticklabels(modeled_monthly['Month Name'])
        ax.set_ylabel('Monthly Electricity Consumption (MWh)')
        ax.set_title('Monthly Electricity Consumption Comparison')
        ax.legend(loc='upper left', bbox_to_anchor=(1, 1), fontsize=12)
        ax.axhline(0, color='black', linewidth=0.8)
        ax.grid(axis='y', linestyle='--', alpha=0.7)
        plt.tight_layout()

        fig_name = f'{ax.title.get_text()}.png'
        fig_path = os.path.join(self.plot_dir, fig_name)
        plt.savefig(fig_path, dpi=600, bbox_inches='tight')

    def plot_profiles(self, aggregation_type, aggregation_key):
        """
        plots all profiles for representative weeks of the year, for a given aggregation type and key
        Args:
            aggregation_type (String): ['BA', 'County', 'State']
            aggregation_key (String or List): BA Code, County nhgis_gisjoin, or State abbreviation, or 'All' or list
        """

        def plot_for_dates(df, type, key, colors, fig_name):
            dates = {
                'Winter': ['2018-01-15', '2018-01-22'],
                'Spring': ['2018-04-15', '2018-04-22'],
                'Summer': ['2018-07-02', '2018-07-09'],
                'Fall': ['2018-10-15', '2018-10-22'],
            }

            fig, ax = plt.subplots(2, 2, figsize=(14, 10))
            ax = ax.flatten()

            # slices = [df['EIA 930 Total'].loc[start:end] for start, end in dates.values()]
            df.drop(columns=['EIA 930 Total'], inplace=True, errors='ignore')
            slices = [df['ResStock'].loc[start:end] for start, end in dates.values()]
            max_val = max([s.max() for s in slices])

            for i, (season, date_range) in enumerate(dates.items()):
                data = df.loc[date_range[0]:date_range[1]].copy()
                for col in data.columns:
                    if col == 'Other Commercial + Uncategorized':
                        alpha = 1
                        colors[col] = 'black'
                    else:
                        alpha = 0.5
                    ax[i].plot(data.index, data[col], label=col, alpha=alpha, color=colors[col])
                ax[i].xaxis.set_major_formatter(mdates.DateFormatter('%b-%d'))
                ax[i].set_xlabel('Date')
                ax[i].set_xlim(pd.to_datetime(date_range[0]).replace(hour=0, minute=0), pd.to_datetime(date_range[1]).replace(hour=23, minute=0))
                ax[i].set_ylabel('Electricity Demand (MW)')
                ax[i].set_ylim(0, 1.1 * max_val)
                ax[i].set_title(f"{season}: {pd.to_datetime(date_range[0]).strftime('%B %d')} - {pd.to_datetime(date_range[1]).strftime('%d')}")
                # ax[i].legend()
                ax[i].grid(True)

            handles, labels = ax[0].get_legend_handles_labels()
            fig.legend(handles, labels, loc='upper center', bbox_to_anchor=(0.5, 0.95), fontsize=14, ncol=5)

            fig.suptitle(f'{key} Electric Load Weekly Profiles', fontsize=16)
            fig_path = os.path.join(self.plot_dir, fig_name)
            plt.savefig(fig_path, dpi=600, bbox_inches='tight')
            plt.close(fig)

        def plot_stacked_area_for_days(df, key, colors):
            """
            Plots a stacked area plot of the columns in df for four representative days of the year.

            Args:
                df (pd.DataFrame): DataFrame containing time-series data with a datetime index.
                output_dir (str): Directory to save the plot.
                key (str): Identifier for the plot (e.g., BA, County, or State).
            """
            dates = {
                'Winter': '2018-01-15',
                'Spring': '2018-04-15',
                'Summer': '2018-07-02',
                'Fall': '2018-10-19',
            }

            fig, ax = plt.subplots(2, 2, figsize=(14, 10))
            ax = ax.flatten()

            stacks = ['Industrial', 'ResStock', 'ComStock', 'Other Commercial + Uncategorized']
            color_list = [colors[x] for x in stacks]
            data_to_stack = df[stacks]
            data_to_line = df[['EIA 930 Total']]

            max_val = data_to_line.loc[data_to_line.index.floor('D').isin([pd.to_datetime(v) for v in dates.values()])].values.max()
            print(max_val)

            for i, (season, date) in enumerate(dates.items()):
                day_data = data_to_stack.loc[date].copy()
                ax[i].stackplot(day_data.index, day_data.T, labels=day_data.columns, colors=color_list, alpha=0.8)
                ax[i].plot(data_to_line.loc[date].index, data_to_line.loc[date], label='EIA 930 Total', color='blue', alpha=1)
                ax[i].xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
                ax[i].set_ylabel('Electricity Consumption (MWh)')
                ax[i].set_title(f"{season}: {pd.to_datetime(date).strftime('%B %d (%A)')}")
                ax[i].set_ylim(0, 1.1 * max_val)
                ax[i].set_xlim(pd.to_datetime(date).replace(hour=0, minute=0), pd.to_datetime(date).replace(hour=23, minute=0))

            handles, labels = ax[0].get_legend_handles_labels()
            fig.legend(handles, labels, loc='upper center', bbox_to_anchor=(0.5, 0.95), fontsize=10, ncol=5)
            fig.suptitle(f'{key} Electricity Profile Components', fontsize=16)
            fig.tight_layout(rect=[0, 0, 1, 0.96])

            fig_name = f'{key} Component Profile.png'
            fig_path = os.path.join(self.plot_dir, fig_name)
            plt.savefig(fig_path, dpi=600, bbox_inches='tight')
            plt.close(fig)


        if aggregation_type == 'BA':

            total_profiles = EIA930().data
            gap_profile = self.commercial_gap_by_ba()
            com_profile = self.com_ba_profiles
            res_profile = self.res_ba_profiles
            ind_profile = self.ind_ba_profiles
            
            if aggregation_key == 'All':
                keys_to_plot = gap_profile.columns
            elif type(aggregation_key) == list:
                keys_to_plot = [key for key in gap_profile.columns if key in aggregation_key]
            elif (type(aggregation_key) == str) & (aggregation_key in gap_profile.columns):
                keys_to_plot = [aggregation_key]
            else:
                logger.error(f"BA {aggregation_key} not found in gap profiles")
                return None
            
            for key in keys_to_plot:
                logger.info(f"Plotting profiles for BA {key}")

                total_data = total_profiles[[key]].copy()
                gap_data = gap_profile[[key]].copy()
                com_data = com_profile[[key]].copy()
                res_data = res_profile[[key]].copy()
                ind_data = ind_profile[[key]].copy()

                # combine into single dataframe
                df = pd.concat([
                    total_data, 
                    gap_data, 
                    com_data, 
                    res_data, 
                    ind_data
                ], axis=1)

                df.columns = [
                    'EIA 930 Total',
                    'Other Commercial + Uncategorized',
                    'ComStock',
                    'ResStock',
                    'Industrial'
                ]
                
                # plot for each season
                colors = {
                    'EIA 930 Total': 'blue',
                    'Other Commercial + Uncategorized': 'grey',
                    'ComStock': 'green',
                    'ResStock': 'purple',
                    'Industrial': 'orange'
                }

                fig_name = f'{key} {aggregation_type} Profiles.png'
                plot_stacked_area_for_days(df, key, colors)
                plot_for_dates(df, aggregation_type, key, colors, fig_name)
                

                # return df