import os
import boto3
import logging
import botocore
import calendar
import pandas as pd
from better.model import InverseModel
from buildstock_query import BuildStockQuery
from comstockpostproc.gap.eia861 import EIA861
from comstockpostproc.gap.degreedays import DegreeDays
from comstockpostproc.gap.ba_geography import BAGeography

from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin

# Create logger for AWS queries
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ResidentialProfile(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', reload_from_saved=True, save_processed=True, resstock_version='2024_amy2018_release_2'):
        """
        A class to generate residential hourly electricity demand profiles by Balancing Authority. Utilizes ResStock results, modified to better match historical
        aggregate load reported from EIA 861.
        
        Args:
            truth_data_version: The version of truth data. 'v01'
            reload_from_saved (Bool): reload from processed data if available
            save_processed (Bool): Flag to save out processed files

        Attributes:
            data (DataFrame): Hourly residential electric load profiles, based on national ResStock simulation results, apportioned to Balancing Authority territories
        """

        self.truth_data_version = truth_data_version
        self.reload_from_saved = reload_from_saved
        self.save_processed = save_processed
        self.resstock_version = resstock_version
        self.resstock_profiles_filename = f"resstock_{self.resstock_version}_load_by_state"

        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))

        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')

        # calculate BA profiles
        self.data = self.ba_res_profiles()

    def resstock_net_elec_timestep(self):
        """
        Queries resstock for timestep total net energy by county. Not used here - generates a multi-GB file that times out when attempting to download.
        """

        run = BuildStockQuery(workgroup='eulp',
                             db_name='buildstock_sdr',
                             table_name=(
                                 f'resstock_{self.resstock_version}_metadata_state_vu',
                                 f'resstock_{self.resstock_version}_by_state_vu',
                                 None),
                             db_schema='resstock_oedi',
                            #  db_schema=None,
                             buildstock_type='resstock',
                             skip_reports=True)
        
        query = f"""
        SELECT
            "t2"."timestamp" as "time",
            sum("t2"."out.electricity.net.energy_consumption" * "t1"."weight") as "total_net_electricity",
            "t1"."in.county" as "county"
        FROM
            "resstock_{self.resstock_version}_metadata_state_vu" as "t1"
        INNER JOIN
            "resstock_{self.resstock_version}_by_state_vu" as "t2"
        ON
            "t1"."bldg_id" = "t2"."bldg_id"
        WHERE
            "t1"."upgrade" = 0 and
            "t2"."upgrade" = 0 and
            "t1"."state" = 'ID'
        GROUP BY
            "t2"."timestamp",
            "t1"."in.county"
        """

        logger.info('Querying Athena for timeseries ResStock results. This will take a while, go get a coffee...')

        df = run.execute(query)

        df.to_parquet(os.path.join(self.truth_data_dir, f'{self.resstock_profiles_filename}.parquet'))

        return df

    def resstock_net_elec_hourly(self):
        """
        Queries resstock for ending-hour total net energy by state. 
        """

        run = BuildStockQuery(workgroup='eulp',
                              db_name='buildstock_sdr',
                              table_name=(
                                f'resstock_{self.resstock_version}_metadata_state_vu',
                                f'resstock_{self.resstock_version}_by_state_vu',
                                None
                              ),
                              db_schema='resstock_oedi',
                              buildstock_type='resstock',
                              skip_reports=True)
        
        query = f"""
        select
            case
                when extract(minute from "t2"."timestamp") = 0
                    and extract(second from "t2"."timestamp") = 0
                    then date_trunc('hour', "t2"."timestamp")
                else date_trunc('hour', "t2"."timestamp") + interval '1' hour
            end as "rounded_hour",
            sum("t2"."out.electricity.net.energy_consumption" * "t1"."weight") as "total_net_electricity",
            "t1"."state" as "state"
        from
            "resstock_{self.resstock_version}_metadata_state_vu" as "t1"
        inner join
            "resstock_{self.resstock_version}_by_state_vu" as "t2"
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

        logger.info('Querying Athena for timeseries ResStock results. This will take a while (approx 7min), go get a coffee...')

        df = run.execute(query)

        df.to_parquet(os.path.join(self.truth_data_dir, f'{self.resstock_profiles_filename}.parquet'))

        return df

    def resstock_hourly_by_state(self):
        """
        Loads resstock results from existing truth data file or by querying S3
        """

        local_path = os.path.join(self.truth_data_dir, f'{self.resstock_profiles_filename}.parquet')
        if os.path.exists(local_path):
            logger.info('Reloading ResStock timestep county profiles from truth data')
            res_load = pd.read_parquet(local_path)
        else:
            # res_county_load = self.resstock_net_elec_timestep()
            res_load = self.resstock_net_elec_hourly()

        res_load.set_index('rounded_hour', inplace=True)

        return res_load
    
    def adjust_state_residential_profiles(self):
        """
        Uses ten years of EIA861 Monthly total reported residential electricity consumption per residential customer by state, and monthly state population-weighted
        degree-days to generate a 5-parameter change point model using the LBNL Better inverse regression model. Creates a similar 5P model for daily total ResStock demand per customer against
        daily state population-weighted degree-days. Then computes daily adjustment factors that scale the ResStock results so that the resulting 5P model matches the EIA 861 model parameters

        Returns a dataframe with DateTime index and column for each state of adjusted electrical demand in kWh.  
        """

        processed_filename = 'res_hourly_by_state_adjusted.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved: 
            if os.path.exists(processed_path):
                logger.info('Reloading Adjusted Residential Hourly Profiles from saved')
                df = pd.read_parquet(processed_path)
                return df
            else:
                logger.info(f"No processed data found for {processed_filename}. Processing from truth data.")

        # load resstock raw hourly net load by state
        resstock_state_hourly = self.resstock_hourly_by_state()
        
        # pivot to one column per state
        resstock_hourly_by_state = resstock_state_hourly.pivot_table('total_net_electricity', index='rounded_hour', columns='state', aggfunc='sum')

        # shift to beginning hour
        resstock_hourly_by_state = resstock_hourly_by_state.shift(-1, freq='h')
        
        # resstock daily totals
        resstock_daily_by_state = resstock_hourly_by_state.resample('d').sum()

        # # load monthly historical EIA 861 data
        # eia_monthly_res = EIA861(type='Monthly', year='All', segment='Residential', measure='Sales').data

        # load state population-weighted daily degree-days for simulation year
        daily_dds = DegreeDays(freq='Daily', year=2018).data

        # load state population-weighted monthly degree days for all years
        monthly_dds = DegreeDays(freq='Monthly', year='All').data

        # EIA 861 Monthly Residential MWh per Customer by state and month all years
        eiam_res = EIA861(type='Monthly', year='All', segment='Residential', measure=['Sales', 'Customers']).data
        eiam_res['sales_per_customer'] = eiam_res['RESIDENTIAL_Sales_MWh'] / eiam_res['RESIDENTIAL_Customers_ct']

        eiam_all_monthly = eiam_res.pivot_table('sales_per_customer', index=['Year', 'Month'], columns='State', aggfunc='sum')

        # EIA 861M Residential customer counts by state for 2018
        eiam_res_18 = eiam_res.loc[eiam_res['Year'] == 2018][['Year', 'Month', 'State', 'RESIDENTIAL_Customers_ct']]
        eiam_18_cust_by_state = eiam_res_18.pivot_table('RESIDENTIAL_Customers_ct', index=['Year', 'Month'], columns='State', aggfunc='sum')

        # get number of days in month
        def days_in_month(month):
            return calendar.monthrange(20118, month)[1]
        
        # calculate daily adjustments to raw resstock by finding the 5P model that fits the daily resstock data compared to daily state population-weighted average temps,
        # and adjusting to fit the 5P model found by comparing 10 years of EIAM data agianst monthly average population-weighted temps

        # resulting dataframes
        res_daily_corrections = pd.DataFrame()
        model_params = pd.DataFrame()

        for col in resstock_daily_by_state.columns:

            # get historical monthly MWh per customer
            eiam_data = eiam_all_monthly.loc[:,col].copy()

            # get monthly degree-days
            if col == 'DC': # no dds for DC, use Maryland instead
                state = 'MD'
            else:
                state = col

            state_monthly_dds = monthly_dds.loc[:,state].copy()
            state_daily_dds = daily_dds.loc[:,state].copy()

            eia_df = pd.concat([eiam_data, state_monthly_dds], axis=1)
            eia_df.rename(columns={col: 'MWh/customer'}, inplace=True)
            
            # calculate average consumption per day per customer and average temps
            eia_df['num_days'] = eia_df.apply(lambda row: days_in_month(int(row.name[1])), axis=1)
            eia_df['kWh per day per customer'] = eia_df['MWh/customer'] * 1e3 / eia_df['num_days']
            eia_df['avg_temp'] = 65 + (eia_df['cdd'] / eia_df['num_days']) - (eia_df['hdd'] / eia_df['num_days'])

            # fit change point model to eia data
            eia_model = InverseModel(eia_df['avg_temp'].values, eia_df['kWh per day per customer'].values, 'kWh per day per customer')
            eia_model.fit_model()

            # get resstock daily consumption
            res_df = resstock_daily_by_state.loc[:,col].to_frame()
            res_df.rename(columns={col:'kWh'}, inplace=True)

            # calculate resstock daily load per customer, using EIAM customer counts for 2018
            custs = eiam_18_cust_by_state.loc[:, col].to_frame()
            custs.set_index(custs.index.get_level_values(1).astype(int), inplace=True)
            custs = custs.reindex(res_df.index.month, method='ffill')
            custs.set_index(res_df.index, inplace=True)
            custs.rename(columns={col:'customer_ct'}, inplace=True)

            res_df = res_df.merge(custs, left_index=True, right_index=True)
            res_df['kWh per day per customer'] = res_df['kWh'] / res_df['customer_ct']

            # calculate daily average temp from daily degree days
            res_df = pd.concat([res_df, state_daily_dds], axis=1)
            res_df['avg_temp'] = 65 + res_df['cdd'] - res_df['hdd']

            # fit change point model to resstock data
            res_model = InverseModel(res_df['avg_temp'].values, res_df['kWh per day per customer'].values, 'kWh per day per customer')
            res_model.fit_model()

            # get eia fitted model outputs for range of res temps
            eia_model_outputs = InverseModel.piecewise_linear(res_df['avg_temp'].values, *eia_model.p)

            # get res fitted model outputs
            res_model_outputs = InverseModel.piecewise_linear(res_df['avg_temp'].values, *res_model.p)

            # calculate scaling factors
            res_df[f'{col}_scaling_factors'] = eia_model_outputs / res_model_outputs
            res_df['scaled_kWh per day per customer'] = res_df['kWh per day per customer'] * res_df[f'{col}_scaling_factors']

            # TODO: Plot origianal and scaled resstock values

            # write model parameters to dataframe
            model_df = pd.DataFrame(
                data={col: list(eia_model.model_p) + [eia_model.R_Squared(), eia_model.rmse()]},
                index = [
                    'base (kWh/day/customer)',
                    'heating change temp (F)',
                    'heating slope (kWh/day/customer/F)',
                    'cooling change temp (F)',
                    'cooling slope (kWh/day/customer/F)',
                    'r2',
                    'RMSE'
                ]
            )

            # create scaling factors dataframe
            res_df.rename(columns={f'{col}_scaling_factors': col}, inplace=True)
            res_daily_corrections = pd.concat([res_daily_corrections, res_df[col]], axis=1)
            model_params = pd.concat([model_params, model_df], axis=1)

        self.regression_model_params = model_params

        # resasmple daily corrections to hourly frequency
        res_hourly_corrections = res_daily_corrections.reindex(resstock_hourly_by_state.index, method='ffill')

        # apply corrections to resstock
        resstock_hourly_by_state_corrected = resstock_hourly_by_state * res_hourly_corrections

        # shift back to ending hour
        resstock_hourly_by_state_corrected = resstock_hourly_by_state_corrected.shift(1, freq='h')

        if self.save_processed:
            resstock_hourly_by_state_corrected.to_parquet(processed_path)

        return resstock_hourly_by_state_corrected

    def ba_res_profiles(self):
        """
        Apportions the adjusted ResStock profiles to Balancing Authorities by dividing load based on the fraction of total residential building area found in each territory from the 
        Structures data. This assumes that residential-coded structures areas are equally proportional to electricity use nationwide (in each state). 

        An alternate approach would be to use the count of Residential customers from EIA data in each BA by state, but this wouldn't include utilities that report in the Short EIA 861 data.
        """

        processed_filename = 'res_ba_profiles.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved: 
            if os.path.exists(processed_path):
                logger.info('Reloading BA Residential Hourly Profiles from saved')
                df = pd.read_parquet(processed_path)
                return df
            else:
                logger.info(f"No processed data found for {processed_filename}. Processing from truth data.")

        # load corrected profiles
        res_hourly_by_state_corrected = self.adjust_state_residential_profiles()

        # load county to BA mapping
        ba_tract_areas = BAGeography().balancing_authority_bldg_areas_data()
        ba_tract_res_areas = ba_tract_areas.loc[:,'Residential'].to_frame()

        # merge tract data to state
        ba_tract_res_areas['state_fips'] = ba_tract_res_areas.index.get_level_values('CENSUSCODE').str[:2]
        ba_tract_res_areas.set_index('state_fips', append=True, inplace=True)
        ba_state_areas = ba_tract_res_areas.groupby(['BA Code', 'state_fips']).sum()

        # get fips to abbrev map and group BA areas by state abbrev
        state_labels = self.read_delimited_truth_data_file_from_S3(f'truth_data/{self.truth_data_version}/national_state2020.txt', '|')
        state_labels['STATEFP'] = state_labels['STATEFP'].astype(str).str.zfill(2)
        state_labels = state_labels[['STATE','STATEFP']].set_index('STATEFP')

        ba_state_areas = ba_state_areas.join(state_labels, on='state_fips')
        ba_state_areas.set_index([ba_state_areas.index.get_level_values(level=0), 'STATE'], inplace=True)
        ba_state_areas = ba_state_areas.reorder_levels(['STATE', 'BA Code'])
        ba_state_areas.sort_index(inplace=True)

        # residential areas for each BA in each state
        res_ba_areas = ba_state_areas.loc[:, 'Residential'].to_frame()

        # total areas by state
        state_res_areas = ba_state_areas.groupby(['STATE'])['Residential'].sum().to_frame()

        # fractions of total state residential area in each BA
        res_ba_areas['area_frac'] = res_ba_areas.divide(state_res_areas, level=0)

        # multiply State BA fractions by State profiles to get State BA profiles
        res_ba_state_profiles_data = {}
        for idx, row in res_ba_areas.iterrorws():
            res_ba_state_profiles_data[idx] = res_hourly_by_state_corrected[idx[0]].mul(row['area_frac'])

        res_ba_profiles = pd.DataFrame(res_ba_state_profiles_data)

        # convert from kWh to MWh
        res_ba_state_profiles = res_ba_state_profiles / 1e3

        # combine by BA
        res_ba_profiles = res_ba_state_profiles.T.groupby(level=1).sum().T

        if self.save_processed:
            res_ba_profiles.to_parquet(processed_path)

        return res_ba_profiles









