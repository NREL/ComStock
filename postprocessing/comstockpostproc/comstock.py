'# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.'
# See top level LICENSE.txt file for license terms.
import os
from functools import lru_cache
from fsspec.core import url_to_fs
from joblib import Parallel, delayed

import boto3
import botocore
import glob
import gzip
import json
import logging
import shutil
import botocore.exceptions
import numpy as np
import pandas as pd
import polars as pl
import re
import datetime

from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.units_mixin import UnitsMixin
from comstockpostproc.cbecs import CBECS
from comstockpostproc.eia import EIA
from comstockpostproc.ami import AMI
from comstockpostproc.comstock_apportionment import Apportion
from comstockpostproc.gas_correction_model import GasCorrectionModelMixin
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin, write_geo_data
from buildstock_query import BuildStockQuery

logger = logging.getLogger(__name__)

COLUMN_DEFINITION_FILE_NAME = 'comstock_column_definitions.csv'
ENUM_DEFINITION_FILE_NAME = 'comstock_enumeration_definitions.csv'
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
RESOURCE_DIR = os.path.join(CURRENT_DIR, 'resources')

# ComStock in a constructor class for processing ComStock results
class ComStock(NamingMixin, UnitsMixin, GasCorrectionModelMixin, S3UtilitiesMixin):
    def __init__(self, s3_base_dir, comstock_run_name, comstock_run_version, comstock_year, athena_table_name,
        truth_data_version, buildstock_csv_name = 'buildstock.csv', acceptable_failure_percentage=0.01, drop_failed_runs=True,
        color_hex=NamingMixin.COLOR_COMSTOCK_BEFORE, weighted_energy_units='tbtu', weighted_demand_units='gw', weighted_ghg_units='co2e_mmt', weighted_utility_units='billion_usd', skip_missing_columns=False,
        reload_from_csv=False, make_comparison_plots=True, make_timeseries_plots=True, include_upgrades=True, upgrade_ids_to_skip=[], states={}, upgrade_ids_for_comparison={}, rename_upgrades=False):
        """
        A class to load and transform ComStock data for export, analysis, and comparison.
        Args:

            comstock_run_s3_dir (str): The location of the ComStock run on S3
            comstock_run_name (str): The name of the ComStock run, used to look
            up the data on S3
            comstock_year (int): The year represented by this ComStock run
            comstock_run_version (str): The version string for this ComStock run
            to differentiate it from other ComStock runs
        """

        # Initialize members
        self.comstock_run_name = comstock_run_name
        self.comstock_run_version = comstock_run_version
        self.year = comstock_year
        self.truth_data_version = truth_data_version
        self.dataset_name = f'ComStock {self.comstock_run_version}'
        self.data_dir = os.path.join(CURRENT_DIR, '..', 'comstock_data', self.comstock_run_version)
        self.truth_data_dir = os.path.join(CURRENT_DIR, '..', 'truth_data', self.truth_data_version)
        self.output_dir = os.path.abspath(os.path.join(CURRENT_DIR, '..', 'output', self.dataset_name))
        self.results_file_name = 'results_up00.parquet'
        self.building_type_mapping_file_name = f'CBECS_2012_to_comstock_nems_aeo_building_types.csv'
        self.buildstock_file_name = buildstock_csv_name
        self.ejscreen_file_name = 'EJSCREEN_Tract_2020_USPR.csv'
        self.egrid_file_name = 'egrid_emissions_2019.csv'
        self.cejst_file_name = '1.0-communities.csv'
        self.geospatial_lookup_file_name = 'spatial_tract_lookup_table_publish_v6.csv'
        self.tract_to_util_map_file_name = 'tract_to_elec_util.csv'
        self.hvac_metadata_file_name = 'hvac_metadata.csv'
        self.rename_upgrades = rename_upgrades
        self.rename_upgrades_file_name = 'rename_upgrades.json'
        self.athena_table_name = athena_table_name
        self.data = None
        self.fkt = None  # TODO verify that we should initialize this?
        self.plotting_data = None
        self.monthly_data = None
        self.monthly_data_gap = None
        self.ami_timeseries_data = None
        self.data_long = None
        self.color = color_hex
        self.building_type_weights = None
        self.weighted_energy_units = weighted_energy_units
        self.weighted_demand_units = weighted_demand_units
        self.weighted_ghg_units = weighted_ghg_units
        self.weighted_utility_units = weighted_utility_units
        self.skip_missing_columns = skip_missing_columns
        self.include_upgrades = include_upgrades
        self.upgrade_ids_to_skip = upgrade_ids_to_skip
        self.upgrade_ids_for_comparison = upgrade_ids_for_comparison
        self.states = states
        self.unweighted_weighted_map = {}
        self.cached_parquet = [] # List of parquet files to reload and export
        # TODO our currect credential setup aren't playing well with this approach but does with the s3 ServiceResource
        # We are currently unable to list the HeadObject for automatically uploaded data
        # Consider migrating all usage to s3 ServiceResource instead.
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))
        self.s3_resource = boto3.resource('s3')
        if self.athena_table_name is not None:
            self.athena_client = BuildStockQuery(workgroup='eulp',
                                                 db_name='enduse',
                                                 buildstock_type='comstock',
                                                 table_name=self.athena_table_name,
                                                 skip_reports=True)
        self.make_comparison_plots = make_comparison_plots
        self.make_timeseries_plots = make_timeseries_plots
        self.APPORTIONED = False # Including this for some basic control logic in which methods are allowed
        self.CBECS_WEIGHTS_APPLIED = False # Including this for some additional control logic about method order
        logger.info(f'Creating {self.dataset_name}')

        # Make directories
        for p in [self.data_dir, self.truth_data_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        # S3 location
        self.s3_inpath = None
        if s3_base_dir is not None:
            if self.athena_table_name:
                self.s3_inpath = f"s3://{s3_base_dir}/{self.comstock_run_name}/{self.athena_table_name}"
            else:
                self.s3_inpath = f"s3://{s3_base_dir}/{self.comstock_run_name}/{self.comstock_run_name}"

        # Load and transform data, preserving all columns
        self.download_data()
        pl.enable_string_cache()
        if reload_from_csv:
            upgrade_pqts = glob.glob(os.path.join(self.output_dir, 'cached_ComStock_wide_upgrade*.parquet'))
            upgrade_pqts.sort()
            if len(upgrade_pqts) > 0:
                upgrade_dfs = []
                for file_path in upgrade_pqts:
                    bn = os.path.basename(file_path)
                    up_id = int(bn.replace('cached_ComStock_wide_upgrade', '').replace('.parquet', ''))
                    if up_id in self.upgrade_ids_to_skip:
                        logger.info(f'Skipping reload for upgrade {up_id}')
                        continue
                    logger.info(f'Reloading data from: {file_path}')
                    upgrade_dfs.append(pl.scan_parquet(file_path))
                self.data = pl.concat(upgrade_dfs)
            elif os.path.exists(os.path.join(self.output_dir, 'ComStock wide.csv')):
                file_path = os.path.join(self.output_dir, 'ComStock wide.csv')
                logger.info(f'Reloading data from: {file_path}')
                self.data = pl.scan_csv(file_path, dtypes={self.UPGRADE_ID: pl.Int64}, infer_schema_length=50000)
            else:
                raise FileNotFoundError(
                f'Cannot find wide .csv or .parquet in {self.output_dir} to reload data, set reload_from_csv=False.')
        else:

            # Get upgrades to process based on available results parquet files
            upgrade_ids = []
            results_paths = glob.glob(os.path.join(self.data_dir, 'results_up*.parquet'))
            results_paths.sort()
            for results_path in results_paths:
                upgrade_id = np.int64(os.path.basename(results_path).replace('results_up', '').replace('.parquet', ''))

                # Skip specified upgrades
                if upgrade_id in self.upgrade_ids_to_skip:
                    logger.info(f'Skipping upgrade {upgrade_id}')
                    continue

                upgrade_ids.append(upgrade_id)

            # Import columns from buildstock, results.csv, and other files
            up_lazyframes = []
            upgrade_ids.sort()
            for upgrade_id in upgrade_ids:
                self.data = None
                self.load_data(upgrade_id, acceptable_failure_percentage, drop_failed_runs)
                self.add_buildstock_csv_columns()
                self.data = self.downselect_imported_columns(self.data)
                self.rename_columns_and_convert_units()
                self.set_column_data_types()
                # Calculate/generate columns based on imported columns
                # self.add_aeo_nems_building_type_column()  # TODO POLARS figure out apply function
                self.add_missing_energy_columns()
                # self.combine_utility_cols()
                self.add_enduse_total_energy_columns()
                self.add_energy_intensity_columns()
                # self.add_bill_intensity_columns()
                # self.add_energy_rate_columns()
                self.add_normalized_qoi_columns()
                self.add_peak_intensity_columns()
                self.add_vintage_column()
                self.add_dataset_column()
                # self.add_upgrade_building_id_column()  # TODO POLARS figure out apply function
                self.add_hvac_metadata()
                self.add_building_type_group()
                self.add_enduse_fuel_group_columns()
                self.add_enduse_group_columns()
                self.add_addressable_segments_columns()
                self.combine_emissions_cols()
                self.add_emissions_intensity_columns()
                self.get_comstock_unscaled_monthly_energy_consumption()
                self.add_unweighted_savings_columns()
                # Downselect the self.data to just the upgrade
                self.data = self.data.filter(pl.col(self.UPGRADE_ID) == upgrade_id)
                # self._sightGlass_metadata_check(self.data)
                # Write self.data to parquet file, hive partition on upgrade to make later processing faster
                file_name = f'cached_ComStock_wide_upgrade{upgrade_id}.parquet'
                upgrade_dir = os.path.join(self.output_dir, 'cached_wide_by_upgrade', f'upgrade={upgrade_id}')
                os.makedirs(upgrade_dir, exist_ok=True)
                file_path = os.path.join(upgrade_dir, file_name)
                self.cached_parquet.append((upgrade_id, file_path)) #cached_parquet is a list of parquets used to export and reload
                logger.info(f'Caching to: {file_path}')
                self.data = self.reorder_data_columns(self.data)
                self.data = self.data.drop('upgrade')  # upgrade column will be read from hive partition dir name
                self.data.write_parquet(file_path)
                up_lazyframes.append(file_path)

            # Now, we have self.data is one huge LazyFrame
            # which is exactly like self.data was before because it includes all upgrades
            self.data = pl.scan_parquet(up_lazyframes, hive_partitioning=True)
            self._aggregate_failure_summaries()
            # logger.info(f'comstock data schema: {self.data.dtypes()}')
            # logger.debug('\nComStock columns after adding all data:')
            # for c in self.data.columns:
            #     logger.debug(c)

    def _aggregate_failure_summaries(self):
        #sinece we are generating summary of falures based on
        #each upgrade_id(in load_data()), we should aggregate
        #the summary of failures for each upgrade_id into one

        path = os.path.join(self.output_dir)

        alLines = list()
        #find all the failure_summary files like with failure_summary_0.csv
        # failure_summary_1.csv ... failure_summary_k.csv
        for file in os.listdir(path):
            if file.startswith("failure_summary_") and file.endswith(".csv"):
                #open the file and read the content
                with open(os.path.join(path, file), 'r') as f:
                    for line in f:
                        if line not in alLines:
                            alLines.append(line)
                 #delete the file
                os.remove(os.path.join(path, file))

        #write the aggregated summary of failures to a new file
        with open(os.path.join(path, "failure_summary_aggregated.csv"), 'w') as f:
            for line in alLines:
                f.write(line)


    def download_data(self):
        # Get data on the s3 resource to download data from:
        if self.s3_inpath is None:
            logger.info('The s3 path provided in the ComStock object initalization is invalid.')
        s3_path_items = self.s3_inpath.lstrip('s3://').split('/')
        bucket_name = s3_path_items[0]
        prfx = '/'.join(s3_path_items[1:])

        # baseline/results_up00.parquet
        results_data_path = os.path.join(self.data_dir, self.results_file_name)
        if not os.path.exists(results_data_path):
            baseline_parquet_path = f"{prfx}/baseline/{self.results_file_name}"
            try:
                self.s3_resource.Object(bucket_name, baseline_parquet_path).load()
            except botocore.exceptions.ClientError:
                logger.error(f'Could not find results_up00.parquet at {baseline_parquet_path} in bucket {bucket_name}')
                raise FileNotFoundError(
                    f'Missing results_up00.parquet file. Manually download and place at {results_data_path}'
                )
            logger.info(f'Downloading {baseline_parquet_path} from the {bucket_name} bucket')
            self.s3_resource.Object(bucket_name, baseline_parquet_path).download_file(results_data_path)

        # upgrades/upgrade=*/results_up*.parquet
        if self.include_upgrades:
            if len(glob.glob(f'{self.data_dir}/results_up*.parquet')) < 2:
                if self.s3_inpath is None:
                    logger.info('The s3 path passed to the constructor is invalid, '
                                'cannot check for results_up**.parquet files to download')
                else:
                    upgrade_parquet_path = f'{prfx}/upgrades'
                    resp = self.s3_resource.Bucket(bucket_name).objects.filter(Prefix=upgrade_parquet_path).all()
                    for obj in list(resp):
                        obj_path = obj.key
                        obj_name = obj_path.split('/')[-1]
                        m = re.search('results_up(.*).parquet', obj_name)
                        if not m:
                            continue
                        upgrade_id = m.group(1)
                        if upgrade_id in self.upgrade_ids_to_skip:
                            logger.info(f'Skipping data download for upgrade {upgrade_id}')
                            continue
                        results_data_path = os.path.join(self.data_dir, obj_name)
                        if not os.path.exists(results_data_path):
                            logger.info(f'Downloading {obj_path} from the {bucket_name} bucket')
                            self.s3_resource.Object(bucket_name, obj_path).download_file(results_data_path)

        # buildstock.csv
        #1. check the file in the data_dir
        #2. if not found, download from S3
        #3. if not found in S3, raise an error
        buildstock_csv_path = os.path.join(self.data_dir, self.buildstock_file_name)
        if not os.path.exists(buildstock_csv_path):
            s3_path = f"{self.s3_inpath}/buildstock_csv/buildstock.csv"
            bldstk_s3_path = f'{prfx}/buildstock_csv/buildstock.csv'
            try:
                self.s3_resource.Object(bucket_name, bldstk_s3_path).load()
            except botocore.exceptions.ClientError:
                logger.error(f'Could not find buildstock.csv at {bldstk_s3_path} in bucket {bucket_name}')
                raise FileNotFoundError(
                    f'Missing buildstock.csv file. Manually download and place at {buildstock_csv_path}'
                )
            logger.info(f'Downloading {bldstk_s3_path} from the {bucket_name} bucket')
            self.s3_resource.Object(bucket_name, bldstk_s3_path).download_file(buildstock_csv_path)

        # EJSCREEN
        ejscreen_data_path = os.path.join(self.truth_data_dir, self.ejscreen_file_name)
        if not os.path.exists(ejscreen_data_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/EPA/EJSCREEN/{self.ejscreen_file_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')

        # egrid emissions factors
        egrid_data_path = os.path.join(self.truth_data_dir, self.egrid_file_name)
        if not os.path.exists(egrid_data_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/EPA/eGRID/{self.egrid_file_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')

        # CEJST (CEQ's official EJ/J40 designations)
        cejst_data_path = os.path.join(self.truth_data_dir, self.cejst_file_name)
        if not os.path.exists(cejst_data_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/EPA/CEJST/{self.cejst_file_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')

        # Geospatial data
        geospatial_data_path = os.path.join(self.truth_data_dir, self.geospatial_lookup_file_name)
        if not os.path.exists(geospatial_data_path):
            sampling_file_path = os.path.abspath(os.path.join(__file__, '..', '..', '..', 'sampling', 'resources', self.geospatial_lookup_file_name))
            logger.info(f'sampling_file_path: {sampling_file_path}')
            if os.path.exists(sampling_file_path):
                shutil.copy(sampling_file_path, geospatial_data_path)

        # Electric Utility Data
        elec_util_data_path = os.path.join(self.truth_data_dir, self.tract_to_util_map_file_name)
        if not os.path.exists(elec_util_data_path):
            s3_file_path = f'truth_data/{self.truth_data_version}/{self.tract_to_util_map_file_name}'
            self.read_delimited_truth_data_file_from_S3(s3_file_path, ',')

    def download_timeseries_data_for_ami_comparison(self, ami, reload_from_csv=True, save_individual_regions=False):
        if reload_from_csv:
            file_name = f'Timeseries for AMI long.csv'
            file_path = os.path.join(self.output_dir, file_name)
            if not os.path.exists(file_path):
                 raise FileNotFoundError(
                    f'Cannot find {file_path} to reload data, set reload_from_csv=False to create CSV.')
            logger.info(f'Reloading from CSV: {file_path}')
            self.ami_timeseries_data = pd.read_csv(file_path, low_memory=False, index_col='timestamp', parse_dates=True)
        else:
            athena_end_uses = list(map(lambda x: self.END_USES_TIMESERIES_DICT[x], self.END_USES))
            athena_end_uses.append('total_site_electricity_kwh')
            all_timeseries_df = pd.DataFrame()
            for region in ami.ami_region_map:
                region_file_path_long = os.path.join(self.output_dir, region['source_name'] + '_building_type_timeseries_long.csv')
                if os.path.isfile(region_file_path_long) and reload_from_csv and save_individual_regions:
                    logger.info(f"timeseries data in long format for {region['source_name']} already exists at {region_file_path_long}")
                    continue

                ts_agg = self.athena_client.agg.aggregate_timeseries(enduses=athena_end_uses,
                                                                     group_by=['build_existing_model.building_type', 'time'],
                                                                     restrict=[('build_existing_model.county_id', region['county_ids'])])
                if ts_agg['time'].dtype == 'Int64':
                    # Convert bigint to timestamp type if necessary
                    ts_agg['time'] = pd.to_datetime(ts_agg['time']/1e9, unit='s')

                # region_file_path_wide = os.path.join(self.output_dir, region['source_name'] + '_building_type_timeseries_wide.csv')
                # ts_agg.to_csv(region_file_path_wide, index=False)
                # logger.info(f"Saved enduse timeseries in wide format for {region['source_name']} to {region_file_path_wide}")

                timeseries_df = self.convert_timeseries_to_long(ts_agg, region['county_ids'], region['source_name'], save_individual_region=save_individual_regions)
                timeseries_df['region_name'] = region['source_name']
                all_timeseries_df = pd.concat([all_timeseries_df, timeseries_df])

            data_path = os.path.join(self.output_dir, 'Timeseries for AMI long.csv')
            all_timeseries_df.to_csv(data_path, index=True)
            self.ami_timeseries_data = all_timeseries_df

    def convert_timeseries_to_long(self, agg_df, county_ids, output_name, save_individual_region=False):
        # rename columns
        agg_df = agg_df.set_index('time')
        agg_df = agg_df.rename(columns={
            "build_existing_model.building_type": "building_type",
            "electricity_exterior_lighting_kwh": "exterior_lighting",
            "electricity_interior_lighting_kwh": "interior_lighting",
            "electricity_interior_equipment_kwh": "interior_equipment",
            "electricity_water_systems_kwh": "water_systems",
            "electricity_heat_recovery_kwh": "heat_recovery",
            "electricity_fans_kwh": "fans",
            "electricity_pumps_kwh": "pumps",
            "electricity_cooling_kwh": "cooling",
            "electricity_heating_kwh": "heating",
            "electricity_refrigeration_kwh": "refrigeration",
            "total_site_electricity_kwh": "total"
        })

        # aggregate by hour
        agg_df['year'] = agg_df.index.year
        agg_df['month'] = agg_df.index.month
        agg_df['day'] = agg_df.index.day
        agg_df['hour'] = agg_df.index.hour
        agg_df = agg_df.groupby(['building_type', 'year', 'month', 'day', 'hour']).sum().reset_index()
        agg_df['timestamp'] = agg_df.apply(
            lambda r: datetime.datetime(
                r['year'],
                r['month'],
                r['day']
            ) +
            datetime.timedelta(hours=r['hour']),
            axis=1
        )
        agg_df = agg_df.drop(['year', 'month', 'day', 'hour', 'units_count'], axis=1)
        agg_df = agg_df.set_index('timestamp')
        agg_df = agg_df[agg_df.index.dayofyear != 366]

        # melt into long format
        val_vars = [
            'exterior_lighting',
            'interior_lighting',
            'interior_equipment',
            'water_systems',
            'heat_recovery',
            'fans',
            'pumps',
            'cooling',
            'heating',
            'refrigeration',
            'total'
        ]
        agg_df = pd.melt(
            agg_df.reset_index(),
            id_vars=[
                'timestamp',
                'building_type',
                'sample_count'
            ],
            value_vars=val_vars,
            var_name='enduse',
            value_name='kwh'
        ).set_index('timestamp')
        agg_df = agg_df.rename(columns={'sample_count': 'bldg_count'})

        # size get data
        # note that this is a Polars dataframe, not a Pandas dataframe
        self.data = self.data.with_columns([pl.col('in.nhgis_county_gisjoin').cast(pl.Utf8)])
        # size_df = self.data.filter(self.data['in.nhgis_county_gisjoin'].is_in(county_ids))
        size_df = self.data.clone().filter(pl.col('in.nhgis_county_gisjoin').is_in(county_ids))
        size_df = size_df.select(['in.comstock_building_type', 'in.sqft', 'calc.weighted.sqft']).collect()

        # Cast columns to match dtype of lists
        size_df = size_df.with_columns([
            pl.col('in.comstock_building_type').cast(pl.Utf8),
            pl.col('in.sqft').cast(pl.Float64),
            pl.col('calc.weighted.sqft').cast(pl.Float64)
        ])

        size_df = size_df.group_by('in.comstock_building_type').agg(pl.col(['in.sqft', 'calc.weighted.sqft']).sum())
        size_df = size_df.with_columns((pl.col('calc.weighted.sqft')/pl.col('in.sqft')).alias('weight'))
        size_df = size_df.with_columns((pl.col('in.comstock_building_type').replace(self.BLDG_TYPE_TO_SNAKE_CASE, default=None)).alias('building_type'))
        # file_path = os.path.join(self.output_dir, output_name + '_building_type_size.csv')
        # size_df.write_csv(file_path)

        weight_dict = dict(zip(size_df['building_type'].to_list(), size_df['weight'].to_list()))
        weight_size_dict = dict(zip(size_df['building_type'].to_list(), size_df['calc.weighted.sqft'].to_list()))
        agg_df['kwh_weighted'] = agg_df['kwh'] * agg_df['building_type'].map(weight_dict)

        # calculate kwh/sf
        agg_df['kwh_per_sf'] = agg_df.apply(lambda row: row['kwh_weighted'] / weight_size_dict.get(row['building_type'], 1), axis=1)
        agg_df = agg_df.drop(['kwh', 'kwh_weighted'], axis=1)

        # save out long data format
        if save_individual_region:
            output_file_path = os.path.join(self.output_dir, output_name + '_building_type_timeseries_long.csv')
            agg_df.to_csv(output_file_path, index=True)
            logger.info(f"Saved enduse timeseries in long format for {output_name} to {output_file_path}")

        return agg_df

    def load_data(self, upgrade_id, acceptable_failure_percentage=0.01, drop_failed_runs=True):
        # Ensure that the baseline results exist
        data_file_path = os.path.join(self.data_dir, self.results_file_name)
        if not os.path.exists(data_file_path):
            raise FileNotFoundError(
                f'Missing {data_file_path}, cannot load ComStock data')

        # Read the buildstock.csv to determine number of simulations expected
        buildstock = pl.read_csv(os.path.join(self.data_dir, self.buildstock_file_name), infer_schema_length=50000)
        buildstock.rename({'Building': 'sample_building_id'})
        buildstock_bldg_count = buildstock.shape[0]
        logger.debug(f'{buildstock_bldg_count} models in buildstock.csv')

        # Create a list of results to eventually combine
        base_failed_ids = set()
        upgrade_id_to_results = {}
        failure_summaries = []

        # Load results, identify failed runs
        for upgrade_id in [0, upgrade_id]:

            # Skip specified upgrades
            if upgrade_id in self.upgrade_ids_to_skip:
                logger.info(f'Skipping upgrade {upgrade_id}')
                continue

            # Load upgrade results
            results_path = os.path.join(self.data_dir, f'results_up{str(upgrade_id).zfill(2)}.parquet')
            logger.debug(f'Reading results_up{upgrade_id}')
            up_res = pl.read_parquet(results_path)
            up_res = up_res.with_columns([
                pl.lit(upgrade_id).alias(self.UPGRADE_ID)
            ])
            # Set a few columns for the baseline
            if upgrade_id == 0:
                up_res = up_res.with_columns([pl.lit(self.BASE_NAME).alias('apply_upgrade.upgrade_name')])
                a_up_col = 'apply_upgrade.applicable'
                if up_res[a_up_col].dtype == pl.Boolean:
                    up_res = up_res.with_columns([pl.lit(True).alias(a_up_col)])
                    logger.debug('Adding apply_upgrade.applicable to baseline as Boolean')
                elif up_res[a_up_col].dtype == pl.Utf8:
                    up_res = up_res.with_columns([pl.lit('True').alias(a_up_col)])
                    logger.debug('Adding apply_upgrade.applicable to baseline as String')

            # Fill Nulls in measure-within-upgrade applicability columns with False
            for c, dt in up_res.schema.items():
                if 'applicable' in c:
                    logger.debug(f'For {c}: Nulls set to False in upgrade, and its type is {dt}')
                    if dt == pl.Null or dt == pl.Boolean:
                        logger.debug(f'For {c}: Nulls set to False (Boolean) in baseline')
                        up_res = up_res.with_columns([pl.col(c).fill_null(pl.lit(False))])
                    elif dt == pl.Utf8:
                        logger.debug(f'For {c}: Nulls set to "False" (String) in baseline')
                        up_res = up_res.with_columns([pl.col(c).fill_null(pl.lit("False"))])
                        up_res = up_res.with_columns([pl.when(pl.col(c).str.lengths() == 0).then(pl.lit('False')).otherwise(pl.col(c)).keep_name()])
                # make sure all columns contains no null values
                    assert up_res.get_column(c).null_count() == 0, f'Column {c} contains null values'

            # Convert columns with only 'True' and/or 'False' strings to Boolean
            for col, dt in up_res.schema.items():
                if not dt == pl.Utf8:
                    continue
                # Get all the values in a column, including null/blank rows
                col_vals = up_res.get_column(col).unique().str.to_lowercase().to_list()
                if len(col_vals) > 10:  # Contains more than true/false if more than 10 values
                    continue
                # Downselect to only string values (exclude Nulls)
                lower_col_vals = [c.lower() for c in col_vals if isinstance(c, str)]
                # Any combination of null, true, and false is considered a boolean column
                bool_possibilities = [set(['true', 'false']), set(['true']), set(['false'])]
                if set(lower_col_vals) in bool_possibilities:
                    up_res = up_res.with_columns(pl.col(col).str.to_lowercase().replace({"false": False, "true": True}, default=None))

            # Downselect columns to reduce memory use
            up_res = self.downselect_imported_columns(up_res)

            # Check that the results length matches buildstock.csv length
            if not len(up_res) == buildstock_bldg_count:
                logger.warning(f"There were {buildstock_bldg_count} buildings in the buildstock.csv but only {len(up_res)} in the results.csv ({round((len(up_res)/buildstock_bldg_count)*100, 2)}%).")
                logger.warning("    This likely means that one or more jobs timed out while running buildstockbatch and didn't make it to the results.csv file.")
                logger.warning("    Run    tail -n 5 job.out-*    inside the project directory to review the job.out files.")

                # Add building IDs that are missing to the list of "failed" buildings
                missing_ids = [id for id in buildstock['sample_building_id'] if id not in up_res.index]
                base_failed_ids.update(missing_ids)

            # Determine the verified success/failure/NA status
            # buildings that failed per builstockbatch
            # or were "successful" but have no results (happens when long-running building jobs are manually killed)
            # or have any empty completion status column (unclear why this happens)
            VERIFIED_COMP_STATUS = 'verified_completed_status'
            ST_TOTAL = 'Building Count'
            ST_SUCCESS = 'Success'
            ST_NA = 'Not Applicable'
            ST_FAIL = 'Failed'
            ST_FAIL_BSB = 'Failed: per BuildStockBatch'
            ST_FAIL_NO_RES = 'Failed: missing simulation results'
            ST_FAIL_NO_STATUS = 'Failed: missing completion status'
            FRAC_FAIL = 'Fraction of Total Failed'
            FRAC_NA = 'Fraction Not Applicable'
            FRAC_APPL = 'Fraction Applicable'
            ST_SUCCESS_BASE_FAIL_UP = 'Success in baseline, failed in upgrade'
            ST_SUCCESS_UP_FAIL_BASE = 'Success in upgrade, failed in baseline'
            up_res = up_res.with_columns([
                # Failed per buildstockbatch completion status
                pl.when(
                (pl.col(self.COMP_STATUS) == 'Fail'))
                .then(pl.lit(ST_FAIL_BSB))
                # Failed because missing simulation outputs
                .when(
                (pl.col(self.COMP_STATUS) == 'Success') &
                (pl.col('simulation_output_report.total_site_energy_mbtu').is_null()))
                .then(pl.lit(ST_FAIL_NO_RES))
                # Failed because missing completion status
                .when(
                (pl.col(self.COMP_STATUS).is_null()))
                .then(pl.lit(ST_FAIL_NO_STATUS))
                # Sucessful, but upgrade was NA, so has no results
                .when(
                (pl.col(self.COMP_STATUS) == 'Invalid'))
                .then(pl.lit(ST_NA))
                # Successful and has results available
                .otherwise(pl.lit(ST_SUCCESS))
                # Assign the column name
                .alias(VERIFIED_COMP_STATUS)
            ])

            # Correct the completion status column to reflect all failure modes
            up_res = up_res.with_columns([
                # Failures of all types
                pl.when(
                (pl.col(VERIFIED_COMP_STATUS).is_in([ST_FAIL_BSB, ST_FAIL_NO_RES, ST_FAIL_NO_STATUS])))
                .then(pl.lit('Fail'))
                # Not applicable
                .when(
                (pl.col(VERIFIED_COMP_STATUS) == ST_NA))
                .then(pl.lit('Invalid'))
                # Success
                .when(
                (pl.col(VERIFIED_COMP_STATUS) == ST_SUCCESS))
                .then(pl.lit('Success'))
                # Should not get here
                .otherwise(pl.lit('ERROR'))
                # Assign the column name
                .alias(self.COMP_STATUS)
            ])

            # Check that no rows have a completion status of "ERROR" assigned
            errs = up_res.select((pl.col(self.COMP_STATUS).filter(pl.col(self.COMP_STATUS) == 'ERROR').count()))
            num_errs = errs.get_column(self.COMP_STATUS).sum()
            if num_errs > 0:
                raise Exception(f'Errors in correcting completion status for {num_errs} buildings, fix logic.')

            # Get the upgrade name
            up_res_success = up_res.select(
                (pl.col('apply_upgrade.upgrade_name').filter(pl.col(VERIFIED_COMP_STATUS) == ST_SUCCESS))
            )
            upgrade_name = up_res_success.get_column('apply_upgrade.upgrade_name').head(1).to_list()[0]

            # Summarize the failure status counts
            fs = up_res.get_column(VERIFIED_COMP_STATUS).value_counts()
            dat = [fs.get_column('count').to_list()]
            sch = fs.get_column(VERIFIED_COMP_STATUS).to_list()
            fs = pl.DataFrame(data=dat, schema=sch)

            # Add upgrade ID and name to failure summary
            fs = fs.with_columns([pl.lit(upgrade_id).alias(str(self.UPGRADE_ID))])
            fs = fs.with_columns([pl.lit(upgrade_name).alias(str(self.UPGRADE_NAME))])

            # Add missing completion statuses (not all upgrades will have all failure types)
            for fm in [ST_SUCCESS, ST_NA, ST_FAIL_BSB, ST_FAIL_NO_RES, ST_FAIL_NO_STATUS]:
                if fm not in fs:
                    fs = fs.with_columns([pl.lit(0).alias(fm).cast(pl.Int64)])

            # Calculate total number of failures
            fs = fs.with_columns(((pl.col(ST_FAIL_BSB)) + (pl.col(ST_FAIL_NO_RES)) + (pl.col(ST_FAIL_NO_STATUS))).alias(ST_FAIL))

            # Calculate the total number of models
            fs = fs.with_columns(((pl.col(ST_SUCCESS)) + (pl.col(ST_NA)) + (pl.col(ST_FAIL))).alias(ST_TOTAL))

            # Calculate failure percentage
            fs = fs.with_columns((pl.col(ST_FAIL) / pl.col(ST_TOTAL)).round(3).alias(FRAC_FAIL))

            # Calculate fraction not applicable
            fs = fs.with_columns((pl.col(ST_NA) / pl.col(ST_TOTAL)).round(3).alias(FRAC_NA))

            # Calculate fraction applicable
            fs = fs.with_columns((pl.col(ST_SUCCESS) / pl.col(ST_TOTAL)).round(3).alias(FRAC_APPL))

            # Find the failed building IDs
            up_fail_ids = up_res.select(
                (pl.col('building_id').filter(pl.col(self.COMP_STATUS) == 'Fail'))
            )
            up_fail_ids = up_fail_ids.get_column('building_id').unique().to_list()
            if upgrade_id == 0:
                base_failed_ids.update(up_fail_ids)

            # Check the upgrade failure percentage and error if too high
            num_up_failures = len(up_fail_ids)
            num_up_total = up_res.shape[0]
            pct_up_failed = num_up_failures / num_up_total
            if pct_up_failed > acceptable_failure_percentage:
                err_msg = (f'Upgrade {upgrade_id} failure rate was {pct_up_failed} ({num_up_failures} of {num_up_total} simulations), '
                    f'which is above the specified acceptable limit of {acceptable_failure_percentage}.')
                logger.error(err_msg)
                raise Exception(err_msg)

            # Find buildings that failed in the upgrade but not the baseline
            failed_in_up_success_in_base = [id for id in up_fail_ids if id not in base_failed_ids]
            fs = fs.with_columns([pl.lit(len(failed_in_up_success_in_base)).cast(pl.Int64).alias(str(ST_SUCCESS_BASE_FAIL_UP))])

            # Find buildings that failed in the baseline but not the upgrade
            failed_in_base_success_in_up = [id for id in base_failed_ids if id not in up_fail_ids]
            fs = fs.with_columns([pl.lit(len(failed_in_base_success_in_up)).cast(pl.Int64).alias(ST_SUCCESS_UP_FAIL_BASE)])

            fs = fs.select(sorted(fs.columns))
            failure_summaries.append(fs)

            if drop_failed_runs:
                # Drop failed baseline runs
                up_res = up_res.filter(~pl.col('building_id').is_in(base_failed_ids))

            upgrade_id_to_results[upgrade_id] = up_res

        # Save failure summary
        failure_summaries = pl.concat(failure_summaries, how='diagonal')
        fs_cols = [
            self.UPGRADE_ID,
            self.UPGRADE_NAME,
            ST_TOTAL,
            ST_SUCCESS,
            ST_NA,
            ST_FAIL,
            FRAC_APPL,
            FRAC_NA,
            FRAC_FAIL,
            ST_SUCCESS_BASE_FAIL_UP,
            ST_SUCCESS_UP_FAIL_BASE,
            ST_FAIL_BSB,
            ST_FAIL_NO_RES,
            ST_FAIL_NO_STATUS,
        ]
        failure_summaries = failure_summaries.select(fs_cols)
        file_name = f'failure_summary_{upgrade_id}.csv'
        file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
        failure_summaries.write_csv(file_path)

        # Process results
        results_dfs = []
        for upgrade_id, up_res in upgrade_id_to_results.items():
            logger.info(f'Processing upgrade {upgrade_id}')
            # Drop all buildings that failed in the baseline run
            up_res = up_res.filter(~pl.col('building_id').is_in(base_failed_ids))

            # Get the baseline results
            base_res = upgrade_id_to_results[0]

            # Merge the building characteristics from the baseline results to the upgrade results
            bldg_char_cols = [c for c in base_res.columns if c not in up_res.columns]
            bldg_char_cols.append('building_id')
            if not upgrade_id == 0:
                up_res = up_res.join(base_res.select(bldg_char_cols), how='left', on='building_id')

            # Split upgrade results into applicable (Success), not applicable (Invalid), and failed in upgrade
            up_res_applic = up_res.filter(pl.col(self.COMP_STATUS) == 'Success')
            up_res_na = up_res.filter(pl.col(self.COMP_STATUS) == 'Invalid')
            up_res_fail = up_res.filter(pl.col(self.COMP_STATUS) == 'Fail')

            # Applicable results are unmodified
            up_res_applic = up_res_applic.select(sorted(up_res_applic.columns))

            # Cast utility columns to float64 to avoid data type inconsistancies
            pattern_util_rate_name = re.compile(r'utility_bills.*_rate.*_name')
            pattern_util_cost = re.compile(r'utility_bills.*_rate.*_bill_dollars')
            for col, dt in up_res_applic.schema.items():
                if pattern_util_rate_name.match(col):
                    orig_dt = up_res_applic.schema[col]
                    if not orig_dt == pl.Utf8:
                        up_res_applic = up_res_applic.with_columns([pl.col(col).cast(pl.Utf8)])
                        dt = up_res_applic.schema[col]
                        logger.info(f'Cast {col} from {orig_dt} to {dt}')
                elif pattern_util_cost.match(col):
                    orig_dt = up_res_applic.schema[col]
                    if not orig_dt == pl.Float64:
                        up_res_applic = up_res_applic.with_columns([pl.col(col).cast(pl.Float64)])
                        dt = up_res_applic.schema[col]
                        logger.info(f'Cast {col} from {orig_dt} to {dt}')

            results_dfs.append(up_res_applic)

            # Get the upgrade name
            up_res_success = up_res_applic.select(
                (pl.col('apply_upgrade.upgrade_name').filter(pl.col(self.COMP_STATUS) == 'Success'))
            )
            upgrade_name = up_res_success.get_column('apply_upgrade.upgrade_name').head(1).to_list()[0]

            # For buildings where the upgrade did NOT apply, add annual results columns from the Baseline run
            # The columns completed_status = "Invalid" and apply_upgrade.applicable = FALSE enable identification later,
            # and any savings calculated for these runs will be zero because upgrade == baseline
            if up_res_na.shape[0] > 0:
                shared_cols = [c for c in base_res.columns if c in up_res.columns]
                cols_to_leave_alone = [
                    'job_id',
                    'started_at',
                    'completed_at',
                    self.COMP_STATUS,
                    'apply_upgrade.applicable',
                    'apply_upgrade.upgrade_name',
                    self.UPGRADE_ID,
                    'apply_upgrade.reference_scenario',
                    self.upgrade_ids_to_skip
                ]
                cols_to_replace = [c for c in shared_cols if c not in cols_to_leave_alone]
                cols_to_keep = [c for c in base_res.columns if c not in cols_to_replace]
                cols_to_keep.append('building_id')
                up_res_na = up_res_na.select(cols_to_keep).join(
                    base_res.select(cols_to_replace), how='left', on='building_id'
                )

                # Sort the columns so concat will work
                up_res_na = up_res_na.select(sorted(up_res_na.columns))

                # Cast utility columns to float64 to avoid data type inconsistancies
                pattern_util_rate_name = re.compile(r'utility_bills.*_rate.*_name')
                pattern_util_cost = re.compile(r'utility_bills.*_rate.*_bill_dollars')
                for col, dt in up_res_na.schema.items():
                    if pattern_util_rate_name.match(col):
                        orig_dt = up_res_na.schema[col]
                        if not orig_dt == pl.Utf8:
                            up_res_na = up_res_na.with_columns([pl.col(col).cast(pl.Utf8)])
                            dt = up_res_na.schema[col]
                            logger.info(f'Cast {col} from {orig_dt} to {dt}')
                    elif pattern_util_cost.match(col):
                        orig_dt = up_res_na.schema[col]
                        if not orig_dt == pl.Float64:
                            up_res_na = up_res_na.with_columns([pl.col(col).cast(pl.Float64)])
                            dt = up_res_na.schema[col]
                            logger.info(f'Cast {col} from {orig_dt} to {dt}')

                results_dfs.append(up_res_na)

            # For buildings where the upgrade failed, add annual results columns from the Baseline run
            # The columns completed_status = "Fail" and apply_upgrade.applicable = FALSE enable identification later,
            # and any savings calculated for these runs will be zero because upgrade == baseline
            if up_res_fail.shape[0] > 0:
                shared_cols = [c for c in base_res.columns if c in up_res.columns]
                cols_to_leave_alone = [
                    'job_id',
                    'started_at',
                    'completed_at',
                    self.COMP_STATUS,
                    'apply_upgrade.applicable',
                    'apply_upgrade.upgrade_name',
                    self.UPGRADE_ID,
                    'apply_upgrade.reference_scenario',
                    self.upgrade_ids_to_skip
                ]
                cols_to_replace = [c for c in shared_cols if c not in cols_to_leave_alone]
                cols_to_keep = [c for c in base_res.columns if c not in cols_to_replace]
                cols_to_keep.append('building_id')
                up_res_fail = up_res_fail.select(cols_to_keep).join(
                    base_res.select(cols_to_replace), how='left', on='building_id'
                )
                # Set applicability to False and upgrade name because often blank for failed runs
                up_res_fail = up_res_fail.with_columns([pl.lit(False).alias('apply_upgrade.applicable')])
                up_res_fail = up_res_fail.with_columns([pl.lit(upgrade_name).alias('apply_upgrade.upgrade_name')])

                # Sort the columns so concat will work
                up_res_fail = up_res_fail.select(sorted(up_res_fail.columns))

                # Cast utility columns to float64 to avoid data type inconsistancies
                pattern_util_rate_name = re.compile(r'utility_bills.*_rate.*_name')
                pattern_util_cost = re.compile(r'utility_bills.*_rate.*_bill_dollars')
                for col, dt in up_res_fail.schema.items():
                    if pattern_util_rate_name.match(col):
                        orig_dt = up_res_fail.schema[col]
                        if not orig_dt == pl.Utf8:
                            up_res_fail = up_res_fail.with_columns([pl.col(col).cast(pl.Utf8)])
                            dt = up_res_fail.schema[col]
                            logger.info(f'Cast {col} from {orig_dt} to {dt}')
                    elif pattern_util_cost.match(col):
                        orig_dt = up_res_fail.schema[col]
                        if not orig_dt == pl.Float64:
                            up_res_fail = up_res_fail.with_columns([pl.col(col).cast(pl.Float64)])
                            dt = up_res_fail.schema[col]
                            logger.info(f'Cast {col} from {orig_dt} to {dt}')

                results_dfs.append(up_res_fail)

        # Gather schema data for debugging on failed concatenation
        results_df_schemas = {}
        for results_df in results_dfs:
            pattern_util_rate_name = re.compile(r'utility_bills.*_rate.*_name')
            pattern_util_cost = re.compile(r'utility_bills.*_rate.*_bill_dollars')
            for col, dt in results_df.schema.items():
                if col in results_df_schemas:
                    results_df_schemas[col].append(dt)
                else:
                    results_df_schemas[col] = [dt]

        # Check the schemas for inconsistent dtypes which prevent concatenation
        for col, dts in results_df_schemas.items():
            if len(set(dts)) > 1:
                vals = []
                for df in results_dfs:
                    vals += df.get_column(col).unique().to_list()
                err_msg = f'Column {col} is being read as multiple dtypes: {set(dts)} from values: {set(vals)}'
                logger.error(err_msg)
                raise Exception(err_msg)

        # Combine applicable, not applicable, and failed-replaced-with-baseline results from all upgrades
        self.data = pl.concat(results_dfs, how='diagonal')

        # Show the dataset size
        logger.debug(f'Memory after load_data: {self.data.estimated_size()}')

    def add_buildstock_csv_columns(self):
        # Add columns from the buildstock.csv

        # Find columns in the buildstock.csv columns marked for export in column definitions
        col_def_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pd.read_csv(col_def_path)
        col_defs = col_defs[(col_defs['location'] == 'buildstock.csv') & (col_defs['full_metadata'] == True)]
        col_def_names = col_defs['original_col_name'].tolist()

        # For backwards compatibility, add renamed columns here
        old_to_new = {
            # 'climate_zone_ashrae_2004': 'climate_zone_ashrae_2006'
        }
        for old, new in old_to_new.items():
            if new in col_def_names:
                col_def_names.append(old)

        # Read the buildstock.csv and join columns onto annual results by building ID
        buildstock_csv_path = os.path.join(self.data_dir, self.buildstock_file_name)
        headers = pd.read_csv(buildstock_csv_path, nrows=0).columns.tolist()
        if 'sample_building_id' in headers:
            col_def_names.append('sample_building_id')  # Older buildstockbatch versions, used for join only
        elif 'Building' in headers:
            col_def_names.append('Building')  # Newer buildstockbatch versions, used for join only

        cols_to_keep = []
        for c in col_def_names:
            if c in headers:
                cols_to_keep.append(c)
            else:
                logger.warning(f'Column {c} requested but not found in buildstock.csv, removing from col_def_names')

        buildstock = pl.read_csv(buildstock_csv_path, columns=cols_to_keep, infer_schema_length=50000)

        # For backwards compatibility
        buildstock = buildstock.rename({'Building': 'sample_building_id'})
        for old, new in old_to_new.items():
            if old in buildstock.columns:
                logger.info(f'Found old column name {old} from buildstock.csv and replacing it to {new}')
                buildstock = buildstock.rename({old: new})

        self.data = self.data.join(buildstock, left_on='building_id', right_on='sample_building_id', how='left')

        # Show the dataset size
        logger.debug(f'Memory after add_buildstock_csv_columns: {self.data.estimated_size()}')

    def add_geospatial_columns(self, input_lf: pl.LazyFrame, geography_to_join_on):
        supported_geogs = [self.TRACT_ID, self.COUNTY_ID, self.PUMA_ID, self.STATE_ABBRV]
        if geography_to_join_on not in supported_geogs:
            logger.info(f'Cannot add more geospatial columns based on {geography_to_join_on}')
            return input_lf

        # Read the column definitions
        col_def_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pd.read_csv(col_def_path)

        # Find all geospatial columns to join
        col_defs = col_defs[(col_defs['location'] == 'geospatial') & (col_defs['full_metadata'] == True)]
        col_def_names = col_defs['original_col_name'].tolist()

        file_path = os.path.join(self.truth_data_dir, self.geospatial_lookup_file_name)
        geospatial_data = pl.scan_csv(file_path, infer_schema_length=None)
        # TODO nhgis_county_gisjoin column should be added to the geospatial data file
        geospatial_data = geospatial_data.with_columns(
            pl.col('nhgis_county_gisjoin').cast(str).str.slice(0, 4).alias('nhgis_state_gisjoin')
        )
        geospatial_data = geospatial_data.select(col_def_names)
        geospatial_data = self.rename_geospatial_columns(geospatial_data)

        # Ran the following code once to find mappable columns.
        # Rerun this if geospatial mapping changes.
        # for key_col in [self.COUNTY_ID, self.PUMA_ID, self.STATE_ABBRV]:
        #     # Find all the unique geographic mappings available from this input
        #     mappable_cols = []
        #     for val_col in geospatial_data.columns:
        #         if val_col == key_col:
        #             continue
        #         # Downselect to the unique set of key-value pairs
        #         df = geospatial_data.select([key_col, val_col]).unique()
        #         has_one_to_one_mapping = True
        #         for k, vals in df.group_by([key_col]):
        #             if len(vals) > 1:
        #                 has_one_to_one_mapping = False
        #                 break
        #         if has_one_to_one_mapping:
        #             mappable_cols.append(val_col)
        #     print(f'Columns mappable from {key_col}:')
        #     print(mappable_cols)
        # exit()

        # Columns mappable from in.nhgis_county_gisjoin:
        county_mappings = [
            self.COUNTY_ID,  # include the column itself
            self.STATE_ABBRV,
            self.STATE_NAME,
            self.STATE_ID,
            self.CEN_DIV,
            self.CEN_REG,
            self.CZ_ASHRAE,
            'in.building_america_climate_zone',
            'in.iso_rto_region',
            'in.reeds_balancing_area',
            'in.cambium_grid_region',
        ]

        # Columns mappable from in.nhgis_puma_gisjoin:
        puma_mappings = [
            self.PUMA_ID,  # include the column itself
            self.STATE_ABBRV,
            self.STATE_NAME,
            self.STATE_ID,
            self.CEN_DIV,
            self.CEN_REG,
        ]

        # Columns mappable from in.state:
        state_mappings = [
            self.STATE_ABBRV, # include the column itself
            self.STATE_NAME,
            self.STATE_ID,
            self.CEN_DIV,
            self.CEN_REG,
        ]

        # Downselect to mappable columns before joining
        if geography_to_join_on == self.TRACT_ID:
            pass  # No column downselection needed
        elif geography_to_join_on == self.COUNTY_ID:
            geospatial_data = geospatial_data.select(county_mappings).unique()
        elif geography_to_join_on == self.PUMA_ID:
            geospatial_data = geospatial_data.select(puma_mappings).unique()
        elif geography_to_join_on == self.STATE_ABBRV:
            geospatial_data = geospatial_data.select(state_mappings).unique()

        # Join on the geospatial data
        input_lf = input_lf.join(geospatial_data, on=geography_to_join_on)

        return input_lf

    def add_ejscreen_columns(self, input_lf: pl.LazyFrame):
        # Add the EJ Screen data
        if not self.TRACT_ID in input_lf:
            logger.info((f'Because the {self.TRACT_ID} column is missing '
                'from the data, EJSCREEN characteristics cannot be joined.'))
            return input_lf

        # Read the column definitions
        col_def_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pd.read_csv(col_def_path)

        # Find all columns to join from EJSCREEN
        tract_col = 'ID'
        col_defs = col_defs[(col_defs['location'] == 'ejscreen') & (col_defs['full_metadata'] == True)]
        col_def_names = col_defs['original_col_name'].tolist()
        col_def_names.append('ID')  # Used for join only

        # Read the buildstock.csv and join columns onto annual results by building ID
        file_path = os.path.join(self.truth_data_dir, self.ejscreen_file_name)
        ejscreen = pl.scan_csv(file_path).select(col_def_names)
        ejscreen = ejscreen.with_columns([pl.col(tract_col).cast(pl.Utf8)])

        # Convert EJSCREEN census tract ID to gisjoin format
        ejscreen = ejscreen.with_columns((
                'G' +
                pl.col(tract_col).str.slice(0, length=2) +
                '0' +
                pl.col(tract_col).str.slice(2, length=3) +
                '0' +
                pl.col(tract_col).str.slice(5, length=6)
            ).alias(self.TRACT_ID))
        ejscreen = ejscreen.drop([tract_col])
        ejscreen = self.rename_geospatial_columns(ejscreen)

        # Merge in the EJSCREEN columns
        input_lf = input_lf.join(ejscreen, on=self.TRACT_ID, how='left')

        # Fill nulls in EJSCREEN columns with zeroes; not all tracts have an EJSCREEN mapping
        for c in ejscreen.columns:
            if c == self.TRACT_ID:
                continue
            input_lf = input_lf.with_columns([pl.col(c).fill_null(0.0)])

        assert isinstance(input_lf, pl.LazyFrame)

        return input_lf

    def add_cejst_columns(self, input_lf):
        # Add the CEJST data
        if not self.TRACT_ID in input_lf:
            logger.info((f'Because the {self.TRACT_ID} column is missing '
                'from the data, CEJST characteristics cannot be joined.'))
            return input_lf

        # Read the column definitions
        col_def_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pd.read_csv(col_def_path)

        # Find all columns to join from CEJST
        # Pull all cejst columns listed for export in the comstock column definition csv file
        tract_col = 'Census tract 2010 ID'
        col_defs = col_defs[(col_defs['location'] == 'cejst') & (col_defs['full_metadata'] == True)]
        col_def_names = col_defs['original_col_name'].tolist()
        col_def_names.append(tract_col)
        col_def_types = {}
        for c in col_def_names:
            col_def_types[c] = str

        # Read the buildstock.csv and join columns onto annual results by building ID
        file_path = os.path.join(self.truth_data_dir, self.cejst_file_name)
        cejst = pl.scan_csv(file_path).select(col_def_names)
        cejst = cejst.with_columns([pl.col(tract_col).cast(pl.Utf8)])

        # Convert CEJST census tract ID to gisjoin format
        cejst = cejst.with_columns((
                'G' +
                pl.col(tract_col).str.slice(0, length=2) +
                '0' +
                pl.col(tract_col).str.slice(2, length=3) +
                '0' +
                pl.col(tract_col).str.slice(5, length=6)
            ).alias(self.TRACT_ID))
        cejst = cejst.drop([tract_col])
        cejst = self.rename_geospatial_columns(cejst)

        # Merge in the CEJST columns
        input_lf = input_lf.join(cejst, on=self.TRACT_ID, how='left')

	    # Fill nulls in CEJST data with False (assume NOT disadvantaged)
        input_lf = input_lf.with_columns(pl.col(self.TRACT_ID).fill_null(False))

        assert isinstance(input_lf, pl.LazyFrame)

        return input_lf

    def add_addressable_segments_columns(self):
        hvac_group_map = {
            # Multizone CAV/VAV
            'Central Multi-zone VAV RTU_Boiler _ACC': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Boiler _DX': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Boiler _District': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Boiler _WCC': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_District_ACC': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_District_DX': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_District_District': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_District_WCC': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Electric Resistance_ACC': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Electric Resistance_DX': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Electric Resistance_District': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Electric Resistance_WCC': 'Multizone CAV/VAV',
            'Central Multi-zone VAV RTU_Furnace_DX': 'Multizone CAV/VAV',
            # Small Packaged Unit
            'Central Single-zone RTU_ASHP_ASHP': 'Small Packaged Unit',
            'Central Single-zone RTU_Boiler _DX': 'Small Packaged Unit',
            'Central Single-zone RTU_Boiler _Evaporative Cooling': 'Small Packaged Unit',
            'Central Single-zone RTU_District_DX': 'Small Packaged Unit',
            'Central Single-zone RTU_District_District': 'Small Packaged Unit',
            'Central Single-zone RTU_Electric Resistance_DX': 'Small Packaged Unit',
            'Central Single-zone RTU_Electric Resistance_District': 'Small Packaged Unit',
            'Central Single-zone RTU_Electric Resistance_Evaporative Cooling': 'Small Packaged Unit',
            'Central Single-zone RTU_Furnace_DX': 'Small Packaged Unit',
            'Central Single-zone RTU_Furnace_Evaporative Cooling': 'Small Packaged Unit',
            # Zone-by-Zone
            'DOAS+Zone terminal equipment_ASHP_ASHP': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_Boiler _ACC': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_Boiler _District': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_Boiler _WCC': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_District_ACC': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_District_District': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_District_WCC': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_Electric Resistance_ACC': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_Electric Resistance_District': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_Electric Resistance_WCC': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_GSHP_GSHP': 'Zone-by-Zone',
            'DOAS+Zone terminal equipment_WSHP_WSHP': 'Zone-by-Zone',
            'Zone terminal equipment_ASHP_ASHP': 'Zone-by-Zone',
            'Zone terminal equipment_Boiler _DX': 'Zone-by-Zone',
            'Zone terminal equipment_District_DX': 'Zone-by-Zone',
            'Zone terminal equipment_Electric Resistance_DX': 'Zone-by-Zone',
            'Zone terminal equipment_Furnace_DX': 'Zone-by-Zone',
            'Zone terminal equipment_Furnace_None': 'Zone-by-Zone',
            # Other HVAC
            'None_Boiler _None': 'Other HVAC',
            'None_Electric Resistance_None': 'Other HVAC',
            # Residential Style Central Systems
            'Residential forced air_Furnace_DX': 'Residential Style Central Systems',
            'Residential forced air_Furnace_None': 'Residential Style Central Systems'
            }

        self.data = self.data.with_columns((pl.col('in.hvac_combined_type').cast(pl.Utf8).replace(hvac_group_map, default=None)).alias('in.hvac_category'))

        # Define building type groups relevant to segmentation
        non_food_svc = ['RetailStandalone', 'Warehouse','SmallOffice', 'LargeHotel', 'MediumOffice', 'PrimarySchool',
            'Hospital', 'SmallHotel', 'Outpatient', 'SecondarySchool', 'LargeOffice']

        food_svc = ['QuickServiceRestaurant', 'FullServiceRestaurant']

        some_food_svc = ['RetailStripmall']

        non_lodging = ['QuickServiceRestaurant', 'RetailStripmall', 'RetailStandalone', 'Warehouse',
            'SmallOffice', 'MediumOffice', 'PrimarySchool',
            'FullServiceRestaurant', 'Hospital', 'Outpatient',
            'SecondarySchool', 'LargeOffice']

        lodging = ['SmallHotel', 'LargeHotel']

        # Cast columns used in is_in() statements below to match dtype of lists
        self.data = self.data.with_columns([
            pl.col('in.comstock_building_type').cast(pl.Utf8),
            pl.col('in.building_subtype').cast(pl.Utf8),
            pl.col('in.hvac_category').cast(pl.Utf8),
            pl.col('in.hvac_heat_type').cast(pl.Utf8)
        ])

        # Assign segment
        self.data = self.data.with_columns([
            # Segment A
            pl.when(
            (pl.col('in.comstock_building_type').is_in(non_food_svc)) &
            (pl.col('in.hvac_category') == 'Small Packaged Unit'))
            .then(pl.lit(self.SEG_A))
            # Segment A - includes strip malls with no food service
            .when(
            (pl.col('in.comstock_building_type').is_in(some_food_svc)) &
            (pl.col('in.hvac_category') == 'Small Packaged Unit') &
            (pl.col('in.building_subtype') == 'strip_mall_restaurant0'))
            .then(pl.lit(self.SEG_A))
            # Segment B
            .when(
            (pl.col('in.comstock_building_type').is_in(food_svc)) &
            (pl.col('in.hvac_category') == 'Small Packaged Unit'))
            .then(pl.lit(self.SEG_B))
            # Segment C - strip malls with SOME food service
            .when(
            (pl.col('in.comstock_building_type').is_in(some_food_svc)) &
            (pl.col('in.hvac_category') == 'Small Packaged Unit') &
            (pl.col('in.building_subtype') != 'strip_mall_restaurant0'))
            .then(pl.lit(self.SEG_C))
            # Segment D
            # NOTE see the space after Boiler... this is an artifact of previous code!
            .when(
            (pl.col('in.hvac_heat_type').is_in(['Boiler ', 'District'])) &
            (pl.col('in.hvac_category') == 'Multizone CAV/VAV'))
            .then(pl.lit(self.SEG_D))
            # Segment E
            .when(
            (pl.col('in.comstock_building_type').is_in(lodging)) &
            (pl.col('in.hvac_category') == 'Zone-by-Zone'))
            .then(pl.lit(self.SEG_E))
            # Segment F
            .when(
            (pl.col('in.hvac_heat_type') == 'Electric Resistance') &
            (pl.col('in.hvac_category') == 'Multizone CAV/VAV'))
            .then(pl.lit(self.SEG_F))
            # Segment G
            .when(
            (pl.col('in.hvac_heat_type') == 'Furnace') &
            (pl.col('in.hvac_category') == 'Multizone CAV/VAV'))
            .then(pl.lit(self.SEG_G))
            # Segment H
            .when(
            (pl.col('in.hvac_category') == 'Residential Style Central Systems'))
            .then(pl.lit(self.SEG_H))
            # Segment I
            .when(
            (pl.col('in.comstock_building_type').is_in(non_lodging)) &
            (pl.col('in.hvac_category') == 'Zone-by-Zone'))
            .then(pl.lit(self.SEG_I))
            # Segment J
            .when(
            (pl.col('in.hvac_category') == 'Other HVAC'))
            .then(pl.lit(self.SEG_J))
            # Catchall - should not hit this, every building should have a segment
            .otherwise(pl.lit('ERROR'))
            # Assign the column name
            .alias(self.SEG_NAME)
        ])

        # Check that no rows have a segment "ERROR" assigned
        errs = self.data.select((pl.col(self.SEG_NAME).filter(pl.col(self.SEG_NAME) == 'ERROR').count()))
        num_errs = errs.get_column(self.SEG_NAME).sum()
        if num_errs > 0:
            raise Exception(f'Errors in assigning addressable segments to {num_errs} buildings, fix logic.')

    def add_enduse_group_columns(self):
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HVAC_ENERGY).alias(self.ANN_HVAC_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_LTG_ELEC_ENDUSE).alias(self.ANN_LTG_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_INTEQUIP_ENERGY).alias(self.ANN_INTEQUIP_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_REFRIG_ELEC_ENDUSE).alias(self.ANN_REFRIG_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_SWH_ENERGY).alias(self.ANN_SWH_GROUP_KBTU))

        self.convert_units(self.COLS_ENDUSE_GROUP_ANN_ENGY)

    def add_enduse_fuel_group_columns(self):
        # HVAC columns
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HVAC_ELEC_ENDUSE).alias(self.ANN_ELEC_HVAC_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HVAC_GAS_ENDUSE).alias(self.ANN_GAS_HVAC_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HVAC_DISTHTG_ENDUSE).alias(self.ANN_DISTHTG_HVAC_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HVAC_DISTCLG_ENDUSE).alias(self.ANN_DISTCLG_HVAC_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HVAC_OTHER_ENDUSE).alias(self.ANN_OTHER_HVAC_GROUP_KBTU))

        # Lighting column
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_LTG_ELEC_ENDUSE).alias(self.ANN_ELEC_LTG_GROUP_KBTU))

        # Interior equipment columns
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_INTEQUIP_ELEC_ENDUSE).alias(self.ANN_ELEC_INTEQUIP_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_INTEQUIP_GAS_ENDUSE).alias(self.ANN_GAS_INTEQUIP_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_INTEQUIP_DISTHTG_ENDUSE).alias(self.ANN_DISTHTG_INTEQUIP_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_INTEQUIP_OTHER_ENDUSE).alias(self.ANN_OTHER_INTEQUIP_GROUP_KBTU))

        # Refrigeration columns
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_REFRIG_ELEC_ENDUSE).alias(self.ANN_ELEC_REFRIG_GROUP_KBTU))

        # SWH columns
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_SWH_ELEC_ENDUSE).alias(self.ANN_ELEC_SWH_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_SWH_GAS_ENDUSE).alias(self.ANN_GAS_SWH_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_SWH_DISTHTG_ENDUSE).alias(self.ANN_DISTHTG_SWH_GROUP_KBTU))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_SWH_OTHER_ENDUSE).alias(self.ANN_OTHER_SWH_GROUP_KBTU))

        col_names = [
            self.ANN_ELEC_HVAC_GROUP_KBTU,
            self.ANN_GAS_HVAC_GROUP_KBTU,
            self.ANN_DISTHTG_HVAC_GROUP_KBTU,
            self.ANN_DISTCLG_HVAC_GROUP_KBTU,
            self.ANN_OTHER_HVAC_GROUP_KBTU,
            self.ANN_ELEC_LTG_GROUP_KBTU,
            self.ANN_ELEC_INTEQUIP_GROUP_KBTU,
            self.ANN_DISTHTG_INTEQUIP_GROUP_KBTU,
            self.ANN_OTHER_INTEQUIP_GROUP_KBTU,
            self.ANN_GAS_INTEQUIP_GROUP_KBTU,
            self.ANN_ELEC_REFRIG_GROUP_KBTU,
            self.ANN_ELEC_SWH_GROUP_KBTU,
            self.ANN_GAS_SWH_GROUP_KBTU,
            self.ANN_DISTHTG_SWH_GROUP_KBTU,
            self.ANN_OTHER_SWH_GROUP_KBTU
        ]

        self.convert_units(col_names)

    def downselect_imported_columns(self, df):
        # Downselect to the columns marked for export in column definitions
        logger.debug(f'Memory before downselect_columns: {df.estimated_size()}')
        col_defs_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pl.scan_csv(col_defs_path)
        col_def_names = col_defs.filter(
            (pl.col('full_metadata') == True) &
            (~pl.col('location').is_in(['calculated', 'geospatial', 'cejst', 'ejscreen']))
        )
        col_def_names = col_def_names.select('original_col_name').collect()
        col_def_names = col_def_names.to_series().to_list()

        # Handle missing columns
        cols_to_keep = []
        cols_missing = []
        for c in col_def_names:
            if c in df:
                cols_to_keep.append(c)
            else:
                cols_missing.append(c)

        if len(cols_missing) > 0 and not self.skip_missing_columns:
            logger.error(f'Columns requested for export in {COLUMN_DEFINITION_FILE_NAME} but not found in data:')
            for c in cols_missing:
                logger.error(f'Column "{c}" was requested but not found in data')
            raise Exception(f'Columns missing, see ERRORs above. Set "skip_missing_columns=True" to ignore missing columns.')

        # Check all available columns
        col_defs = pl.scan_csv(col_defs_path)
        col_def_names = col_defs.filter(~pl.col('location').is_in(['calculated', 'geospatial', 'cejst', 'ejscreen']))
        col_def_names = col_def_names.select('original_col_name').collect()
        col_def_names = col_def_names.to_series().to_list()
        for c in df.columns:
            if c not in col_def_names:
                if re.match(r'simulation_output_report\.apply_upgrade_.*_applicable', c):
                    # Add the measure-within-upgrade applicability columns,
                    # whose names are based on the measures included and therefore
                    # cannot be specified in the column definitions
                    if self.include_upgrades:
                        cols_to_keep.append(c)
                else:
                    # Report columns available in the data but not listed in the column definitions
                    logger.debug(f'Column {c} is available but was not listed in in {COLUMN_DEFINITION_FILE_NAME}')

        # df = df[cols_to_keep]
        df = df.select(cols_to_keep)

        logger.debug(f'Memory after downselect_columns: {df.estimated_size()}')

        return df

    def downselect_columns_for_metadata_export(self, input_lf, data_type='full'):
        # Find columns marked for export in column definitions
        if data_type not in ['detailed', 'full', 'basic']:
            raise RuntimeError('Unsupported data_type input to downselect_columns_for_metadata_export')

        # If 'detailed' is used, do no downselection
        if data_type == 'detailed':
            return input_lf

        col_defs = pl.read_csv(os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME))
        export_cols = col_defs.filter(pl.col(f'{data_type}_metadata') == True).select(['new_col_name', 'new_units'])
        export_cols = export_cols.unique()

        all_cols = col_defs.select('new_col_name').to_series().to_list()
        for c in input_lf.columns:
            c = c.split('..')[0]  # column name without units
            if c.startswith('applicability.'):
                continue  # measure-within-upgrade applicability column names are dynamic, don't check
            if c not in all_cols:
                logger.warning(f'No entry for {c} in {COLUMN_DEFINITION_FILE_NAME}')

        # Check for missing columns
        cols_to_keep = []
        cols_missing = []
        for export_col_name, export_col_units in export_cols.iter_rows():
            expected_unitless_cols = [self.FLR_AREA, self.col_name_to_weighted(self.FLR_AREA)]
            if (export_col_units is None) or (export_col_name in expected_unitless_cols):
                export_col_name_units = export_col_name
            else:
                export_col_name_units = f'{export_col_name}..{export_col_units}'

            if export_col_name_units in input_lf.columns:
                cols_to_keep.append(export_col_name_units)
            else:
                if export_col_name_units in self.COLS_GEOG:
                    # Some geography columns will be missing from aggregate files.
                    # This is expected, do not count as a missing column.
                    pass
                else:
                    cols_missing.append(export_col_name_units)

        if len(cols_missing) > 0:
            logger.error(f'Columns requested for export in {COLUMN_DEFINITION_FILE_NAME} but not found in data:')
            for c in cols_missing:
                logger.error(f'Missing "{c}" in data')

        cols_to_keep = list(set(cols_to_keep))

        input_lf = input_lf.select(cols_to_keep)

        return input_lf


    def reorder_data_columns(self, input_df):
        # Reorder columns for easier comprehension

        # These columns are required for SightGlass and should be at the front of the data
        special_cols = [
            self.BLDG_ID,
            self.UPGRADE_ID,
            self.BLDG_WEIGHT,
            self.FLR_AREA,
            self.col_name_to_weighted(self.FLR_AREA),
            self.UPGRADE_NAME,
            self.UPGRADE_APPL
        ]
        front_cols = [c for c in special_cols if c in input_df.columns]

        # These columns may or may not be present depending on the run
        for opt_col in [self.COMP_STATUS, self.DATASET]:
            if opt_col in input_df.columns:
                front_cols.append(opt_col)

        def diff_lists(li1, li2):
            li_dif = [i for i in li1 + li2 if (i not in li1) or (i not in li2)]
            return li_dif

        oth_cols = diff_lists(input_df.columns, front_cols)
        oth_cols.sort()

        # Lists of columns
        applicability = []
        geogs = []
        ins = []
        out_engy_cons_svgs = []
        out_peak = []
        out_intensity = []
        out_emissions = []
        out_utility = []
        out_qoi = []
        out_params = []
        calc = []

        for c in oth_cols:
            if c.startswith('applicability.'):
                applicability.append(c)
            elif c in self.COLS_GEOG:
                geogs.append(c)
            elif c.startswith('in.'):
                ins.append(c)
            elif c.startswith('out.qoi.'):
                out_qoi.append(c)
            elif c.startswith('out.emissions.'):
                out_emissions.append(c)
            elif c.startswith('out.utility_bills.'):
                out_utility.append(c)
            elif c.startswith('out.params.'):
                out_params.append(c)
            elif c.startswith('calc.'):
                calc.append(c)
            elif (c.endswith('.energy_consumption')
                  or c.endswith('.energy_consumption..kwh')
                  or c.endswith('.energy_savings')
                  or c.endswith('.energy_savings..kwh')):
                out_engy_cons_svgs.append(c)
            elif (c.endswith('peak_demand') or c.endswith('peak_demand..kw')):
                out_peak.append(c)
            elif (c.endswith('.energy_consumption_intensity')
                  or c.endswith('.energy_consumption_intensity..kwh_per_ft2')
                  or c.endswith('.energy_savings_intensity')
                  or c.endswith('.energy_savings_intensity..kwh_per_ft2')):
                out_intensity.append(c)
            else:
                logger.error(f'Didnt find an order for column: {c}')

        sorted_cols = front_cols + applicability + geogs + ins + out_engy_cons_svgs + out_peak + out_intensity + out_qoi + out_emissions + out_utility + out_params + calc

        input_df = input_df.select(sorted_cols)

        return input_df

    def rename_columns_and_convert_units(self):
        # Rename columns per comstock_column_definitions.csv

        # Read the column definitions
        col_defs = pl.read_csv(os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME))
        col_defs = col_defs.filter((pl.col('full_metadata') == True) &
                                   (~pl.col('location').is_in(['calculated', 'geospatial', 'cejst', 'ejscreen'])))
        for col_def in col_defs.iter_rows(named=True):
            orig_name = col_def['original_col_name']
            new_name = col_def['new_col_name']
            if pd.isna(new_name):
                err_msg = f'Requested export of column {orig_name}, but no new name was specified'
                logger.error(err_msg)
                raise Exception(err_msg)

            logger.debug(f"Processing {orig_name}")

            # Skip missing columns if specified
            if self.skip_missing_columns:
                if not orig_name in self.data.columns:
                    # if 'utility_bills.' in orig_name:
                    #     continue
                    logger.warning(f'Column {orig_name} was requested as an input but not found in data, skipping')
                    continue

            # Check for unit conversion
            orig_units = col_def['original_units']
            new_units = col_def['new_units']
            if pd.isna(orig_units):
                logger.debug('-- Unitless, no unit conversion necessary')
            elif orig_units == new_units:
                logger.debug(f"-- Keeping original units {orig_units}")
            else:
                # Convert the column
                cf = self.conv_fact(orig_units, new_units)
                self.data = self.data.with_columns([(pl.col(orig_name) * cf)])
                logger.debug(f"-- Converted units from {orig_units} to {new_units} by multiplying by {cf}")

            # Append new units to column name, using .. separator for easier parsing
            if not pd.isna(orig_units):
                new_name = f'{new_name}..{new_units}'

            # Rename the column
            logger.debug(f'-- New name = {new_name}')
            self.data = self.data.rename({orig_name: new_name})

        # Rename the measure-within-upgrade applicability columns
        if self.include_upgrades:
            for orig_name in self.data.columns:
                if re.match(r'simulation_output_report\.apply_upgrade_.*_applicable', orig_name):
                    # Rename the column
                    new_name = orig_name.replace('simulation_output_report.apply_upgrade_', 'applicability.')
                    new_name = new_name.replace('_applicable', '')
                    logger.debug(f'-- New name = {new_name}')
                    self.data = self.data.rename({orig_name: new_name})

        # Rename the upgrades if specified
        if self.rename_upgrades:
            rename_upgrades_path = os.path.join(self.data_dir, self.rename_upgrades_file_name)
            if not os.path.exists(rename_upgrades_path):
                raise FileNotFoundError(
                f'Missing {rename_upgrades_path}. Either set rename_upgrades=False or add json with "old_name": "new_name" pairs.')
            with open(rename_upgrades_path, "r") as f:
                upgrade2upgrade = json.load(f)
                logger.debug(f'Renaming upgrades')
                for old, new in upgrade2upgrade.items():
                    logger.debug(f'{old} -> {new}')
                self.data = self.data.with_columns((pl.col(self.UPGRADE_NAME).replace(upgrade2upgrade, default=None)).alias(self.UPGRADE_NAME))
                self.data = self.data.with_columns(pl.col(self.UPGRADE_NAME))

        logger.debug(f'Memory after rename_columns_and_convert_units: {self.data.estimated_size()}')

    def rename_geospatial_columns(self, input_lf):
        # Rename columns per comstock_column_definitions.csv
        # TODO combine this with rename_columns_and_convert_units()

        # Read the column definitions
        col_defs = pl.read_csv(os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME))
        col_defs = col_defs.filter(
            (pl.col('full_metadata') == True) &
            (pl.col('location').is_in(['geospatial', 'cejst', 'ejscreen'])))
        input_lf_cols = input_lf.columns
        for col_def in col_defs.iter_rows(named=True):
            orig_name = col_def['original_col_name']
            new_name = col_def['new_col_name']
            orig_units = col_def['original_units']
            new_units = col_def['new_units']

            # Find the name with units
            new_name_with_units = new_name
            if not pd.isna(orig_units):
                new_name_with_units = f'{new_name}..{new_units}'

            # Skip already-renamed columns
            if new_name_with_units in input_lf_cols:
                logger.debug(f'Already renamed {new_name_with_units}')
                continue

            # Skip columns that don't exist
            if not orig_name in input_lf_cols:
                continue

            if pd.isna(new_name):
                err_msg = f'Requested export of column {orig_name}, but no new name was specified'
                logger.error(err_msg)
                raise Exception(err_msg)

            logger.debug(f"Processing {orig_name}")

            # Check for unit conversion
            new_units = col_def['new_units']
            if pd.isna(orig_units):
                logger.debug('-- Unitless, no unit conversion necessary')
            elif orig_units == new_units:
                logger.debug(f"-- Keeping original units {orig_units}")
            else:
                # Convert the column
                cf = self.conv_fact(orig_units, new_units)
                input_lf = input_lf.with_columns([(pl.col(orig_name) * cf)])
                logger.debug(f"-- Converted units from {orig_units} to {new_units} by multiplying by {cf}")

            # Append new units to column name, using .. separator for easier parsing
            if not pd.isna(orig_units):
                new_name = f'{new_name}..{new_units}'

            # Rename the column
            logger.debug(f'-- {orig_name} -> {new_name}')
            input_lf = input_lf.rename({orig_name: new_name})

        assert isinstance(input_lf, pl.LazyFrame)
        return input_lf

    def set_column_data_types(self):
        # Set dtypes for some columns

        # Upgrade ID must be Athena bigint (np.int64)
        self.data = self.data.with_columns(pl.col(self.UPGRADE_ID).cast(pl.Int64))

        # TODO base list of columns to convert on column dictionary CSV?
        for col in (self.COLS_TOT_ANN_ENGY + [self.FLR_AREA]):
            self.data = self.data.with_columns(pl.col(col).cast(pl.Float64))

        # No in.foo column may be a bigint because python cannot serialize bigints to JSON
        # when determining unique in.foo values for SightGlass filters.
        self.data = self.data.with_columns(pl.col(self.YEAR_BUILT).cast(pl.Utf8))

    def add_missing_energy_columns(self):
        # Put in zeroes for end-use columns that aren't used in ComStock yet
        for engy_col in (self.COLS_TOT_ANN_ENGY + self.COLS_ENDUSE_ANN_ENGY):
            if not engy_col in self.data:
                logger.debug(f'Adding missing energy column: {engy_col}')
                self.data = self.data.with_columns([
                    pl.lit(0.0).alias(engy_col)
                ])

    def add_enduse_total_energy_columns(self):
        # Create columns for all energy across fuels for heating and cooling

        # Heating
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_HEAT_ENDUSE).alias(self.ANN_HEAT_GROUP_KBTU))

        # Cooling
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_COOL_ENDUSE).alias(self.ANN_COOL_GROUP_KBTU))

    def add_energy_intensity_columns(self):
        # Create EUI column for each annual energy column
        for engy_col in (self.COLS_TOT_ANN_ENGY + self.COLS_ENDUSE_ANN_ENGY):
            # Divide energy by area to create intensity
            eui_col = self.col_name_to_eui(engy_col)
            self.data = self.data.with_columns(
                (pl.col(engy_col) / pl.col(self.FLR_AREA)).alias(eui_col))

    def add_bill_intensity_columns(self):
        # Create bill per area column for each annual utility bill column
        for bill_col in self.COLS_UTIL_BILLS + [
                                                self.UTIL_BILL_TOTAL_MEAN,
                                                self.UTIL_BILL_ELEC_MAX,
                                                self.UTIL_BILL_ELEC_MED,
                                                self.UTIL_BILL_ELEC_MIN]:
            # Put in np.nan for bill columns that aren't part of ComStock
            if not bill_col in self.data:
                self.data = self.data.with_columns([pl.lit(None).alias(bill_col)])

            # Divide bill by area to create intensity
            per_area_col = self.col_name_to_area_intensity(bill_col)
            self.data = self.data.with_columns(
                (pl.col(bill_col) / pl.col(self.FLR_AREA)).alias(per_area_col))

    def add_energy_rate_columns(self):
        # Create energy rate column for each annual utility bill column
        for bill_col in self.COLS_UTIL_BILLS:
            # Get the corresponding energy consumption column
            bill_to_engy_col = {
                self.UTIL_BILL_ELEC: self.ANN_TOT_ELEC_KBTU,
                self.UTIL_BILL_GAS: self.ANN_TOT_GAS_KBTU,
                self.UTIL_BILL_FUEL_OIL: None,
                self.UTIL_BILL_PROPANE: None
            }
            # Only create rate columns for fuels with bills and annual consumption
            engy_col = bill_to_engy_col[bill_col]
            if not engy_col:
                continue
            # Divide bill by consumption to create rate
            rate_col = self.col_name_to_energy_rate(bill_col)
            self.data = self.data.with_columns(
                (pl.col(bill_col) / pl.col(engy_col)).alias(rate_col))

    def add_normalized_qoi_columns(self):
        dict_cols = []

        dict_cols_max = {self.QOI_MAX_SHOULDER_USE_NORMALIZED:self.QOI_MAX_SHOULDER_USE,
        self.QOI_MAX_SUMMER_USE_NORMALIZED:self.QOI_MAX_SUMMER_USE,
        self.QOI_MAX_WINTER_USE_NORMALIZED:self.QOI_MAX_WINTER_USE}
        dict_cols.append(dict_cols_max)

        dict_cols_min = {self.QOI_MIN_SHOULDER_USE_NORMALIZED:self.QOI_MIN_SHOULDER_USE,
        self.QOI_MIN_SUMMER_USE_NORMALIZED:self.QOI_MIN_SUMMER_USE,
        self.QOI_MIN_WINTER_USE_NORMALIZED:self.QOI_MIN_WINTER_USE}
        dict_cols.append(dict_cols_min)

        for dict in dict_cols:
            for new,orig in dict.items():
                # Create QOI columns normalized by square footage
                # self.data[new] = (self.data[orig] / self.data[self.FLR_AREA]) * 1000
                self.data = self.data.with_columns(
                    (pl.col(orig) / pl.col(self.FLR_AREA) * 1000).alias(new))

    def add_peak_intensity_columns(self):
        # Create peak per area column for each peak column
        for peak_col in (self.COLS_QOI_MONTHLY_MAX_DAILY_PEAK + self.COLS_QOI_MONTHLY_MED_DAILY_PEAK + [
            self.QOI_MAX_SHOULDER_USE,
            self.QOI_MAX_SUMMER_USE,
            self.QOI_MAX_WINTER_USE
            ]):
            # Divide peak by area to create intensity
            per_area_col = self.col_name_to_area_intensity(peak_col)
            self.data = self.data.with_columns(
                (pl.col(peak_col) / pl.col(self.FLR_AREA)).alias(per_area_col))

    def add_emissions_intensity_columns(self):
        # Create emissions per area column for each emissions column
        for emissions_col in (self.COLS_GHG_ELEC_SEASONAL_DAILY_EGRID + self.COLS_GHG_ELEC_SEASONAL_DAILY_CAMBIUM + [
            self.GHG_LRMER_MID_CASE_15_ELEC,
            self.GHG_ELEC_EGRID,
            self.ANN_GHG_EGRID,
            self.ANN_GHG_CAMBIUM
            ]):
            # Divide emissions by area to create intensity
            per_area_col = self.col_name_to_area_intensity(emissions_col)
            self.data = self.data.with_columns(
                (pl.col(emissions_col) / pl.col(self.FLR_AREA)).alias(per_area_col))

    def add_aeo_nems_building_type_column(self):
        # Add the AEO and NEMS building type for each row of CBECS

        # Load the building type mapping file
        file_path = os.path.join(RESOURCE_DIR, self.building_type_mapping_file_name)
        bldg_type_map = pd.read_csv(file_path, index_col='ComStock Intermediate Building Type')

        @lru_cache()
        def comstock_to_aeo_bldg_type(cstock_bldg_type, sqft, bldg_type_map):
            # Get the CBECS properties
            if 'Office' in cstock_bldg_type:
                # Office type is based on size
                if sqft <= 50_000:
                    aeo_bldg_type = 'Office - Small'
                else:
                    aeo_bldg_type = 'Office - Large'
            else:
                # Other building types are direct mappings
                aeo_bldg_type = bldg_type_map['NEMS and AEO Intermediate Building Type'].loc[cstock_bldg_type][0]
            return aeo_bldg_type

        # self.data[self.AEO_BLDG_TYPE] = self.data.apply(lambda row: comstock_to_aeo_bldg_type(row, bldg_type_map), axis=1)
        self.data = self.data.with_columns(
            self.data.select([self.BLDG_TYPE, self.FLR_AREA]).apply(lambda x: comstock_to_aeo_bldg_type(x[0], x[1], bldg_type_map)).alias(self.AEO_BLDG_TYPE)
        )

        # self.data[self.AEO_BLDG_TYPE] = self.data[self.AEO_BLDG_TYPE].astype('category')
        self.data = self.data.with_columns(pl.col(self.AEO_BLDG_TYPE))

    def add_vintage_column(self):
    # Adds decadal vintage bins used in CBECS 2018

        def vintage_bin_from_year(year):
            year = int(year)
            if year < 1946:
                vint = 'Before 1946'
            elif year < 1960:
                vint = '1946 to 1959'
            elif year < 1970:
                vint = '1960 to 1969'
            elif year < 1980:
                vint = '1970 to 1979'
            elif year < 1990:
                vint = '1980 to 1989'
            elif year < 2000:
                vint = '1990 to 1999'
            elif year < 2013:
                vint = '2000 to 2012'
            elif year < 2019:
                vint = '2013 to 2018'
            else:
                vint = '2019 or newer'
            return vint

        # self.data[self.VINTAGE] = self.data.apply(lambda row: vintage_bin_from_year(row[]), axis=1)
        self.data = self.data.with_columns(
            pl.col(self.YEAR_BUILT).map_elements(lambda x: vintage_bin_from_year(x), return_dtype=pl.Utf8).alias(self.VINTAGE),
        )
        self.data = self.data.with_columns(pl.col(self.VINTAGE))

    def add_floor_area_category_column(self):
    # Adds floor area bins used in CBECS 2018

        def floor_area_bin_from_area(sqft):
            if sqft <= 5_000:
                bin = '1,001 to 5,000 square feet'
            elif sqft <= 10_000:
                bin = '5,001 to 10,000 square feet'
            elif sqft <= 25_000:
                bin = '10,001 to 25,000 square feet'
            elif sqft <= 50_000:
                bin = '25,001 to 50,000 square feet'
            elif sqft <= 100_000:
                bin = '50,001 to 100,000 square feet'
            elif sqft <= 200_000:
                bin = '100,001 to 200,000 square feet'
            elif sqft <= 500_000:
                bin = '200,001 to 500,000 square feet'
            elif sqft <= 1_000_000:
                bin = '500,001 to 1 million square feet'
            else:
                bin = 'Over 1 million square feet'
            return bin

        self.data = self.data.with_columns(
            pl.col(self.FLR_AREA).apply(lambda x: floor_area_bin_from_area(x)).alias(self.FLR_AREA_CAT),
        )
        self.data = self.data.with_columns(pl.col(self.FLR_AREA))

    def add_dataset_column(self):
        self.data = self.data.with_columns([
            pl.lit(self.dataset_name).alias(self.DATASET)
        ])
        self.data = self.data.with_columns(pl.col(self.DATASET))

    def add_upgrade_building_id_column(self):
    # Adds column that combines building ID and upgrade ID for easier joins of wide and long data

        def combine_building_upgrade_id(row):
            return np.int64(f'{row[self.BLDG_ID]}{row[self.UPGRADE_ID]}')

        self.data[self.BLDG_UP_ID] = self.data.apply(lambda row: combine_building_upgrade_id(row), axis=1)

    def add_hvac_metadata(self):
        # Read the HVAC metadata
        hvac_metadata_path = os.path.join(RESOURCE_DIR, self.hvac_metadata_file_name)
        hvac = pd.read_csv(hvac_metadata_path, na_filter=False)

        # add column for ventilation
        dict_vent = dict(zip(hvac['system_type'], hvac['ventilation_type']))
        self.data = self.data.with_columns((pl.col('in.hvac_system_type').cast(pl.Utf8).replace(dict_vent, default=None)).alias('in.hvac_vent_type'))
        self.data = self.data.with_columns(pl.col('in.hvac_vent_type'))

        # add column for heating
        dict_heat = dict(zip(hvac['system_type'], hvac['primary_heating']))
        self.data = self.data.with_columns((pl.col('in.hvac_system_type').cast(pl.Utf8).replace(dict_heat, default=None)).alias('in.hvac_heat_type'))
        self.data = self.data.with_columns(pl.col('in.hvac_heat_type'))

        # add column for cooling
        dict_cool = dict(zip(hvac['system_type'], hvac['primary_cooling']))
        self.data = self.data.with_columns((pl.col('in.hvac_system_type').cast(pl.Utf8).replace(dict_cool, default=None)).alias('in.hvac_cool_type'))
        self.data = self.data.with_columns(pl.col('in.hvac_cool_type'))

        # hvac combined
        self.data = self.data.with_columns(pl.concat_str(['in.hvac_vent_type', 'in.hvac_heat_type', 'in.hvac_cool_type'], separator='_').alias('in.hvac_combined_type'))

    def add_building_type_group(self):
        # Add a building type group

        bldg_type_groups = {
            'FullServiceRestaurant': 'Food Service',
            'QuickServiceRestaurant': 'Food Service',
            'RetailStripmall': 'Mercantile',
            'RetailStandalone': 'Mercantile',
            'SmallOffice': 'Office',
            'MediumOffice': 'Office',
            'LargeOffice': 'Office',
            'PrimarySchool': 'Education',
            'SecondarySchool': 'Education',
            'Outpatient': 'Healthcare',
            'Hospital': 'Healthcare',
            'SmallHotel': 'Lodging',
            'LargeHotel': 'Lodging',
            'Warehouse': 'Warehouse and Storage',
        }

        self.data = self.data.with_columns((pl.col(self.BLDG_TYPE).cast(pl.Utf8).replace(bldg_type_groups, default=None)).alias(self.BLDG_TYPE_GROUP))
        self.data = self.data.with_columns(pl.col(self.BLDG_TYPE_GROUP))

    def add_national_scaling_weights(self, cbecs: CBECS, remove_non_comstock_bldg_types_from_cbecs: bool):
        # Remove CBECS entries for building types not included in the ComStock run
        # comstock_bldg_types = self.data[self.BLDG_TYPE].unique()
        # assert "calc.weighted.utility_bills.total_mean_bill..billion_usd" in self.data.columns
        assert isinstance(self.data, pl.LazyFrame)
        comstock_bldg_types: set = set(self.data.select(self.BLDG_TYPE).unique().collect().to_pandas()[self.BLDG_TYPE].tolist())

        cbecs.data: pd.DataFrame = cbecs.data.collect().to_pandas()
        assert isinstance(cbecs.data, pd.DataFrame)
        bldg_types_to_keep = [] #if the bldg types in both CBECS and ComStock, keep them.
        for bt in cbecs.data[self.BLDG_TYPE].unique():
            if bt in comstock_bldg_types:
                bldg_types_to_keep.append(bt)

        logger.debug("Building types to keep: ", bldg_types_to_keep)
        if remove_non_comstock_bldg_types_from_cbecs:
            # Modify CBECS to remove building types not covered by ComStock
            cbecs.data = cbecs.data[cbecs.data[self.BLDG_TYPE].isin(bldg_types_to_keep)]
            cbecsData = cbecs.data.copy(deep=True)
        else:
            # Make a copy of CBECS, leaving the original unchanged
            cbecsData = cbecs.data[cbecs.data[self.BLDG_TYPE].isin(bldg_types_to_keep)].copy(deep=True)

        # Calculate scaling factors used to scale ComStock results to CBECS square footages
        # Only includes successful ComStock simulations, so the failure rate will
        # change scaling factors between ComStock runs depending on which models failed.

        # Total sqft of each building type, CBECS
        wt_area_col = self.col_name_to_weighted(self.FLR_AREA)
        cbecsData[wt_area_col] = cbecsData[wt_area_col].astype(float)
        cbecs_bldg_type_sqft = cbecsData[[wt_area_col, self.BLDG_TYPE]].groupby([self.BLDG_TYPE]).sum()
        # logger.debug(f"cbecs_bldg_type_sqft: {cbecsData[[wt_area_col, self.BLDG_TYPE]]}")
        logger.debug('CBECS floor area by building type')
        logger.debug(cbecs_bldg_type_sqft)

        # Total sqft of each building type, ComStock
        if self.APPORTIONED:
            # Since this is a national calculation, groupby on building id and upgrade only in foreign key table
            national_agg = self.fkt.clone()
            national_agg = national_agg.select([pl.col(self.BLDG_WEIGHT), pl.col(self.BLDG_ID)]).groupby(pl.col(self.BLDG_ID)).sum()
            cs_data = self.data.filter(pl.col(self.UPGRADE_NAME) == self.BASE_NAME).select([pl.col(self.BLDG_ID), pl.col(self.FLR_AREA), pl.col(self.BLDG_TYPE)]).clone()
            national_agg = national_agg.join(cs_data, on=pl.col(self.BLDG_ID))
            national_agg = national_agg.with_columns((pl.col(self.BLDG_WEIGHT) * pl.col(self.FLR_AREA)).alias(self.FLR_AREA))
            national_agg = national_agg.select([pl.col(self.BLDG_TYPE), pl.col(self.FLR_AREA)]).groupby(pl.col(self.BLDG_TYPE)).sum().collect()
            comstock_bldg_type_sqft: pd.DataFrame = national_agg.to_pandas().set_index(self.BLDG_TYPE)
        else:
            baseline_data: pl.LazyFrame = self.data.filter(pl.col(self.UPGRADE_NAME) == self.BASE_NAME).clone()
            comstock_bldg_type_sqft: pl.DataFrame = baseline_data.group_by(self.BLDG_TYPE).agg([pl.col(self.FLR_AREA).sum()]).collect()
            comstock_bldg_type_sqft: pd.DataFrame = comstock_bldg_type_sqft.to_pandas().set_index(self.BLDG_TYPE)
        logger.debug('ComStock Baseline floor area by building type')
        logger.debug(comstock_bldg_type_sqft)

        # Calculate scaling factor for each building type based on floor area (not building/model count)
        sf = pd.concat([cbecs_bldg_type_sqft, comstock_bldg_type_sqft], axis = 1)
        sf[self.BLDG_WEIGHT] = sf[wt_area_col].astype(float) / sf[self.FLR_AREA].astype(float)
        bldg_type_scale_factors = sf[self.BLDG_WEIGHT].to_dict()
        if np.nan in bldg_type_scale_factors:
            wrn_msg = (f'A NaN value was found in the scaling factors, which means that a building type was missing '
                    f'in either the CBECS or ComStock (more likely for a test run) data.')
            logger.warning(wrn_msg)
            del bldg_type_scale_factors[np.nan]

        # Report any scaling factor greater than some threshold.
        if self.APPORTIONED:
            logger.info(f'{self.dataset_name} post-apportionment scaling factors to CBECS floor area:')
            for bldg_type, scaling_factor in bldg_type_scale_factors.items():
                logger.info(f'--- {bldg_type}: {round(scaling_factor, 2)}')
                if scaling_factor > 1.3:
                    wrn_msg = (f'The scaling factor for {bldg_type} is high, which indicates something unexpected '
                        'in the apportionment step, except for Healthcare where this is expected. Please review.')
                    logger.warning(wrn_msg)
                elif scaling_factor < 0.6:
                    wrn_msg = (f'The scaling factor for {bldg_type} is low, which indicates something unexpected '
                        'in the apportionment step. Please review.')
                    logger.warning(wrn_msg)
        else:
        # In situations with high failure rates of a single building,
        # the scaling factor will be high, and the results are likely to be
        # heavily skewed toward the few successful simulations of that building type.
            logger.info(f'{self.dataset_name} scaling factors - scale ComStock results to CBECS floor area')
            for bldg_type, scaling_factor in bldg_type_scale_factors.items():
                logger.info(f'--- {bldg_type}: {round(scaling_factor, 2)}')
                if scaling_factor > 15:
                    wrn_msg = (f'The scaling factor for {bldg_type} is high, which indicates either a test run <350k models '
                        f'or significant failed runs for this building type.  Comparisons to CBECS will likely be invalid.')
                    logger.warning(wrn_msg)

        # For reference/comparison, here are the weights from the ComStock Pre-EUSS 2024R2 runs
        # PROD_V1_COMSTOCK_WEIGHTS = {
        #     'small_office': 9.625838016683277,
        #     'medium_office': 9.625838016683277,
        #     'large_office': 9.625838016683277,
        #     'full_service_restaurant': 11.590605715816617,
        #     'hospital': 8.751376462064501,
        #     'large_hotel': 7.5550651530546435,
        #     'outpatient': 5.369615068860124,
        #     'primary_school': 13.871553017909118,
        #     'quick_service_restaurant': 9.065844311687599,
        #     'retail': 2.816749212502974,
        #     'secondary_school': 6.958371476467069,
        #     'small_hotel': 5.062001512453252,
        #     'strip_mall': 2.1106205675100735,
        #     'warehouse': 2.1086048544461304
        # }
        # Here are the 'nominal' weights from Sampling V2 implementation (EUSS 2024 R2 on):
        # TODO Add weights here

        # Assign scaling factors to each ComStock run
        self.building_type_weights = bldg_type_scale_factors
        if self.APPORTIONED:
            cbecs_weights = pl.LazyFrame({self.BLDG_TYPE: bldg_type_scale_factors.keys(), 'cbecs_weight': bldg_type_scale_factors.values()})
            self.fkt = self.fkt.join(cbecs_weights, on=pl.col(self.BLDG_TYPE))
            self.fkt = self.fkt.with_columns((pl.col(self.BLDG_WEIGHT) * pl.col('cbecs_weight')).alias(self.BLDG_WEIGHT))
            self.fkt = self.fkt.drop(self.BLDG_TYPE, 'cbecs_weight')
        else:
            self.data = self.data.with_columns((pl.col(self.BLDG_TYPE).cast(pl.Utf8).replace(bldg_type_scale_factors, default=None)).alias(self.BLDG_WEIGHT))

        assert isinstance(cbecs.data, pd.DataFrame)
        cbecs.data = pl.from_pandas(cbecs.data).lazy()
        assert isinstance(cbecs.data, pl.LazyFrame)
        self.CBECS_WEIGHTS_APPLIED = True
        return bldg_type_scale_factors

    def create_plotting_lazyframe(self):

        # Get list of upgrade IDs
        upgrade_ids = pl.Series(self.data.select(pl.col(self.UPGRADE_ID)).unique().collect()).to_list()
        upgrade_ids.sort()

        # Create an aggregation for each upgrade
        up_aggs = []
        agg_cols = [self.CZ_ASHRAE, self.CEN_DIV]
        for upgrade_id in upgrade_ids:

            # Get the fkt and self.data for this upgrade
            up_geo_data = self.get_fkt_for_upgrade(upgrade_id)
            up_data = self.data.filter((pl.col(self.UPGRADE_ID) == upgrade_id))  # .collect()

            # Filter to this geography, downselect columns, create savings columns, and downselect columns
            up_agg = self.create_geospatial_slice_of_metadata(up_geo_data,
                                                              up_data,
                                                              geography_filters={},
                                                              geographic_aggregation_levels=agg_cols,
                                                              column_downselection=None)
            up_aggs.append(up_agg)

        # Combine all upgrades into a single LazyFrame
        self.plotting_data = pl.concat(up_aggs)

        return self.plotting_data

    def create_national_aggregation(self):
        national_aggregation = self.fkt.clone()
        national_aggregation = national_aggregation.select(
            [pl.col(self.BLDG_WEIGHT), pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID)]
        ).groupby([pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID)]).sum()
        national_aggregation = national_aggregation.join(self.data, on=[pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID)])
        national_aggregation = self.add_weighted_area_energy_savings_columns(national_aggregation)

        # Calculate national monthly values for something
        # Todo rewrite this to use proper column names
        # self.get_scaled_comstock_monthly_consumption_by_state(national_aggregation)

        # Reorder the columns before exporting
        national_aggregation = self.reorder_data_columns(national_aggregation)
        assert isinstance(national_aggregation, pl.LazyFrame)

        up_ids = pl.Series(national_aggregation.select(pl.col(self.UPGRADE_ID)).unique().collect()).to_list()
        # up_ids = [up_id for (up_id, _) in self.cached_parquet]
        up_ids.sort()
        for up_id in up_ids:
            # Write CSV version
            file_name = f'ComStock wide upgrade{up_id}.csv'
            file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
            logger.info(f'Exporting to: {file_path}')
            try:
                national_aggregation.filter(pl.col(self.UPGRADE_ID) == up_id).sink_csv(file_path)
            except pl.exceptions.InvalidOperationError:
                logger.warning('Warning - sink_csv not supported for metadata write in current polars version')
                logger.warning('Falling back to .collect.write_csv')
                national_aggregation.filter(pl.col(self.UPGRADE_ID) == up_id).collect().write_csv(file_path)

            # Write Parquet version
            file_name = f'ComStock wide upgrade{up_id}.parquet'
            file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
            logger.info(f'Exporting to: {file_path}')
            try:
                national_aggregation.filter(pl.col(self.UPGRADE_ID) == up_id).sink_parquet(file_path)
            except pl.exceptions.InvalidOperationError:
                logger.warning('Warning - sink_parquet not supported for metadata write in current polars version')
                logger.warning('Falling back to .collect.write_parquet')
                national_aggregation.filter(pl.col(self.UPGRADE_ID) == up_id).collect().write_parquet(file_path)

        # Export dictionaries corresponding to the exported columns
        self.export_data_and_enumeration_dictionary()

        # Return the nationally aggregated dataframe for use by plotting, etc.
        return national_aggregation

    def create_geospatially_resolved_aggregations(self, geographic_col_name, pretty_geo_col_name=False):
        # Ensure the geography is supported
        supported_geographies = [self.CEN_DIV, self.STATE_ID, self.COUNTY_ID, self.TRACT_ID, self.CZ_ASHRAE]
        if geographic_col_name not in [self.STATE_ID, self.COUNTY_ID, self.TRACT_ID, self.CZ_ASHRAE]:
            logger.error(f'Requeted geographic aggregation {geographic_col_name} not in supported geographies.')
            logger.error(f'Currently supported geographies are {supported_geographies}')
            raise RuntimeError('Unsupported geography selected for geospatial aggregation')

        # Create the spatial aggregation
        spatial_aggregation = self.fkt.clone()
        spatial_aggregation = spatial_aggregation.select(
            [pl.col('weight'), pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID), pl.col(geographic_col_name)]
        ).groupby([pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID), pl.col(geographic_col_name)]).sum()
        spatial_aggregation = spatial_aggregation.join(self.data, on=[pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID)])
        spatial_aggregation = self.add_weighted_area_energy_savings_columns(spatial_aggregation)

        # Reorder the columns before exporting
        spatial_aggregation = self.reorder_data_columns(spatial_aggregation)
        assert isinstance(spatial_aggregation, pl.LazyFrame)

        up_ids = pl.Series(spatial_aggregation.select(pl.col(self.UPGRADE_ID)).unique().collect()).to_list()
        # up_ids = [up_id for (up_id, _) in self.cached_parquet]
        up_ids.sort()
        for up_id in up_ids:
            file_name = f'{self.UPGRADE_ID}={up_id}'
            file_path = os.path.abspath(os.path.join(
                self.output_dir, 'geospatial_results', geographic_col_name.replace('in.', ''), file_name
            ))
            logger.info(f'Exporting to: {file_path}')
            to_write = spatial_aggregation.filter(pl.col(self.UPGRADE_ID) == up_id)
            if pretty_geo_col_name:
                to_write = to_write.with_columns(pl.col(geographic_col_name).alias(pretty_geo_col_name))
            else:
                pretty_geo_col_name = geographic_col_name
            logger.warning("IF USING OSX AND YOU GET A '*** OSError: [Errno 24] Too many open files' DO THE FOLLOWING'")
            logger.warning("Add the following two commands to your ~/.bash_profile and reboot your shell:")
            logger.warning("ulimit -n 200000")
            logger.warning("ulimit -u 2048")
            logger.info("Attempting pottentially OSERROR triggering write:")
            to_write.collect().write_parquet(file_path, use_pyarrow=True, pyarrow_options={
                "partition_cols": [pretty_geo_col_name], 'max_partitions': 3143
            })

        # Export dictionaries corresponding to the exported columns
        self.export_data_and_enumeration_dictionary()

        # Return the geospatially aggregated dataframe for use by plotting, etc.
        return spatial_aggregation

    def create_geospatial_slice_of_metadata(self,
                                            geo_data,
                                            meta_data,
                                            baseline_fkt_plus,
                                            geography_filters={},
                                            geographic_aggregation_levels=[],
                                            column_downselection=None):

        # Filter to specified geography
        if len(geography_filters) > 0:
            geo_filter_exprs = [(pl.col(k) == v) for k, v in geography_filters.items()]
            geo_data = geo_data.filter(geo_filter_exprs)

        # Determine the geography to aggregate to.
        # At a minimum aggregate the identical building ID X upgrade IDs inside
        # each census tract, which are a result of the bootstrapping process used for apportionment.
        if (not geographic_aggregation_levels) or (geographic_aggregation_levels == [None]):
            geographic_aggregation_levels = [self.TRACT_ID]

        # At this point the geo_data has a tract for each building (row)
        # Join the utility bill columns with data about all utilites onto this
        # Include building floor area for utility cost intenstity calcs
        util_results_cols = [pl.col(c) for c in self.COLS_UTIL_BILL_RESULTS] + [self.FLR_AREA]
        util_results = meta_data.select(
            [pl.col(self.BLDG_ID), pl.col(self.UPGRADE_NAME)] + util_results_cols
        )
        
        geo_data = geo_data.join(util_results, on=self.BLDG_ID, how='left')

        # load tract to utility mapping 
        file_path = os.path.join(self.truth_data_dir, self.tract_to_util_map_file_name)
        tract_to_util_map = pl.scan_csv(file_path)

        # add eia utility id
        geo_data = geo_data.join(tract_to_util_map, on=self.TRACT_ID, how='left')

        # For each row, select the utility bill based on the ID based on the allocated tract
        bills_expr = r"\|{}:(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?)\|"

        geo_data = geo_data.with_columns(
            [pl.col(self.UTIL_BILL_ELEC_RESULTS)
               .str
               .extract(pl.format(bills_expr, pl.col(self.UTIL_BILL_EIA_ID)), i+1)
               .alias(column)
            for i, column in enumerate(self.UTIL_ELEC_BILL_VALS)]
        )
        
        # for each row, select the state average utility cost based on the allocated state
        state_expr = r"\|{}:(.+?)\|"

        geo_data = geo_data.with_columns(
            [pl.col(result)
               .str
               .extract(pl.format(state_expr, pl.col(self.STATE_ABBRV)), 1)
               .cast(pl.Int32)
               .alias(column)
            for result, column in dict(zip(self.COLS_STATE_UTIL_RESULTS, self.COST_STATE_UTIL_COSTS)).items()]
        )

        # fill missing utility bill costs with state average
        geo_data = geo_data.with_columns(
            [pl.when('usd' in column)
               .then(pl.col(column)
                       .fill_null(pl.col(self.UTIL_STATE_AVG_ELEC_COST))
                    )
               .when('label' in column)
               .then(pl.col(column)
                       .fill_null('state_average_rate')
                    )
            for column in self.UTIL_ELEC_BILL_VALS]
        )
        
        # calculate the weighted utility bill columns directly on the fkt
        conv_fact = self.conv_fact('usd', self.weighted_utility_units)
        cost_cols = (self.UTIL_ELEC_BILL_COSTS + self.COST_STATE_UTIL_COSTS)
        for col in cost_cols:
            # get weighted col name
            weighted_col_name = self.col_name_to_weighted(col, self.weighted_utility_units)
            self.unweighted_weighted_map.update({col: weighted_col_name})
        
        # calculate weighted utility costs
        geo_data = geo_data.with_columns(
            [pl.col(col)
               .cast(pl.Int32)
               .mul(pl.col(self.BLDG_WEIGHT))
               .mul(conv_fact)
               .alias(self.unweighted_weighted_map[col])
               for col in cost_cols
            ]
        )

        # weight number of bills TODO: do we want this?
        geo_data = geo_data.with_columns(
            pl.col(self.UTIL_ELEC_BILL_NUM_BILLS)
              .cast(pl.Int32)
              .mul(pl.col(self.BLDG_WEIGHT))
              .alias(self.col_name_to_weighted(self.UTIL_ELEC_BILL_NUM_BILLS))
        )
        # update name dict
        self.unweighted_weighted_map.update({self.UTIL_ELEC_BILL_NUM_BILLS: self.col_name_to_weighted(self.UTIL_ELEC_BILL_NUM_BILLS)})

        # get upgrade ID
        upgrade_id_frame = geo_data.collect().select(pl.col(self.UPGRADE_ID)).cast(pl.Int32).unique()
        # should be a single value
        assert upgrade_id_frame.select(pl.len()).item() == 1
        upgrade_id = upgrade_id_frame.item()

        logger.info(f'Creating geospatial slice for upgrade: {upgrade_id}')

        # geo_data.collect().write_csv(os.path.abspath(os.path.join(self.output_dir, f'{upgrade_id}_test_geo_data_before_agg.csv')))

        # Aggregate the weights for building IDs within each geography
        if geographic_aggregation_levels == ['national']:
            # Handle national case because there is no "country" column in the dataset to filter on
            geo_agg_cols = []
        else:
            geo_agg_cols = [pl.col(c) for c in geographic_aggregation_levels]

        # get weighted util cols to aggregate
        weighted_util_cols = [self.unweighted_weighted_map[col] for col in (cost_cols + [self.UTIL_ELEC_BILL_NUM_BILLS])]

        # aggregate the fkt weights (and and weighted utility bill results) to input geospatial resolutions
        geo_data = geo_data.select(
            [
                pl.col(self.BLDG_WEIGHT), 
                pl.col(self.UPGRADE_ID), 
                pl.col(self.BLDG_ID),
                pl.col(self.FLR_AREA)
            ]
            + geo_agg_cols
            + weighted_util_cols
        ).groupby(
            [
                pl.col(self.UPGRADE_ID), 
                pl.col(self.BLDG_ID)
            ] 
            + geo_agg_cols
        ).agg(
            [
                pl.col([self.BLDG_WEIGHT] + geographic_aggregation_levels + weighted_util_cols).sum(),
                pl.col(self.FLR_AREA).first()
            ]
        )

        logger.info('Geospatial aggregation Complete')

        # calculate as average 'unweighted' utility intensity, e.g. (sum of weighted bills) / (sum of weights * building area)
        geo_data = geo_data.with_columns(
            [pl.col(self.unweighted_weighted_map[col]) # sum of (utility cost per building * tract-level weights) in billion usd
               .truediv(
                   pl.col(self.FLR_AREA) # single building area
                     .mul(pl.col(self.BLDG_WEIGHT)) # sum of tract-level weights
                     .mul(conv_fact) # usd to billion usd
               )
               .alias(self.col_name_to_area_intensity(col))
            for col in cost_cols]
        )

        # calculate aggregate savings cols
        geo_data = self.add_weighted_utility_cost_savings_columns(geo_data, baseline_fkt_plus, geo_agg_cols)

        # cache the baseline fkt at this point to use for savings calculations
        if upgrade_id == 0:
            baseline_fkt_plus = geo_data


        logger.info("Joining the aggregated weights to simulation results")
        # Join the weights to the per-model metadata and annual results
        geo_data = geo_data.select(pl.all().exclude(self.FLR_AREA)).join(meta_data, on=[pl.col(self.UPGRADE_ID), pl.col(self.BLDG_ID)])

        # remove utility cols from unweighted_weighted_map
        for col in (cost_cols + [self.UTIL_ELEC_BILL_NUM_BILLS]):
            self.unweighted_weighted_map.pop(col, None)

        geo_data.collect().write_csv(os.path.abspath(os.path.join(self.output_dir, f'{upgrade_id}_test_geo_data_with_savings_joined.csv')))
        
        logger.info("Calculating weighted energy savings columns")
        # Calculate the weighted columns
        geo_data = self.add_weighted_area_energy_savings_columns(geo_data)

        print("--->>>Add geospatial data columns based on most informative geography column<<<---")
        # Add geospatial data columns based on most informative geography column
        geo_data = self.add_geospatial_columns(geo_data, geographic_aggregation_levels[0])
        if geographic_aggregation_levels == [self.TRACT_ID]:
            geo_data = self.add_cejst_columns(geo_data)
            geo_data = self.add_ejscreen_columns(geo_data)

        print("--->>>Downselect columns for export<<<---")
        # Downselect columns for export
        if column_downselection is not None:
            geo_data = self.downselect_columns_for_metadata_export(geo_data, column_downselection)

        # Remove units from the column names used by SightGlass
        # comstock.remove_sightglass_column_units()

        # Reorder the columns
        geo_data = self.reorder_data_columns(geo_data)

        # Drop the dataset and completed_status columns
        # since these aren't useful to the target audience
        # TODO comstockpostproc should control these exports via comstock_column_definitions
        # droping_list = [comstock.DATASET, comstock.COMP_STATUS] + ['out.district_heating.interior_equipment.energy_consumption',
        #                                                             'out.district_heating.interior_equipment.energy_savings',
        #                                                             'out.district_heating.interior_equipment.energy_consumption_intensity',
        #                                                             'out.district_heating.interior_equipment.energy_savings_intensity',
        #                                                             'calc.enduse_group.district_heating.interior_equipment.energy_consumption..kwh',
        #                                                             'calc.percent_savings.district_heating.interior_equipment.energy_consumption..percent',
        #                                                             'calc.percent_savings.district_heating.interior_equipment.energy_consumption_intensity..percent',
        #                                                             'calc.weighted.district_heating.interior_equipment.energy_consumption..tbtu',
        #                                                             'calc.weighted.savings.district_heating.interior_equipment.energy_consumption..tbtu']
        # comstock.data = comstock.data.drop(droping_list)

        # List the final set of columns
        # logger.info('Final columns from create_geospatial_slice_of_metadata:')
        # for c in geo_data.columns:
        #     logger.info(c)

        # Return the LazyFrame for use by plotting, etc.
        assert isinstance(geo_data, pl.LazyFrame)
        return [geo_data, baseline_fkt_plus]

    def export_metadata_and_annual_results(self, geo_exports, out_dir=None, aws_profile=None):

        # Default the output path if nothing is passed
        if out_dir is None:
            out_dir = self.output_dir

        # Create fsspec paths for filesystem; writes locally or to S3
        if 's3://' in out_dir:
            # PyAthena >2.18.0 implements an s3 filesystem that replaces s3fs but does not implement file.open()
            # Make fsspec use the s3fs s3 filesystem implementation for writing files to S3
            import s3fs
            from fsspec import register_implementation
            register_implementation("s3", s3fs.S3FileSystem, clobber=True)
            out_fs, out_fs_path = url_to_fs(out_dir, profile=aws_profile)
            logger.info(f'out_fs filesystem type: {type(out_fs)}')
        else:
            out_fs, out_fs_path = url_to_fs(out_dir, profile=aws_profile)

        out_location = {}
        out_location['fs'], out_location['fs_path'] = out_fs, out_fs_path

        # # Define the geographic partitions to export
        # geo_exports = [
        # {'geo_top_dir': 'national',
        #     'partition_cols': {},
        #     'aggregation_levels': ['national'],
        #    'data_types': ['detailed', 'full', 'basic'],
        #    'file_types': ['csv', 'parquet'],
        # },
        # {'geo_top_dir': 'by_state_and_county',
        #     'partition_cols': {
        #         comstock.STATE_ABBRV: 'state',
        #         comstock.COUNTY_ID: 'county',
        #     },
        #     'aggregation_levels': [None, comstock.COUNTY_ID],  # The only one by at full resolution (no agg)
        #     'data_types': ['full', 'basic'],
        #     'file_types': ['csv', 'parquet'],
        # },
        # {
        #     'geo_top_dir': 'by_state',
        #     'partition_cols': {
        #         comstock.STATE_ABBRV: 'state'
        #     },
        #     'aggregation_levels': [comstock.STATE_ABBRV],
        #     'data_types': ['full', 'basic'],
        #     'file_types': ['csv', 'parquet'],
        # },
        # {'geo_top_dir': 'by_state_and_puma',
        #     'partition_cols': {
        #         comstock.STATE_ABBRV: 'state',
        #         comstock.PUMA_ID: 'puma',
        #     },
        #     'aggregation_levels': [comstock.PUMA_ID],
        #     'data_types': ['full', 'basic'],
        #     'file_types': ['csv', 'parquet'],
        # },
        # NOTE: data_types must be specified from most columns to fewest
        # AKA ['detailed', 'full', 'basic'] to work properly.

        # Get list of upgrade IDs
        upgrade_ids = pl.Series(self.data.select(pl.col(self.UPGRADE_ID)).unique().collect()).to_list()
        upgrade_ids.sort()

        # Export to all geographies
        logger.info(f'Exporting /metadata_and_annual_results and /metadata_and_annual_results_aggregates')
        for ge in geo_exports:
            ge_tstart = datetime.datetime.now()
            geo_top_dir = ge['geo_top_dir']
            partition_cols = ge['partition_cols']
            aggregation_levels = ge['aggregation_levels']
            data_types = ge['data_types']
            file_types = ge['file_types']
            geo_col_names = list(partition_cols.keys())
            logger.info(f'Exporting: {geo_top_dir}. ')
            logger.info(f'Partitioning by: {geo_col_names}')
            logger.info(f'Geographic aggregation levels: {aggregation_levels}')

            # Get the unique set of combinations of all geography column partitions
            logger.debug('Get the unique set of combinations of all geography column partitions')
            if len(geo_col_names) == 0:
                geo_combos = pl.DataFrame({'geography': ['national']})
                first_geo_combos = pl.DataFrame({'geography': ['national']})
            else:
                geo_combos = self.fkt.select(geo_col_names).unique().collect()
                geo_combos = geo_combos.sort(by=geo_col_names)
                first_geo_combos = self.fkt.select(geo_col_names[0]).unique().collect()
                first_geo_combos = first_geo_combos.sort(by=geo_col_names[0])

            # Make a directory for the geography type
            full_geo_dir = f"{out_location['fs_path']}/metadata_and_annual_results/{geo_top_dir}"
            out_location['fs'].mkdirs(full_geo_dir, exist_ok=True)

            # Make a directory for each data type X file type combo
            if None in aggregation_levels:
                for data_type in data_types:
                    for file_type in file_types:
                        out_location['fs'].mkdirs(f'{full_geo_dir}/{data_type}/{file_type}', exist_ok=True)

            # Make an aggregates directory for the geography type
            full_geo_agg_dir = f"{out_location['fs_path']}/metadata_and_annual_results_aggregates/{geo_top_dir}"
            out_location['fs'].mkdirs(full_geo_agg_dir, exist_ok=True)

            # Make a directory for each data type X file type combo
            for data_type in data_types:
                for file_type in file_types:
                    out_location['fs'].mkdirs(f'{full_geo_agg_dir}/{data_type}/{file_type}', exist_ok=True)

            # Builds a file path for each aggregate based on name, file type, and aggregation level
            def get_file_path(full_geo_agg_dir, full_geo_dir, geo_prefixes, geo_levels, file_type, aggregation_level):
                # Start with either /metadata_and_annual_results or /metadata_and_annual_results_aggregates
                agg_level_dir = full_geo_agg_dir
                if aggregation_level is None:
                    agg_level_dir = full_geo_dir
                geo_level_dir = f'{agg_level_dir}/{data_type}/{file_type}'
                if len(geo_levels) > 0:
                    geo_level_dir = f'{geo_level_dir}/' + '/'.join(geo_levels)
                out_location['fs'].mkdirs(geo_level_dir, exist_ok=True)
                # File name includes either 'baseline' or 'upgradeXX'
                file_name = f'upgrade{upgrade_id:02d}'
                if upgrade_id == 0:
                    file_name = 'baseline'
                # Add geography prefix to filename
                if len(geo_prefixes) > 0:
                    geo_prefix = '_'.join(geo_prefixes)
                    file_name = f'{geo_prefix}_{file_name}'
                # Add aggregate suffix to filename
                if aggregation_level is not None:
                    file_name = f'{file_name}_agg'
                # Add data_type suffix to filename
                if data_type == 'basic':
                    file_name = f'{file_name}_{data_type}'
                # Add the filetype extension to filename
                file_name = f'{file_name}.{file_type}'
                # Write the file, depending on filetype
                file_path = f'{geo_level_dir}/{file_name}'

                return file_path

            # cached baseline fkt with utility data for savings calcs
            baseline_fkt_plus = None

            # Write a file for each upgrade X geography combo for each file type
            for upgrade_id in upgrade_ids:
                # Get the fkt and self.data for this upgrade
                up_geo_data = self.get_fkt_for_upgrade(upgrade_id)
                up_data = self.data.filter((pl.col(self.UPGRADE_ID) == upgrade_id))  # .collect()

                # Write raw data and all aggregation levels
                for aggregation_level in aggregation_levels:

                    # Start with the most expansive set of columns, the downselect later as-needed.
                    if 'detailed' in data_types:
                        starting_downselect = 'detailed'
                    elif 'full' in data_types:
                        starting_downselect = 'full'
                    elif 'basic' in data_types:
                        starting_downselect = 'basic'

                    # Handle aggregated vs. non-aggregated differently because of memory usage
                    if aggregation_level is None:
                        # Iterate by first level of geographic partitioning, collecting the DataFrame
                        # for this geography then writing files for all the sub-geographies within it.
                        for first_geo_combo in first_geo_combos.iter_rows(named=True):
                            print(f'first_geo_combo: {first_geo_combo}')

                            # Get the filters for the first level geography
                            first_geo_filters = {}
                            for k, v in first_geo_combo.items():
                                if k == 'geography' and v == 'national':
                                    continue
                                first_geo_filters[k] = v

                            # Collect the dataframe for the first level geography
                            agg_lvl_list = [aggregation_level] # TODO move handling of this inside create_geospatial_slice_of_metadata
                            if isinstance(aggregation_level, list):
                                agg_lvl_list = aggregation_level  # Pass list if a list is already supplied
                            processed_dfs = self.create_geospatial_slice_of_metadata(up_geo_data, up_data, baseline_fkt_plus, first_geo_filters, agg_lvl_list, starting_downselect)
                            to_write = processed_dfs[0]
                            to_write = to_write.collect()
                            logger.info(f'There are {to_write.shape[0]:,} total rows for {first_geo_filters}')

                            # cache baseline fkt with utilities for utility bill savings
                            baseline_fkt_plus = processed_dfs[1]

                            # Queue writes for each geography
                            combos_to_write = []
                            for geo_combo in geo_combos.iter_rows(named=True):
                                # print(f'geo_combo: {geo_combo}')

                                # Get the filters for the geography
                                geo_filters = {}
                                geo_levels = []
                                geo_prefixes = []
                                for k, v in geo_combo.items():
                                    if k == 'geography' and v == 'national':
                                        continue
                                    geo_filters[k] = v
                                    geo_levels.append(f'{partition_cols[k]}={v}')
                                    geo_prefixes.append(v)

                                # Skip geo_combos that aren't in this first-level partitioning. e.g. counties not in a state
                                first_level_geo_combo_val = list(first_geo_filters.values())[0]
                                geo_combo_val = list(geo_filters.values())[0]
                                if not geo_combo_val == first_level_geo_combo_val:
                                    logger.info(f'Skipping {geo_combo} because not in this partition ({geo_combo_val} != {first_level_geo_combo_val})')
                                    continue

                                # Filter already-collected dataframe to specified geography
                                if len(geo_filters) > 0:
                                    geo_filter_exprs = [(pl.col(k) == v) for k, v in geo_filters.items()]
                                    geo_data = to_write.filter(geo_filter_exprs)
                                else:
                                    geo_data = to_write

                                # Sort by building ID
                                geo_data = geo_data.sort(by=self.BLDG_ID)

                                # Queue write for each data type
                                for data_type in data_types:

                                    # Downselect columns further if appropriate
                                    if not data_type == starting_downselect:
                                        geo_data = self.downselect_columns_for_metadata_export(geo_data, data_type)
                                        geo_data = self.reorder_data_columns(geo_data)

                                    # Queue write for all selected filetypes
                                    n_rows, n_cols = geo_data.shape
                                    for file_type in file_types:
                                        file_path = get_file_path(full_geo_agg_dir, full_geo_dir, geo_prefixes, geo_levels, file_type, aggregation_level)
                                        logger.info(f"Queuing {file_path}: n_cols = {n_cols:,}, n_rows = {n_rows:,}")
                                        combo = (geo_data.clone(), out_location, file_type, file_path)
                                        combos_to_write.append(combo)

                            # Write files in parallel
                            logger.info(f'Writing {len(combos_to_write)} files in parallel')
                            logger.info(datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                            Parallel(n_jobs=12)(delayed(write_geo_data)(combo) for combo in combos_to_write)
                            logger.info(datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

                    else:
                        # If there is any aggregation, collect a single dataframe with all geographies and savings columns
                        # Memory usage should work on most laptops
                        no_geo_filters = {}
                        agg_lvl_list = [aggregation_level] # TODO move handling of this inside create_geospatial_slice_of_metadata
                        if isinstance(aggregation_level, list):
                            agg_lvl_list = aggregation_level  # Pass list if a list is already supplied
                        processed_dfs = self.create_geospatial_slice_of_metadata(up_geo_data, up_data, baseline_fkt_plus, no_geo_filters, agg_lvl_list, starting_downselect)
                        to_write = processed_dfs[0]
                        # print(to_write)
                        # exit()
                        to_write = to_write.collect()
                        logger.info(f'There are {to_write.shape[0]:,} total rows at the aggregation level {aggregation_level}')

                        # cache baseline fkt with utilities for utility bill savings
                        baseline_fkt_plus = processed_dfs[1]

                        # Process each geography and downselect columns
                        combos_to_write = []
                        for geo_combo in geo_combos.iter_rows(named=True):
                            # print(f'geo_combo: {geo_combo}')

                            geo_filters = {}
                            geo_levels = []
                            geo_prefixes = []
                            for k, v in geo_combo.items():
                                if k == 'geography' and v == 'national':
                                    continue
                                geo_filters[k] = v
                                geo_levels.append(f'{partition_cols[k]}={v}')
                                geo_prefixes.append(v)

                            # Filter already-collected dataframe to specified geography
                            if len(geo_filters) > 0:
                                geo_filter_exprs = [(pl.col(k) == v) for k, v in geo_filters.items()]
                                geo_data = to_write.filter(geo_filter_exprs)
                            else:
                                geo_data = to_write

                            # Sort by building ID
                            geo_data = geo_data.sort(by=self.BLDG_ID)

                            # Queue write for each data type
                            for data_type in data_types:

                                # Downselect columns further if appropriate
                                if not data_type == starting_downselect:
                                    geo_data = self.downselect_columns_for_metadata_export(geo_data, data_type)
                                    geo_data = self.reorder_data_columns(geo_data)

                                # Queue write for all selected filetypes
                                n_rows, n_cols = geo_data.shape
                                for file_type in file_types:
                                    file_path = get_file_path(full_geo_agg_dir, full_geo_dir, geo_prefixes, geo_levels, file_type, aggregation_level)
                                    logger.info(f"Queuing {file_path}: n_cols = {n_cols:,}, n_rows = {n_rows:,}")
                                    combo = (geo_data.clone(), out_location, file_type, file_path)
                                    combos_to_write.append(combo)

                        # Write files in parallel
                        logger.info(f'Writing {len(combos_to_write)} files in parallel')
                        logger.info(datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                        Parallel(n_jobs=12)(delayed(write_geo_data)(combo) for combo in combos_to_write)
                        logger.info(datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

            ge_tend = datetime.datetime.now()
            logger.info(f'Finished exporting: {geo_top_dir}. ')
            logger.info(f'Partitioned by: {geo_col_names}')
            logger.info(f'Geographic aggregation levels: {aggregation_levels}')
            logger.info(f'Time elapsed: {(ge_tend - ge_tstart).total_seconds()} seconds')

        # Export dictionaries corresponding to the exported columns
        self.export_data_and_enumeration_dictionary()

    def add_weights_aportioned_by_stock_estimate(self,
                                                 apportionment: Apportion,
                                                 keep_n_per_apportionment_group=False,
                                                 reload_from_cache=False):
        # This function doesn't support already CBECS-weighted self.data - error out
        if self.CBECS_WEIGHTS_APPLIED:
            raise RuntimeError('Unable to apply apportionment weighting after CBECS weighting - reverse order.')

        # TODO this should live somewhere else - don't know where...
        self.data = self.data.with_columns(
            pl.col(self.COUNTY_ID).cast(str).str.slice(0, 4).alias(self.STATE_ID)
        )

        # Path to cached fkt file
        file_name = f'cached_ComStock_fkt.parquet'
        fkt_file_path = os.path.abspath(os.path.join(self.output_dir, file_name))

        if reload_from_cache:
            # fkt creation is non-deterministic, so recreating it results in a different set of models
            # being used, which is an issue if postprocessing is stopped and restarted.
            # Reloading from cache ensures that the same set of models is used.
            if os.path.exists(fkt_file_path):
                logger.info(f'Reloading fkt from cache: {fkt_file_path}')
                self.fkt = pl.scan_parquet(fkt_file_path)
                self.APPORTIONED = True

                # Join on the missing PUMA ID
                # TODO this should be done in the initial fkt creation
                geo_cols = {
                    'nhgis_tract_gisjoin': self.TRACT_ID,
                    'nhgis_puma_gisjoin': self.PUMA_ID,
                }
                file_path = os.path.join(self.truth_data_dir, self.geospatial_lookup_file_name)
                geospatial_data = pl.read_csv(file_path, columns=list(geo_cols.keys()), infer_schema_length=None)
                geospatial_data = geospatial_data.rename(geo_cols)
                geospatial_data = geospatial_data.lazy()
                self.fkt = self.fkt.join(geospatial_data, on=self.TRACT_ID)
            else:
                raise FileNotFoundError(
                f'Cannot find {fkt_file_path} to reload fkt, set reload_from_cache=False.')
        else:
            # Pull the columns required to do the matching plus the annual energy total as a safety blanket
            # TODO this is a superset for convienience - slim down later
            csdf = self.data.clone().filter(pl.col(self.UPGRADE_NAME) == self.BASE_NAME).select(pl.col(
                self.BLDG_ID, self.STATE_ID, self.COUNTY_ID, self.TRACT_ID, self.SAMPLING_REGION, self.CZ_ASHRAE,
                self.BLDG_TYPE, self.HVAC_SYS, self.SH_FUEL, self.SIZE_BIN, self.FLR_AREA, self.TOT_EUI, self.CEN_DIV
            ))

            # If anything in this selection is null we're smoked so check twice and fail never
            if csdf.null_count().collect().sum(axis=1).sum() != 0:
                raise RuntimeError('Null data appears in the apportionment truth data polars frame. Please resolve')

            # Cast sqft to int32
            csdf = csdf.with_columns(pl.col(self.FLR_AREA).cast(pl.Int32))

            # Create the joined hvac system type and fuel type variable used for sampling bin generation and processing
            csdf = csdf.with_columns(
                pl.concat_str([pl.col(self.HVAC_SYS), pl.col(self.SH_FUEL)], separator='_').alias('hvac_and_fueltype')
            )

            # Create a apportionment group id which will be shared for iteration by both the target (apportionment data) and
            # domain (csdf data).
            # TODO make the apportionment data object a lazy df nativly
            APPO_GROUP_ID = 'appo_group_id'
            apportionment.data.loc[:, 'hvac_and_fueltype'] = apportionment.data.loc[:, 'system_type'] + '_' + apportionment.data.loc[:, 'heating_fuel']
            appo_group_df = apportionment.data.copy(deep=True).loc[
                :, ['sampling_region', 'building_type', 'size_bin', 'hvac_and_fueltype']
            ]
            appo_group_df = appo_group_df.drop_duplicates(keep='first').sort_values(
                by=['sampling_region', 'building_type', 'size_bin', 'hvac_and_fueltype']
            ).reset_index(drop=True).reset_index(names=APPO_GROUP_ID)
            appo_group_df = pl.DataFrame(appo_group_df).lazy()

            # Join apportionment group id into comstock data
            csdf = csdf.join(
                appo_group_df,
                left_on=[self.SAMPLING_REGION, self.BLDG_TYPE, self.SIZE_BIN, 'hvac_and_fueltype'],
                right_on=['sampling_region', 'building_type', 'size_bin', 'hvac_and_fueltype']
            )
            if csdf.select(pl.col(APPO_GROUP_ID).is_null().any()).collect().item() != False:
                raise RuntimeError('Not all combinations of sampling region, bt, and size bin could be matched.')

            # Join apportionment group id into comstock data
            tdf = pl.DataFrame(apportionment.data.copy(deep=True)).lazy()
            tdf = tdf.join(appo_group_df, on=['sampling_region', 'building_type', 'size_bin', 'hvac_and_fueltype'])

            # Identify combination in the truth data not supported by the current sample.
            csdf_groups = pl.Series(csdf.select(pl.col(APPO_GROUP_ID)).unique().collect()).to_list()
            truth_groups = pl.Series(appo_group_df.select(pl.col(APPO_GROUP_ID)).unique().collect()).to_list()
            missing_groups = set(truth_groups) - set(csdf_groups)
            unable_to_match = tdf.filter(pl.col(APPO_GROUP_ID).is_in(missing_groups)).select(pl.len()).collect().item()
            total_to_match = tdf.select(pl.len()).collect().item()
            logger.info(f'Unable to match {unable_to_match} out of {total_to_match} truth data.')

            # Provide detailed additional info on missing buckets for review if desired
            logger.info(f'Writing QAQC / Debugging files to {os.path.abspath(self.output_dir)}')
            file_path = os.path.abspath(os.path.join(self.output_dir, 'missing_truth_data_buildings.log'))
            with open(file_path, 'w') as f:
                f.write('The following is a breakdown of missing truth data buildings by bucket attributes:\n')
                for attribute in ['sampling_region', 'building_type', 'size_bin', 'hvac_and_fueltype']:
                    f.write(f'\nAttribute: {attribute}:\n')
                    f.write(f'{pl.Series(tdf.filter(pl.col(APPO_GROUP_ID).is_in(missing_groups)).select(pl.col(attribute).value_counts(sort=True)).collect()).to_list()}'
                        .replace("}, {", "\n\t").replace("[{", "\t").replace("}]", ""))
            attrs = ['sampling_region', 'building_type', 'size_bin', 'hvac_and_fueltype']
            file_path = os.path.abspath(os.path.join(self.output_dir, 'potential_apportionment_group_optimization.csv'))
            tdf.select([pl.col(col) for col in attrs]).groupby([pl.col(col) for col in attrs]).len().sort(pl.col('len'), descending=True).collect().write_csv(file_path)
            file_path = os.path.abspath(os.path.join(self.output_dir, 'debugging_missing_apportionment_groups.csv'))
            tdf.filter(pl.col(APPO_GROUP_ID).is_in(missing_groups)).select([pl.col(col) for col in attrs]).groupby([pl.col(col) for col in attrs]).len().sort(pl.col('len'), descending=True).collect().write_csv(file_path)

            # Drop unsupported truth data and add an index
            tdf = tdf.filter(pl.col(APPO_GROUP_ID).is_in(missing_groups).is_not())
            tdf = tdf.with_row_index()

            # Drop unsupported very-small schools while ensuring at least 3 samples per apportionment group
            # Note we can just drop here because the csdf lazyframe isn't used elsewhere
            # This returns all apportionment groups with three or more schools over 2k square feet, making them 'ok' to
            # remove schools under 2k sqft from them.
            row_count_before = csdf.select(pl.len()).collect().item()
            appo_groups_to_apply_drop_to = pl.Series(
                csdf.select(
                    self.BLDG_TYPE, APPO_GROUP_ID, self.FLR_AREA
                ).filter(
                    (pl.col(self.BLDG_TYPE).is_in(['PrimarySchool', 'SecondarySchool'])) &
                    (pl.col(self.FLR_AREA) > 2001)
                ).groupby(
                    APPO_GROUP_ID
                ).count(
                ).filter(
                    pl.col('count') > 2
                ).select(
                    APPO_GROUP_ID
                ).collect()
            ).to_list()
            # Keep all rows not in the list of above apportionment groups OR over 2k sqft
            csdf = csdf.filter(
                (~pl.col(APPO_GROUP_ID).is_in(appo_groups_to_apply_drop_to)) |
                (pl.col(self.FLR_AREA) > 2001)
            )
            row_count_after = csdf.select(pl.len()).collect().item()
            logger.info(f'Removed {row_count_before - row_count_after} very small schools from cs results')

            # Create a dictionary defining how many elements of which apportionment groups to sample
            samples_per_group = tdf.groupby(APPO_GROUP_ID).len().collect().to_pandas()
            samples_per_group = samples_per_group.set_index(APPO_GROUP_ID).to_dict()['len']

            # Create a dictionary identifying the tdf indicies associated with each apportionment group
            tdf_ids_per_group = tdf.select(pl.col('index'), pl.col(APPO_GROUP_ID)).groupby(pl.col(APPO_GROUP_ID)).agg(pl.col('index')).collect().to_pandas()
            tdf_ids_per_group = tdf_ids_per_group.set_index(APPO_GROUP_ID).to_dict()['index']

            # Create a dictionary of which comstock building ids are associated with each apportionment group
            cs_ids_per_group = csdf.select(pl.col(self.BLDG_ID), pl.col(APPO_GROUP_ID)).groupby(pl.col(APPO_GROUP_ID)).agg(pl.col(self.BLDG_ID)).collect().to_pandas()
            cs_ids_per_group = cs_ids_per_group.set_index(APPO_GROUP_ID).to_dict()[self.BLDG_ID]
            assert(set(samples_per_group.keys()) == set(cs_ids_per_group.keys()))

            # Iterativly sample the groups
            # Keeping apportionment group id for debugging if needed later... Otherwise unnessecary
            logger.info('Apportioning comstock building models for each building in the bootstrapped truth dataset')
            sampled_appo_id = list()
            sampled_td_id = list()
            sampled_cs_id = list()
            for group_id in samples_per_group.keys():
                to_sample = samples_per_group[group_id]
                sampled_appo_id.extend(np.repeat(group_id, to_sample).tolist())
                sampled_td_id.extend(tdf_ids_per_group[group_id].tolist())
                sampled_cs_id.extend(np.random.choice(cs_ids_per_group[group_id], to_sample).tolist())

            # Create the new sampled dataframe (foreign key table)
            fkdf = pd.DataFrame({APPO_GROUP_ID: sampled_appo_id, 'tdf_id': sampled_td_id, self.BLDG_ID: sampled_cs_id})
            fkt = pl.DataFrame(fkdf).lazy()

            # Join tdf onto the sampled results with all upgrades
            logger.info('Joining truth dataset information onto the sampled forign key table')
            fkt = fkt.join(tdf.select(
                pl.col('index').alias('tdf_id').cast(pl.Int64),
                pl.col('tract').alias(self.TRACT_ID),
                pl.col('county').alias(self.COUNTY_ID),
                pl.col('state').alias(self.STATE_ID),
                pl.col('cz').alias(self.CZ_ASHRAE_CEC_MIXED),
                pl.col('cen_div').alias(self.CEN_DIV),
                pl.col('sqft').alias('truth_sqft'),
                pl.col('tract_assignment_type').alias('in.tract_assignment_type'),
                pl.col('building_type').alias(self.BLDG_TYPE)
            ), on=pl.col('tdf_id'))

            # Pull in the sqft calculate weights
            area_by_id = self.data.select(pl.col(self.FLR_AREA), pl.col(self.BLDG_ID), pl.col(self.UPGRADE_ID))
            area_by_id = area_by_id.filter(pl.col(self.UPGRADE_ID) == 0).drop([self.UPGRADE_ID])
            fkt = fkt.join(area_by_id, on=[pl.col(self.BLDG_ID)])
            logger.info('Calculating apportioned weights')
            bs_coef = apportionment.bootstrap_coefficient
            fkt = fkt.with_columns((pl.col('truth_sqft') / (pl.col(self.FLR_AREA) * bs_coef)).alias(self.BLDG_WEIGHT))

            # Add state abbreviations to the fkt for use in partitioning
            fkt = fkt.with_columns(
                pl.col(self.STATE_ID).replace(self.STATE_NHGIS_TO_ABBRV).alias(self.STATE_ABBRV)
            )

            # Map the mixed ASHRAE and CEC climate zones back to ASHRAE climate zones
            fkt = fkt.with_columns(
                pl.col(self.CZ_ASHRAE_CEC_MIXED).replace(self.MIXED_CZ_TO_ASHRAE_CZ).alias(self.CZ_ASHRAE)
            )

            # Drop unwanted columns from the foreign key table and persist
            fkt = fkt.drop('tdf_id', APPO_GROUP_ID, 'truth_sqft', 'in.tract_assignment_type', self.FLR_AREA)

            # Cache the fkt for reuse
            fkt.collect().write_parquet(fkt_file_path)
            logger.info(f'Caching fkt to: {fkt_file_path}')

            # Scan the fkt
            self.fkt = pl.scan_parquet(fkt_file_path)
            self.APPORTIONED = True

        # Return new self.data object - note this may still be normalized against cbecs
        logger.debug('Renaming existing self.data geospatial cols to prevent namespace collision')
        self.data = self.data.rename({
            self.TRACT_ID: self.TRACT_ID.replace('in.', self.POST_APPO_SIM_COL_PREFIX),
            self.COUNTY_ID: self.COUNTY_ID.replace('in.', self.POST_APPO_SIM_COL_PREFIX),
            self.STATE_ID: self.STATE_ID.replace('in.', self.POST_APPO_SIM_COL_PREFIX),
            self.CEN_DIV: self.CEN_DIV.replace('in.', self.POST_APPO_SIM_COL_PREFIX),
        })

        # Drop any remaining geography columns associated with the model creation
        # Geographic data will joined after self.data and self.fkt have been joined
        self.data = self.data.drop(self.COLS_GEOG)

        logger.info('Successfully completed the apportionment sampling postprocessing')

    def get_fkt_for_upgrade(self, upgrade_id):
        if self.fkt is None:
            raise Exception(f'self.fkt not initialized, call add_weights_aportioned_by_stock_estimate() first')

        # Ensure this is a valid upgrade ID
        avail_up_ids = pl.Series(self.data.select(pl.col(self.UPGRADE_ID)).unique().collect()).to_list()
        if upgrade_id not in avail_up_ids:
            raise Exception(f"Requested fkt for upgrade_id={upgrade_id} not in self.data. Choose from: {avail_up_ids}")

        # Add the upgrade ID to the fkt, which is identical for every upgrade
        up_fkt = self.fkt.clone()
        up_fkt = up_fkt.with_columns([
                pl.lit(upgrade_id).cast(pl.Int64).alias(self.UPGRADE_ID)
            ])

        return up_fkt

    def add_weighted_area_energy_savings_columns(self, input_lf):

        assert isinstance(input_lf, pl.LazyFrame)
        # Area - create weighted column
        new_area_col = self.col_name_to_weighted(self.FLR_AREA)
        input_lf = input_lf.with_columns(
                (pl.col(self.FLR_AREA) * pl.col(self.BLDG_WEIGHT)).alias(new_area_col))

        #generate the weighted columns with coventions for Emission, Utility, Energy Enduse group.
        old_unit_to_new_unit = {
            'co2e_kg': self.weighted_ghg_units, #Emission, default : co2e_kg -> co2e_mmt
            'usd': self.weighted_utility_units, #Utility, default : usd -> billion_usd
            'kwh': self.weighted_energy_units, #Energy and Enduse Groups, default : kwh -> tbtu
            'kw': self.weighted_demand_units, #(Peak) Demand, default : kw -> gw (gigawatt)
        }

        # Get the list of existing column names
        existing_col_names = input_lf.columns
        logger.debug('Converting units in the weighted columns')
        for col in (self.GHG_FUEL_COLS +
                     [self.ANN_GHG_EGRID, self.ANN_GHG_CAMBIUM] +
                    # self.COLS_UTIL_BILLS +
                    # [self.UTIL_BILL_TOTAL_MEAN, self.UTIL_BILL_ELEC_MAX, self.UTIL_BILL_ELEC_MED, self.UTIL_BILL_ELEC_MIN] +
                    self.COLS_TOT_ANN_ENGY +
                    self.COLS_ENDUSE_ANN_ENGY +
                    self.COLS_ENDUSE_GROUP_TOT_ANN_ENGY +
                    self.COLS_ENDUSE_GROUP_ANN_ENGY):

            if not col in existing_col_names:
                logger.warning(f'Missing column needed for adding weighted columns: {col}')
            # assert col in input_lf.columns, f'Missing column needed for adding weighted columns: {col}' # TODO ANDREW handle this

            #based on the unit, we use different conv factor and convert the value to the new column
            old_unit = self.units_from_col_name(col)

            if old_unit not in old_unit_to_new_unit.keys():
                raise Exception("The unit is not in the old_unit_to_new_unit mapping")

            new_col = self.col_name_to_weighted(col, old_unit_to_new_unit[old_unit])
            conv_fact = self.conv_fact(old_unit, old_unit_to_new_unit[old_unit])
            input_lf = input_lf.with_columns(
                (pl.col(col) * pl.col(self.BLDG_WEIGHT) * conv_fact).alias(new_col))
            logger.debug(f'{col} * {self.BLDG_WEIGHT} * {conv_fact} -> {new_col}')

        assert isinstance(input_lf, pl.LazyFrame)

        logger.debug('Adding weighted savings columns')
        #based on the unweighted savings columns, generate the weighted savings columns
        if self.include_upgrades:
            for unweighted_saving_cols, weighted_saving_cols in self.unweighted_weighted_map.items():
                # logger.info(f'Handling {unweighted_saving_cols} to {weighted_saving_cols}')
                if weighted_saving_cols in existing_col_names:
                    logger.info(f'Already added weighted savings column: {weighted_saving_cols}')
                    continue

                old_unit = self.units_from_col_name(unweighted_saving_cols)
                new_unit = self.units_from_col_name(weighted_saving_cols)
                conv_fact = self.conv_fact(old_unit, new_unit)
                input_lf: pl.LazyFrame = input_lf.with_columns((pl.col(unweighted_saving_cols) * pl.col(self.BLDG_WEIGHT) * conv_fact).alias(weighted_saving_cols))
                logger.debug(f'Adding {unweighted_saving_cols} * {self.BLDG_WEIGHT} * {conv_fact} -> {weighted_saving_cols}')

        assert isinstance(input_lf, pl.LazyFrame)

        # Create weighted emissions for each enduse group
        # TODO once end-use emissions are reported, sum those columns directly
        logger.debug('Adding enduse group emissions columns')
        for col in (self.COLS_ENDUSE_GROUP_ANN_ENGY + self.COLS_ENDUSE_GROUP_TOT_ANN_ENGY):
            fuel, enduse_gp = col.replace('calc.enduse_group.', '').replace('.energy_consumption..kwh', '').split('.')
            if fuel in ['district_heating', 'district_cooling']:
                continue  # ComStock has no emissions for district heating or cooling

            tot_engy = f'calc.weighted.{fuel}.total.energy_consumption..tbtu'
            enduse_gp_engy = f'calc.weighted.enduse_group.{fuel}.{enduse_gp}.energy_consumption..tbtu'
            tot_ghg = f'calc.weighted.emissions.{fuel}..co2e_mmt'
            enduse_gp_ghg_col = f'calc.weighted.enduse_group.{fuel}.{enduse_gp}.emissions..co2e_mmt'

            if fuel == 'electricity':
                enduse_gp_ghg_col = f'calc.weighted.enduse_group.{fuel}.{enduse_gp}.emissions.egrid_2021_subregion..co2e_mmt'
                tot_ghg = 'calc.weighted.emissions.electricity.egrid_2021_subregion..co2e_mmt'
            elif fuel == 'site_energy':
                tot_ghg = f'calc.weighted.emissions.total_with_egrid..co2e_mmt'

            # enduse group emissions = total emissions * (enduse group energy / total energy)
            if fuel == 'other_fuel':
                # Add propane and fuel oil emissions together because energy is reported combined as other_fuel
                propane_ghg = f'calc.weighted.emissions.propane..co2e_mmt'
                fuel_oil_ghg = f'calc.weighted.emissions.fuel_oil..co2e_mmt'
                tot_ghg_expr = (pl.col(propane_ghg).add(pl.col(fuel_oil_ghg)))
                input_lf = input_lf.with_columns([
                    pl.when((pl.col(tot_engy) > 0))  # Avoid divide-by-zero
                    .then((tot_ghg_expr.mul(pl.col(enduse_gp_engy)).truediv(pl.col(tot_engy))))
                    .otherwise(0.0)
                    .alias(enduse_gp_ghg_col),
                ])
            else:
                input_lf = input_lf.with_columns([
                    pl.when((pl.col(tot_engy) > 0))  # Avoid divide-by-zero
                    .then((pl.col(tot_ghg).mul(pl.col(enduse_gp_engy)).truediv(pl.col(tot_engy))))
                    .otherwise(0.0)
                    .alias(enduse_gp_ghg_col)
                ])

        assert isinstance(input_lf, pl.LazyFrame)

        return input_lf

    def add_weighted_utility_cost_savings_columns(self, input_lf, baseline_lf, geo_agg_cols):
        # the data contains the weighted extracted utility bills for the apportioned tract
        # This method will calculate the weighted utility cost savings by each metric - min, median_low, median_high, mean, max, and state average

        logger.debug('Adding weighted utility cost savings')

        assert isinstance(input_lf, pl.LazyFrame)

        result_cols = self.UTIL_ELEC_BILL_COSTS + self.COST_STATE_UTIL_COSTS
        abs_svgs_cols = {}
        pct_svgs_cols = {}

        val_cols = []

        for col in result_cols:
            weighted_col = self.unweighted_weighted_map[col]
            val_cols.append(weighted_col)
            abs_svgs_cols[weighted_col] = self.col_name_to_savings(weighted_col, None)
            pct_svgs_cols[weighted_col] = self.col_name_to_percent_savings(weighted_col, 'percent')
            # mapping for column name to intensity savings column name
            intensity_col = self.col_name_to_area_intensity(col)
            val_cols.append(intensity_col)
            abs_svgs_cols[intensity_col] = self.col_name_to_savings(intensity_col, None)
            pct_svgs_cols[intensity_col] = self.col_name_to_percent_savings(intensity_col, 'percent')

        if baseline_lf is None:
            # this is baseline data, add empty savings cols and return
            for weighted_col in (list(abs_svgs_cols.values()) + list(pct_svgs_cols.values())):
                input_lf = input_lf.with_columns(pl.lit(0.0).alias(weighted_col))
            return input_lf
        

        val_and_id_cols = val_cols + geo_agg_cols + [self.BLDG_ID]
        # for col in val_and_id_cols:
        #     print(col)

        base_vals = baseline_lf.select(val_and_id_cols).sort([self.BLDG_ID] + geo_agg_cols).clone()
        base_vals = base_vals.rename(lambda col_name: col_name + '_base')

        up_vals = input_lf.select(val_and_id_cols).sort([self.BLDG_ID] + geo_agg_cols).clone()

        # absolute savings
        abs_svgs = pl.concat([up_vals, base_vals], how='horizontal').with_columns(
            [pl.col(f'{col}_base') - pl.col(col) for col in val_cols]
        ).select(up_vals.columns)

        # percent savings
        pct_svgs = pl.concat([up_vals, base_vals], how='horizontal').with_columns(
            [(pl.col(f'{col}_base') - pl.col(col)) / pl.col(f'{col}_base') for col in val_cols]
        ).select(up_vals.columns)

        pct_svgs = pct_svgs.fill_null(0.0)
        pct_svgs = pct_svgs.fill_nan(0.0)

        # abs_svgs = abs_svgs.rename(abs_svgs_cols).cast({self.BLDG_ID: pl.Int64})
        # pct_svgs = pct_svgs.rename(pct_svgs_cols).cast({self.BLDG_ID: pl.Int64})

        abs_svgs = abs_svgs.rename(abs_svgs_cols)
        pct_svgs = pct_svgs.rename(pct_svgs_cols)

        input_lf = input_lf.join(abs_svgs, how='left', on=[self.BLDG_ID] + geo_agg_cols)
        input_lf = input_lf.join(pct_svgs, how='left', on=[self.BLDG_ID] + geo_agg_cols)

        return input_lf

    def add_unweighted_savings_columns(self):

        assert isinstance(self.data, pl.DataFrame)

        col_groups = [
            # Energy
            {
                'cols': self.COLS_TOT_ANN_ENGY + self.COLS_ENDUSE_ANN_ENGY,
                'weighted_units': self.weighted_energy_units
            },
            # Utility Bills
            # {
            #     'cols': (self.COLS_UTIL_BILLS +
            #                     [self.UTIL_BILL_TOTAL_MEAN,
            #                     self.UTIL_BILL_ELEC_MAX,
            #                     self.UTIL_BILL_ELEC_MED,
            #                     self.UTIL_BILL_ELEC_MIN]),
            #     'weighted_units': self.weighted_utility_units
            # },
            # Peak Demand QOIs
            {
                'cols': (self.COLS_QOI_MONTHLY_MAX_DAILY_PEAK +
                              self.COLS_QOI_MONTHLY_MED_DAILY_PEAK +
                              [self.QOI_MAX_SHOULDER_USE,
                              self.QOI_MAX_SUMMER_USE,
                              self.QOI_MAX_WINTER_USE]),
                'weighted_units': self.weighted_demand_units
            },
            # Emissions
            {
                'cols': (self.COLS_GHG_ELEC_SEASONAL_DAILY_EGRID +
                              self.COLS_GHG_ELEC_SEASONAL_DAILY_CAMBIUM +
                              [self.GHG_LRMER_MID_CASE_15_ELEC,
                              self.GHG_ELEC_EGRID,
                              self.ANN_GHG_EGRID,
                              self.ANN_GHG_CAMBIUM]),
                'weighted_units': self.weighted_ghg_units
            }
        ]

        # Calculate savings for each group of columns using the appropriate units
        for col_group in col_groups:

            val_cols = []
            abs_svgs_cols = {}
            pct_svgs_cols = {}

            for col in col_group['cols']:
                # Mapping from column name to raw savings column name
                val_cols.append(col)
                abs_svgs_cols[col] = self.col_name_to_savings(col, None)
                pct_svgs_cols[col] = self.col_name_to_percent_savings(col, 'percent')
                # Mapping for column name to intensity savings column name
                intensity_col = self.col_name_to_area_intensity(col)
                val_cols.append(intensity_col)
                abs_svgs_cols[intensity_col] = self.col_name_to_savings(intensity_col, None)
                pct_svgs_cols[intensity_col] = self.col_name_to_percent_savings(intensity_col, 'percent')

                # Save a map of columns to create weighted savings for later in processing
                # after weights are assigned.
                self.unweighted_weighted_map.update({
                    self.col_name_to_savings(col, None): self.col_name_to_weighted_savings(col, col_group['weighted_units'])
                    })

            # Keep the building ID and upgrade name columns to use as the index
            val_and_id_cols = val_cols + [self.BLDG_ID, self.UPGRADE_NAME]

            # Get the baseline results
            base_vals = self.data.filter(pl.col(self.UPGRADE_NAME) == self.BASE_NAME).select(val_and_id_cols).sort(self.BLDG_ID).clone()

            # Caculate the savings for each upgrade, including the baseline
            up_abs_svgs = []
            up_pct_svgs = []

            for upgrade_name, up_res in self.data.groupby(self.UPGRADE_NAME):

                up_vals = up_res.select(val_and_id_cols).sort(self.BLDG_ID).clone()

                # Check that building_ids have same order in both DataFrames before division
                base_val_ids = base_vals.get_column(self.BLDG_ID)
                up_val_ids = up_vals.get_column(self.BLDG_ID)
                assert up_val_ids.to_list() == base_val_ids.to_list()

                # Calculate the absolute and percent savings
                abs_svgs = (base_vals[val_cols] - up_vals[val_cols])

                pct_svgs = ((base_vals[val_cols] - up_vals[val_cols]) / base_vals[val_cols])
                pct_svgs = pct_svgs.fill_null(0.0)
                pct_svgs = pct_svgs.fill_nan(0.0)

                abs_svgs = abs_svgs.with_columns([
                    base_val_ids,
                    pl.lit(upgrade_name).alias(self.UPGRADE_NAME)
                ])
                abs_svgs = abs_svgs.with_columns(pl.col(self.UPGRADE_NAME))

                pct_svgs = pct_svgs.with_columns([
                    base_val_ids,
                    pl.lit(upgrade_name).alias(self.UPGRADE_NAME)
                ])
                pct_svgs = pct_svgs.with_columns(pl.col(self.UPGRADE_NAME))

                abs_svgs = abs_svgs.rename(abs_svgs_cols)
                pct_svgs = pct_svgs.rename(pct_svgs_cols)

                up_abs_svgs.append(abs_svgs)
                up_pct_svgs.append(pct_svgs)

            up_abs_svgs = pl.concat(up_abs_svgs)
            up_pct_svgs = pl.concat(up_pct_svgs)

            # Join the savings columns onto the results
            self.data = self.data.join(up_abs_svgs, how='left', on=[self.UPGRADE_NAME, self.BLDG_ID])
            self.data = self.data.join(up_pct_svgs, how='left', on=[self.UPGRADE_NAME, self.BLDG_ID])

    def remove_sightglass_column_units(self):
        # SightGlass requires that the energy_consumption, energy_consumption_intensity,
        # energy_savings, and energy_savings_intensity columns have no units on the
        # column names. This method removes the units from the appropriate column names.

        def rmv_units(c):
            return c.replace(f'..{self.units_from_col_name(c)}', '')

        crnms = {}  # Column renames
        og_cols = self.data.columns
        for col in (self.COLS_TOT_ANN_ENGY + self.COLS_ENDUSE_ANN_ENGY):
            # energy_consumption
            if col in og_cols: crnms[col] = rmv_units(col)

            # energy_consumption_intensity
            col_int = self.col_name_to_eui(col)
            if col_int in og_cols: crnms[col_int] = rmv_units(col_int)

            # energy_savings
            col_svg = self.col_name_to_savings(col)
            if col_svg in og_cols: crnms[col_svg] = rmv_units(col_svg)

            # energy_savings_intensity
            col_svg_int = self.col_name_to_eui(col_svg)
            if col_svg_int in og_cols: crnms[col_svg_int] = rmv_units(col_svg_int)

        # peak_demand
        col_peak = 'out.electricity.total.peak_demand..kw'
        if col_peak in og_cols: crnms[col_peak] = rmv_units(col_peak)

        logger.debug('remove_sightglass_column_units')
        for old, new in crnms.items():
            assert old.startswith(new)
            logger.debug(f'{old} -> {new}')

        self.data = self.data.rename(crnms)

    def add_sightglass_column_units(self, lazyframe):
        # SightGlass requires that the energy_consumption, energy_consumption_intensity,
        # energy_savings, and energy_savings_intensity columns have no units on the
        # column names. This method adds those units back to the appropriate column names,
        # which is useful for plotting.

        def rmv_units(c):
            return c.replace(f'..{self.units_from_col_name(c)}', '')

        crnms = {}  # Column renames
        og_cols = lazyframe.columns
        for col in (self.COLS_TOT_ANN_ENGY + self.COLS_ENDUSE_ANN_ENGY):
            # energy_consumption
            if rmv_units(col) in og_cols: crnms[rmv_units(col)] = col

            # energy_consumption_intensity
            col_int = self.col_name_to_eui(col)
            if rmv_units(col_int) in og_cols: crnms[rmv_units(col_int)] = col_int

            # energy_savings
            col_svg = self.col_name_to_savings(col)
            if rmv_units(col_svg) in og_cols: crnms[rmv_units(col_svg)] = col_svg

            # energy_savings_intensity
            col_svg_int = self.col_name_to_eui(col_svg)
            if rmv_units(col_svg_int) in og_cols: crnms[rmv_units(col_svg_int)] = col_svg_int

        # peak_demand
        c_peak = 'out.electricity.total.peak_demand..kw'
        if rmv_units(c_peak) in og_cols: crnms[rmv_units(c_peak)] = c_peak

        logger.debug('add_sightglass_column_units')
        for old, new in crnms.items():
            assert new.startswith(old)
            logger.debug(f'{old} -> {new}')

        lazyframe = lazyframe.rename(crnms)
        return lazyframe

    def get_comstock_unscaled_monthly_energy_consumption(self):
        """
        From the ComStock run, get the monthly timeseries data into monthly natural gas and electricity energy consumption for each state.
        Scale the monthly consumption to national scale.
        First, scale each building type up to match CBECS sqft for that building type.
        Second, scale the total energy for that total sqft up to match the total of CBECS for ALL building types.
        Return:
            comstock_monthly_consumption (pd.DataFrame): Table of natural gas and electricity consumption by state and month.
        """
        if self.athena_table_name is None:
            logger.debug('No athena_table_name was provided, not attempting to query monthly data from Athena.')
            return True

        # Load or query timeseries ComStock results by state and building type
        file_name = f'comstock_monthly_natural_gas_and_electricity_by_state_and_bldg_type.csv'
        file_path = os.path.join(self.data_dir, file_name)
        if not os.path.exists(file_path):
            # Query Athena for ComStock results
            logger.info('Querying Athena for ComStock monthly energy data by state and building type, this will take several minutes.')
            query = f"""
                SELECT
                "upgrade",
                "month",
                "state_id",
                "building_type",
                sum("total_site_gas_kbtu") AS "total_site_gas_kbtu",
                sum("total_site_electricity_kwh") AS "total_site_electricity_kwh"
                FROM
                (
                    SELECT
                    EXTRACT(MONTH from "time") as "month",
                    SUBSTRING("build_existing_model.county_id", 2, 2) AS "state_id",
                    "build_existing_model.create_bar_from_building_type_ratios_bldg_type_a" as "building_type",
                    "upgrade",
                    "total_site_gas_kbtu",
                    "total_site_electricity_kwh"
                    FROM
                    "{self.athena_table_name}_timeseries"
                    JOIN "{self.athena_table_name}_baseline"
                    ON "{self.athena_table_name}_timeseries"."building_id" = "{self.athena_table_name}_baseline"."building_id"
                    WHERE "build_existing_model.building_type" IS NOT NULL
                )
                GROUP BY
                "upgrade",
                "month",
                "state_id",
                "building_type"
            """
            comstock_unscaled_data = self.athena_client.execute(query)
            comstock_unscaled_data.to_csv(file_path, index=False)

        # Read data from disk
        comstock_unscaled = pl.read_csv(file_path)

        # Rename columns
        comstock_unscaled = comstock_unscaled.rename({'month': 'Month', 'state_id': 'FIPS Code'})

        # Rename upgrade values
        upgrade_data = self.data.select([self.UPGRADE_ID, self.UPGRADE_NAME])
        print(upgrade_data.head())
        upgrade_name_map = dict(zip(upgrade_data[self.UPGRADE_ID], upgrade_data[self.UPGRADE_NAME]))
        comstock_unscaled = comstock_unscaled.with_columns(
            pl.col('upgrade').replace(upgrade_name_map).alias('upgrade_name'),
        )
        print(comstock_unscaled.head())
        #Rename Building_Types
        def rename_buildingtypes(building_type):
            building_type = building_type.replace('_',' ').replace(' ', '')
            return building_type

        comstock_unscaled = comstock_unscaled.with_columns(
            pl.col('building_type').map_elements(lambda x: rename_buildingtypes(x), return_dtype=pl.Utf8).alias('building_type'),
        )

        self.monthly_data = comstock_unscaled

        return comstock_unscaled

    def get_scaled_comstock_monthly_consumption_by_state(self, input_lf):

        if self.monthly_data is None:
            logger.info('No monthly_data exists, not attempting to scale monthly data.')
            return True

        # Load or query monthly ComStock energy consumption by state and building type
        monthly = self.monthly_data

        # Get the scaling factors to take the results of this ComStock run to the national scale
        comstock_scaling_factors: pl.LazyFrame = input_lf.clone().group_by(self.BLDG_TYPE).agg(pl.col(self.BLDG_WEIGHT).mean()).collect()
        #comstock_scaling_factors only have two columns. not costly.
        comstock_scaling_factors = dict(comstock_scaling_factors.iter_rows())

        # Assign the correct per-building-type scaling factor to ComStock monthly data
        monthly = monthly.with_columns((pl.col(self.BLDG_TYPE).replace(comstock_scaling_factors, default=None)).alias('Scaling Factor'))

        # Scale the ComStock energy consumption
        monthly = monthly.with_columns(
            (pl.col('total_site_electricity_kwh').mul(pl.col('Scaling Factor'))).alias('Electricity consumption (kWh)'),
        )

        monthly = monthly.with_columns(
            (pl.col('total_site_gas_kbtu').mul(pl.col('Scaling Factor'))).alias('Natural gas consumption (thous Btu)'),
        )

        # Aggregate ComStock by state and month, combining all building types
        vals = ['Electricity consumption (kWh)', 'Natural gas consumption (thous Btu)']
        cols_to_drop = [self.BLDG_TYPE, 'total_site_electricity_kwh', 'total_site_gas_kbtu', 'Scaling Factor']

        idx = ['FIPS Code', 'Month', 'upgrade', 'upgrade_name']
        monthly = monthly.group_by(idx).sum().drop(cols_to_drop)

        # Add a dataset label column
        monthly = monthly.with_columns([
            pl.lit(self.dataset_name).alias(self.DATASET)
        ])

        # load the state id table
        file_path = os.path.join(self.truth_data_dir, 'state_region_division_table.csv')
        if not os.path.exists(file_path):
            raise AssertionError('State metadata not found, download truth data')
        else:
            state_table = pl.read_csv(file_path)

        # Rename columns
        state_table = state_table.rename({'State': self.STATE_NAME, 'State Code': self.STATE_ABBRV})

        # Append the state metadata
        cols = ['FIPS Code', self.STATE_ABBRV, 'Division']
        monthly = monthly.join(state_table.select(cols), on='FIPS Code', how='left')

        # # Get the energy consumption of the buildings NOT covered by ComStock from CBECS
        # cbecs_gap_elec_tbtu, cbecs_gap_gas_tbtu = self.get_comstock_to_whole_stock_energy_gaps()

        # Using ComStock's existing distribution of energy consumption by state and month,
        # add the energy consumption of the buildings NOT covered by ComStock.
        # This will be called the ComStock Gap Model.
        # Because of the way the stacked bar plots are created, ComStock Gap = ComStock + ComStock Gap
        # comstock_elec_tbtu = comstock['Electricity consumption (kWh)'].sum() * self.kWh_to_kBtu * self.kBtu_to_TBtu
        # comstock_gas_tbtu = comstock['Natural gas consumption (thous Btu)'].sum() * self.kBtu_to_TBtu
        # elec_scale = (cbecs_gap_elec_tbtu + comstock_elec_tbtu) / comstock_elec_tbtu
        # gas_scale = (cbecs_gap_gas_tbtu + comstock_gas_tbtu) / comstock_gas_tbtu
        # comstock_gap = comstock.copy()
        # comstock_gap['Dataset'] = 'ComStock Gap Model'
        # comstock_gap['Electricity consumption (kWh)'] = comstock_gap['Electricity consumption (kWh)'] * elec_scale
        # comstock_gap['Natural gas consumption (thous Btu)'] = comstock_gap['Natural gas consumption (thous Btu)'] * gas_scale


        # self.monthly_data_gap = comstock_gap
        self.monthly_data = monthly
        return True

    def create_long_energy_data(self):
        # Convert energy and emissions data into long format, with a row for each fuel/enduse group combo

        engy_cols = []
        emis_cols = []
        for col in (self.COLS_ENDUSE_GROUP_ANN_ENGY):
            fuel, enduse_gp = col.replace('calc.enduse_group.', '').replace('.energy_consumption..kwh', '').split('.')
            pre = f'calc.weighted.enduse_group.{fuel}.{enduse_gp}'
            enduse_gp_engy = f'{pre}.energy_consumption..tbtu'
            engy_cols.append(enduse_gp_engy)
            # Find the corresponding emissions column
            for c in self.data.columns:
                if c.startswith(f'{pre}.emissions'):
                    emis_cols.append(c)

        # Convert energy columns to long form
        engy_var_col = 'calc.weighted.enduse_group.fuel.enduse_group.energy_consumption..units'
        pre = 'calc.weighted.enduse_group.'
        suf = '..tbtu'
        engy_val_col = f'calc.weighted.energy_consumption..{self.weighted_energy_units}'
        engy = self.data.melt(id_vars=[self.BLDG_ID, self.UPGRADE_ID], value_vars=engy_cols, variable_name=engy_var_col, value_name=engy_val_col)
        engy = engy.with_columns(
            pl.col(engy_var_col).str.strip_prefix(pre).str.strip_suffix(suf).str.split('.').list.get(0).alias('fuel'),
            pl.col(engy_var_col).str.strip_prefix(pre).str.strip_suffix(suf).str.split('.').list.get(1).alias('enduse_group'),
        )

        # Convert emissions columns to long form
        emis_var_col = 'calc.weighted.enduse_group.fuel.enduse_group.emissions..units'
        pre = 'calc.weighted.enduse_group.'
        emis_val_col = f'calc.weighted.emissions..{self.weighted_ghg_units}'
        emis = self.data.melt(id_vars=[self.BLDG_ID, self.UPGRADE_ID], value_vars=emis_cols, variable_name=emis_var_col, value_name=emis_val_col)
        emis = emis.with_columns(
            pl.col(emis_var_col).str.strip_prefix(pre).str.split('.').list.get(0).alias('fuel'),
            pl.col(emis_var_col).str.strip_prefix(pre).str.split('.').list.get(1).alias('enduse_group'),
        )

        # Join long form energy and emissions
        join_cols = [self.BLDG_ID, self.UPGRADE_ID, 'fuel', 'enduse_group']
        engy_emis = engy.join(emis, how='left', on=join_cols)
        # Fill blank emissions (for district heating and cooling) with zeroes
        # TODO remove if emissions cols for district heating and cooling get added
        engy_emis = engy_emis.with_columns(
            pl.col(emis_val_col).fill_null(0.0)
        )
        # Remove rows with zero energy for the fuel/end use group combo to make file shorter
        engy_emis = engy_emis.filter((pl.col(engy_val_col) > 0))
        engy_emis = engy_emis.select(join_cols + [engy_val_col, emis_val_col])
        engy_emis = engy_emis.sort(by=join_cols)

        # Check that the long and wide sums match by fuel and for the total
        fuels_to_check = engy_emis.get_column('fuel').unique().to_list() + ['total']
        for fuel in fuels_to_check:
            # Define column names
            tot_engy_col = f'calc.weighted.{fuel}.total.energy_consumption..tbtu'
            tot_ghg_col = f'calc.weighted.emissions.{fuel}..co2e_mmt'
            if fuel == 'electricity':
                tot_ghg_col = 'calc.weighted.emissions.electricity.egrid_2021_subregion..co2e_mmt'
            elif fuel == 'total':
                tot_engy_col = self.col_name_to_weighted(self.ANN_TOT_ENGY_KBTU, self.weighted_energy_units)
                tot_ghg_col = self.col_name_to_weighted(self.ANN_GHG_EGRID, self.weighted_ghg_units)
            elif fuel in ['other_fuel', 'district_heating', 'district_cooling']:
                # TODO revise if district emissions added
                # Other is sum of propane and fuel_oil columns, and district cols have no emissions columns
                # Checked as part of checking total
                continue
            # Energy check
            if fuel == 'total':
                tot_engy_long = engy_emis.select(pl.sum(engy_val_col)).item()
            else:
                tot_engy_long = engy_emis.filter((pl.col('fuel') == fuel)).select(pl.sum(engy_val_col)).item()
            tot_engy_wide = self.data.select(pl.sum(tot_engy_col)).item()
            logger.debug(f'{fuel} long energy {tot_engy_long}')
            logger.debug(f'{fuel} wide energy {tot_engy_wide}')
            assert round(tot_engy_long, 1) == round(tot_engy_wide, 1), f'For {fuel}, long energy {tot_engy_long} does not match wide energy {tot_emis_wide}'
            # Emissions check
            if fuel == 'total':
                tot_emis_long = engy_emis.select(pl.sum(emis_val_col)).item()
            else:
                tot_emis_long = engy_emis.filter((pl.col('fuel') == fuel)).select(pl.sum(emis_val_col)).item()
            tot_emis_wide = self.data.select(pl.sum(tot_ghg_col)).item()
            logger.debug(f'{fuel} long emissions {tot_emis_long}')
            logger.debug(f'{fuel} wide emissions {tot_emis_wide}')
            assert round(tot_emis_long, 1) == round(tot_emis_wide, 1), f'For {fuel}, long emissions {tot_engy_long} do not match wide emissions {tot_emis_wide}'

        # Assign
        self.data_long = engy_emis

    def export_to_csv_long(self):
        # Exports comstock data to CSV in long format, with rows for each fuel/enduse group combo

        if self.data_long is None:
            self.create_long_energy_data()

        # Save files - separate building energy from characteristics for file size
        # up_ids = self.data.get_column(self.UPGRADE_ID).unique().to_list()
        # up_ids.sort()
        # logger.error(f'Got here {up_ids}')
        # for up_id in up_ids:
        #     logger.error('Got here')
        #     file_name = f'upgrade{up_id:02d}_energy_long.csv'
        #     file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
        #     logger.info(f'Exporting to: {file_path}')
        #     self.data.filter(pl.col(self.UPGRADE_ID) == up_id).write_csv(file_path)

        for cached_parquet in self.cached_parquet:
            file_name = f'{cached_parquet}_energy_long.csv'
            file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
            logger.info(f'Exporting to: {file_path}')
            self.data_long.write_csv(file_path)


    def combine_emissions_cols(self):
        # Create combined emissions columns

        # Fill empty emissions columns with zeroes before summing
        for c in self.data.columns:
            if 'out.emissions.' in c:
                self.data = self.data.with_columns([pl.col(c).fill_null(0.0)])

        # Create two combined emissions columns
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_GHG_EGRID).alias(self.ANN_GHG_EGRID))
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_GHG_CAMBIUM).alias(self.ANN_GHG_CAMBIUM))

        col_names = [self.ANN_GHG_EGRID, self.ANN_GHG_CAMBIUM]
        self.convert_units(col_names)

    def combine_utility_cols(self):
        # Create combined utility column for mean electricity rate

        ## Fill empty emissions columns with zeroes before summing
        #for c in self.data.columns:
        #    if 'out.emissions.' in c:
        #        self.data = self.data.with_columns([pl.col(c).fill_null(0.0)])

        # Create two combined emissions columns
        self.data = self.data.with_columns(pl.sum_horizontal(self.COLS_UTIL_BILLS).alias(self.UTIL_BILL_TOTAL_MEAN))

        col_names = [self.UTIL_BILL_TOTAL_MEAN]
        self.convert_units(col_names)


    def convert_units(self, col_names):
        # Read the column definitions
        col_def_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pd.read_csv(col_def_path)

        for col in col_names:
            # Check for unit conversion
            orig_units_per_name = self.units_from_col_name(col)
            col = col.replace(f'..{orig_units_per_name}', '')
            orig_units = col_defs.loc[col_defs['new_col_name'] == col, 'original_units'].item()
            assrt_msg = f'Units in column name {orig_units_per_name} dont match units in column definition {orig_units}'
            assert orig_units == orig_units_per_name, assrt_msg
            new_units = col_defs.loc[col_defs['new_col_name'] == col, 'new_units'].item()
            if pd.isna(orig_units):
                logger.debug('-- Unitless, no unit conversion necessary')
            elif orig_units == new_units:
                logger.debug(f"-- Keeping original units {orig_units}")
            else:
                # Convert the column
                cf = self.conv_fact(orig_units, new_units)
                self.data = self.data.with_columns([(pl.col(col) * cf)])
                logger.info(f"-- Converted units from {orig_units} to {new_units} by multiplying by {cf}")

    def export_data_and_enumeration_dictionary(self):

        assert isinstance(self.data, pl.LazyFrame)

        # Read column definitions
        col_def_path = os.path.join(RESOURCE_DIR, COLUMN_DEFINITION_FILE_NAME)
        col_defs = pl.read_csv(col_def_path)

        # Read enumeration definitions
        enum_def_path = os.path.join(RESOURCE_DIR, ENUM_DEFINITION_FILE_NAME)
        enum_defs = pl.read_csv(enum_def_path)

        # Data dictionary
        col_dicts = []
        all_enums = []
        for col in self.data.columns:
            if col.startswith('applicability.'):
                continue  # measure-within-upgrade applicability column names are dynamic, don't check
            col = col.replace(f'..{self.units_from_col_name(col)}', '')
            try:
                col_def = col_defs.row(by_predicate=(pl.col('new_col_name') == col), named=True)
            except pl.exceptions.NoRowsReturnedError:
                logger.error(f'No definition for {col} in {col_def_path}')
                continue
            except pl.exceptions.TooManyRowsReturnedError:
                logger.error(f'Multiple matches for {col} in {col_def_path}')
                continue

            col_enums = []
            if col_def['data_type'] == 'string':
                str_enums = []
                for enum in self.data.select(col).unique().collect().to_series().to_list():
                    if enum is None:
                        continue  # Don't define blank enumerations
                    try:
                        float(enum)  # Don't define numeric enumerations
                    except ValueError as valerr:
                        if enum == '':
                            continue
                        str_enums.append(str(enum))
                if len(str_enums) > 50:
                    logger.debug(f'Not defining enumerations for {col}, see column definition for pattern')
                    col_enums = str_enums[0:10] + ['...too many to list']
                elif 'utility_bills.' in col:
                    pass  # Don't define utility rate names
                else:
                    col_enums = str_enums
                    all_enums.extend(str_enums)
            col_dicts.append({
                'field_name': col_def['new_col_name'],
                'field_location': 'metadata',
                'data_type': col_def['data_type'],
                'units': col_def['new_units'],
                'field_description': col_def['field_description'],
                'allowable_enumeration': '|'.join(col_enums),
            })

        data_dictionary = pl.from_dicts(col_dicts)

        # Enumeration dictionary
        enum_dicts = []
        for enum in sorted(set(all_enums)):
            enum_def = enum_defs.filter(pl.col('enumeration') == enum)
            if not len(enum_def) == 1:
                logger.error(f'Found {len(enum_def)} enumeration_definitions for: "{enum}"')
                continue
            enum_def = enum_defs.row(by_predicate=(pl.col('enumeration') == enum), named=True)
            enum_dicts.append({
                'enumeration': enum,
                'enumeration_description': enum_def['enumeration_description']
            })

        if enum_dicts:
            enum_dictionary = pl.from_dicts(enum_dicts)
        else:
            enum_dictionary = pl.DataFrame()

        # Save files
        file_name = f'data_dictionary.tsv'
        file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
        logger.info(f'Exporting data dictionary to: {file_path}')
        data_dictionary.write_csv(file_path, separator='\t')

        file_name = f'enumeration_dictionary.tsv'
        file_path = os.path.abspath(os.path.join(self.output_dir, file_name))
        logger.info(f'Exporting enumeration dictionary to: {file_path}')
        enum_dictionary.write_csv(file_path, separator='\t')


    def sightGlass_metadata_check(self, comstock_data: pl.LazyFrame):
        # Actually I think this function should be a part of utility class, not the main class.
        # Check that the metadata columns are present in the data
        # when the columns are in memory
        err_log = ""

        #df.rows(named=True) = [{'foo': 1, 'bar': 1, 'ham': 0}]

        null_count_per_column: dict = comstock_data.null_count().collect().rows(named=True)[0]

        #check if there are null values in row_segment as polars LazyFrame
        for coln, null_count in null_count_per_column.items():
            if coln.startswith("out.qoi.") or coln.startswith("out.utility_bills.") or coln.startswith('applicability.upgrade_add_pvwatts'):
                continue
            if null_count > 0:
                err_log += f"Null values found in column {coln} with {null_count} null count.\n"

        SIGHTGLASS_REQUIRED_COLS = [self.BLDG_ID, self.UPGRADE_ID,
                                     self.UPGRADE_APPL, self.FLR_AREA, self.BLDG_WEIGHT]

        for col in SIGHTGLASS_REQUIRED_COLS:
            if col not in comstock_data.columns:
                err_log += f'{col} not found in data, which is needed for sightglass\n'

        #Skip pattern, may need delete later:
        pattern = r'out\.electricity\.total\.[a-zA-Z]{3}\.energy_consumption'

        for c in comstock_data.columns:
            if re.search('[^a-z0-9._]', c):
                # (f'Column {c} violates name rules: may only contain . _ 0-9 lowercaseletters (no spaces)')
                err_log += f'Column {c} violates name rules: may only contain . _ 0-9 lowercaseletters (no spaces)\n'

        #Actually that's the perfect case to use regex to check the summary.
        TOTAL_PATTERN = r'out\.([a-zA-Z_]+)\.total\.energy_consumption\.\.kwh'
        ENDUSE_PATTERN = r'out\.([a-zA-Z_]+)\.(?!total)([a-zA-Z_]+)\.energy_consumption\.\.kwh'
        MONTH_PATTERN = r'out\.electricity\.total\.([a-zA-Z]{3})\.energy_consumption'

        #Get the sum of the data
        sum_table: pl.DataFrame = comstock_data.sum().collect().rows(named=True)[0]

        #Find the sum of total culmns for each type fuels, and for each fuel type find the sum of different
        #enduse columns. And record them in a dictionary like: {fuel_type: total_energy}
        fuel_total, end_use_total, month_total = {}, {}, {}
        for c in comstock_data.columns:
            if re.match(TOTAL_PATTERN, c):
                fuel_type = re.match(TOTAL_PATTERN, c).group(1)
                if c == self.ANN_TOT_ENGY_KBTU:
                    #absolutely we don't need the total to be added into the
                    #sum again out.site_energy.total.energy_consumption..kwh should be the sum
                    #of all the other energy's type sum.
                    continue
                fuel_total[fuel_type] = sum_table[c]
            elif re.match(ENDUSE_PATTERN, c):
                fuel_type = re.match(ENDUSE_PATTERN, c).group(1)
                end_use_total[fuel_type] = end_use_total.get(fuel_type, 0) + sum_table[c]
            elif re.match(MONTH_PATTERN, c):
                month = re.match(MONTH_PATTERN, c).group(1)
                month_total[month] = sum_table[c]

        logger.info(f"Fuel total: {fuel_total}, Enduse total: {end_use_total}, Month total: {month_total}")
        # Check that the total site energy is the sum of the fuel totals
        for fuel, total in end_use_total.items():
            if not total == pytest.approx(fuel_total[fuel], rel=0.01):
                err_log += f'Fuel total for {fuel} does not match sum of enduse columns\n'
        if not sum(fuel_total.values()) == pytest.approx(sum_table[self.ANN_TOT_ENGY_KBTU], rel=0.01):
            err_log += f'Site total {sum(fuel_total.values())} does not match sum of fuel totals {sum_table[self.ANN_TOT_ENGY_KBTU]}\n'
        if not sum(month_total.values()) == pytest.approx(sum_table[self.ANN_TOT_ELEC_KBTU], rel=0.01):
            err_log += 'Electricity total does not match sum of month totals\n'

        if err_log:
            raise ValueError(err_log)