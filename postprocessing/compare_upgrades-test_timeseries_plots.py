#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import boto3
import time
from fsspec.core import url_to_fs
from sqlalchemy.engine import create_engine
import sqlalchemy as sa
import comstockpostproc as cspp
from sqlalchemy_views import CreateView
import re


import sys, inspect, importlib, site, platform, shutil, subprocess, os

mods = ["pyathena","s3fs","fsspec","botocore","aiobotocore","boto3","pandas"]
for m in mods:
    try:
        mod = importlib.import_module(m)
        print(f"{m:12} {getattr(mod,'__version__','?'):>10}  @ {inspect.getfile(mod)}")
    except Exception as e:
        print(f"{m:12} NOT IMPORTABLE: {e}")


logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def create_sightglass_tables(
    s3_location: str,
    dataset_name: str,
    database_name: str = "vizstock",
    glue_service_role: str = "vizstock-glue-service-role",
    ):
    fs, fs_path = url_to_fs(s3_location)

    glue = boto3.client("glue", region_name="us-west-2")

    crawler_name_base = f"vizstock_{dataset_name}"
    tbl_prefix_base = f"{dataset_name}"

    crawler_params = {
        "Role": glue_service_role,
        "DatabaseName": database_name,
        "Targets": {},
        "SchemaChangePolicy": {
            "UpdateBehavior": "UPDATE_IN_DATABASE",
            "DeleteBehavior": "DELETE_FROM_DATABASE",
        }
    }

    # Crawl each metadata target separately to create a
    # unique table name for each metadata folder
    logger.info(f"Creating crawlers for metadata")
    md_agg_paths = fs.ls(f"{s3_location}") #{fs_path}/metadata_and_annual_results_aggregates/
    md_paths = fs.ls(f"{fs_path}/metadata_and_annual_results/")

    for md_path in md_agg_paths + md_paths:
        md_geog = md_path.split('/')[-1]
        if '_aggregates' in md_path:
            crawler_name = f'{crawler_name_base}_md_agg_{md_geog}'
            tbl_prefix = f'{tbl_prefix_base}_md_agg_{md_geog}_'
        else:
            crawler_name = f'{crawler_name_base}_md_{md_geog}'
            tbl_prefix = f'{tbl_prefix_base}_md_{md_geog}_'

        crawler_params["Name"] = crawler_name
        crawler_params["TablePrefix"] = tbl_prefix
        crawler_params["Targets"]["S3Targets"] = [{
            "Path": f"s3://{md_path}/full/parquet",
            "SampleSize": 1
        }]

        try:
            crawler_info = glue.get_crawler(Name=crawler_name)
        except glue.exceptions.EntityNotFoundException as ex:
            logger.info(f"Creating Crawler {crawler_name}")
            glue.create_crawler(**crawler_params)
        else:
            logger.info(f"Updating Crawler {crawler_name}")
            glue.update_crawler(**crawler_params)

        logger.info(f"Running Crawler {crawler_name} on: {md_path}")

        expected_table_name = f"{tbl_prefix}{md_geog}"
        logger.info(f"Expected Athena table: {expected_table_name} in database {database_name}")

        glue.start_crawler(Name=crawler_name)
        time.sleep(10)

        crawler_info = glue.get_crawler(Name=crawler_name)
        while crawler_info["Crawler"]["State"] != "READY":
            time.sleep(10)
            crawler_info = glue.get_crawler(Name=crawler_name)
            logger.info(f"Crawler state: {crawler_info['Crawler']['State']}")
        glue.delete_crawler(Name=crawler_name)
        logger.info(f"Deleting Crawler {crawler_name}")

    return dataset_name

def fix_timeseries_tables(dataset_name: str, database_name: str = "vizstock"):
    logger.info("Updating timeseries table schemas")

    glue = boto3.client("glue", region_name="us-west-2")
    tbl_prefix = f"{dataset_name}_"
    get_tables_kw = {"DatabaseName": database_name, "Expression": f"{tbl_prefix}*"}
    tbls_resp = glue.get_tables(**get_tables_kw)
    tbl_list = tbls_resp["TableList"]

    while "NextToken" in tbls_resp:
        tbls_resp = glue.get_tables(NextToken=tbls_resp["NextToken"], **get_tables_kw)
        tbl_list.extend(tbls_resp["TableList"])

    for tbl in tbl_list:

        # Skip timeseries views that may exist, including ones created by this script
        if tbl.get("TableType") == "VIRTUAL_VIEW":
            continue

        table_name = tbl['Name']
        if not '_timeseries' in table_name:
            continue

        # Check the dtype of the 'upgrade' column.
        # Must be 'bigint' to match the metadata schema so joined queries work.
        do_tbl_update = False
        for part_key in tbl["PartitionKeys"]:
            if part_key["Name"] == "upgrade" and part_key["Type"] != "bigint":
                do_tbl_update = True
                part_key["Type"] = "bigint"

        if not do_tbl_update:
            logger.debug(f"Skipping {table_name} because it already has correct partition dtypes")
            continue

        # Delete the automatically-created partition index.
        # While the index exists, dtypes for the columns in the index cannot be modified.
        indexes_resp = glue.get_partition_indexes(
            DatabaseName=database_name,
            TableName=table_name
        )
        for index in indexes_resp['PartitionIndexDescriptorList']:
            index_name = index['IndexName']
            index_keys = index['Keys']
            logger.debug(f'Deleting index {index_name} with keys {index_keys} in {table_name}')
            glue.delete_partition_index(
                DatabaseName=database_name,
                TableName=table_name,
                IndexName=index_name
            )

        # Wait for index deletion to complete
        index_deleted = False
        for i in range(0, 60):
            indexes_resp = glue.get_partition_indexes(
                DatabaseName=database_name,
                TableName=table_name
            )
            if len(indexes_resp['PartitionIndexDescriptorList']) == 0:
                index_deleted = True
                break
            logger.debug('Waiting 10 seconds to check index deletion status')
            time.sleep(10)
        if not index_deleted:
            raise RuntimeError(f'Did not delete index in 600 seconds, stopping.')

        # Change the dtype of the 'upgrade' partition column to bigint
        tbl_input = {}
        for k, v in tbl.items():
            if k in (
                "Name",
                "Description",
                "Owner",
                "Retention",
                "StorageDescriptor",
                "PartitionKeys",
                "TableType",
                "Parameters",
            ):
                tbl_input[k] = v
        logger.debug(f"Updating dtype of upgrade column in {table_name} to bigint")
        glue.update_table(DatabaseName=database_name, TableInput=tbl_input)

        # Recreate the index
        key_names = [k['Name'] for k in index_keys]
        logger.debug(f"Creating index with columns: {key_names} in {table_name}")
        glue.create_partition_index(
            # CatalogId='string',
            DatabaseName=database_name,
            TableName=table_name,
            PartitionIndex={
                'Keys': key_names,
                'IndexName': 'vizstock_partition_index'
            }
        )

        # Wait for index creation to complete
        index_created = False
        for i in range(0, 60):
            indexes_resp = glue.get_partition_indexes(
                DatabaseName=database_name,
                TableName=table_name
            )
            for index in indexes_resp['PartitionIndexDescriptorList']:
                index_status = index['IndexStatus']
                if index_status == 'ACTIVE':
                    index_created = True
            if index_created:
                break
            else:
                logger.debug('Waiting 10 seconds to check index creation status')
                time.sleep(10)
        if not index_deleted:
            raise RuntimeError(f'Did not create index in 600 seconds, stopping.')

def column_filter(col):
    return not (
        col.name.endswith(".co2e_kg")
        or col.name.find("out.electricity.pv") > -1
        or col.name.find("out.electricity.purchased") > -1
        or col.name.find("out.electricity.net") > -1
        or col.name.find(".net.") > -1
        or col.name.find("applicability.") > -1
        or col.name.find("out.qoi.") > -1
        or col.name.find("out.emissions.") > -1
        or col.name.find("out.params.") > -1
        or col.name.find("out.utility_bills.") > -1
        or col.name.find("calc.") > -1
        or col.name.startswith("in.ejscreen")
        or col.name.startswith("in.cejst")
        or col.name.startswith("in.cluster_id")
        or col.name.startswith("in.size_bin_id")
        or col.name.startswith("in.sampling_region_id")
        or col.name.startswith("out.district_heating.interior_equipment")
        or col.name.startswith("out.district_heating.cooling")
        or col.name.endswith("_applicable")
        or col.name.startswith("out.electricity.total.apr")
        or col.name.startswith("out.electricity.total.aug")
        or col.name.startswith("out.electricity.total.dec")
        or col.name.startswith("out.electricity.total.feb")
        or col.name.startswith("out.electricity.total.jan")
        or col.name.startswith("out.electricity.total.jul")
        or col.name.startswith("out.electricity.total.jun")
        or col.name.startswith("out.electricity.total.mar")
        or col.name.startswith("out.electricity.total.may")
        or col.name.startswith("out.electricity.total.nov")
        or col.name.startswith("out.electricity.total.oct")
        or col.name.startswith("out.electricity.total.sep")
    )

def create_column_alias(col_name):

    # accept SQLAlchemy Column / ColumnElement or plain str
    if not isinstance(col_name, str):
        # prefer .name, then .key; fallback to str (last resort)
        name = getattr(col_name, "name", None) or getattr(col_name, "key", None)
        if not name:
            name = str(col_name)
        col_name = name

    # 1) name normalizations
    normalized = (
        col_name
        .replace("gas", "natural_gas")
        .replace("fueloil", "fuel_oil")
        .replace("districtheating", "district_heating")
        .replace("districtcooling", "district_cooling")
    )

    # 2) regex patterns
    m1 = re.search(
        r"^(electricity|natural_gas|fuel_oil|propane|district_heating|district_cooling|other_fuel)_(\w+)_(kwh|therm|mbtu|kbtu)$",
        normalized,
    )
    m2 = re.search(
        r"^total_site_(electricity|natural_gas|fuel_oil|propane|district_heating|district_cooling|other_fuel)_(kwh|therm|mbtu|kbtu)$",
        normalized,
    )
    m3 = re.search(r"^(total)_(site_energy)_(kwh|therm|mbtu|kbtu)$", normalized)
    m4 = re.search(
        r"^total_net_site_(electricity|natural_gas|fuel_oil|propane|district_heating|district_cooling|other_fuel)_(kwh|therm|mbtu|kbtu)$",
        normalized,
    )
    m5 = re.search(
        r"^total_purchased_site_(electricity|natural_gas|fuel_oil|propane|district_heating|district_cooling|other_fuel)_(kwh|therm|mbtu|kbtu)$",
        normalized,
    )

    if not (m1 or m2 or m3 or m4 or m5):
        # Not an energy column we care about
        return 1.0, normalized

    if m1:
        fueltype, enduse, fuel_units = m1.groups()
    elif m2:
        fueltype, fuel_units = m2.groups()
        enduse = "total"
    elif m3:
        enduse, fueltype, fuel_units = m3.groups()  # "total","site_energy",units
        # If you prefer "site_energy" to be reported as a pseudo-fuel, keep as-is.
        # Otherwise map to a specific convention here.
    elif m4:
        fueltype, fuel_units = m4.groups()
        enduse = "net"
    else:  # m5
        fueltype, fuel_units = m5.groups()
        enduse = "purchased"

    # 3) build alias
    col_alias = f"out.{fueltype}.{enduse}.energy_consumption"

    # Created using OpenStudio unit conversion library
    energy_unit_conv_to_kwh = {
        "mbtu": 293.0710701722222,
        "m_btu": 293.0710701722222,
        "therm": 29.307107017222222,
        "kbtu": 0.2930710701722222,
    }

    # 4) conversion factor to kWh
    if fuel_units == "kwh":
        conv_factor = 1.0
    else:
        try:
            conv_factor = energy_unit_conv_to_kwh[fuel_units]
        except KeyError:
            raise ValueError(f"Unhandled energy unit: {fuel_units!r} in column {col_name!r}")

    return conv_factor, col_alias

def create_views(
    dataset_name: str, database_name: str = "vizstock", workgroup: str = "eulp"
):
    glue = boto3.client("glue", region_name="us-west-2")

    logger.info(f'Creating views for {dataset_name}')

    # Get a list of metadata tables
    get_md_tables_kw = {
        "DatabaseName": database_name,
        "Expression": f"{dataset_name}_md_.*",
    }
    tbls_resp = glue.get_tables(**get_md_tables_kw)
    tbl_list = tbls_resp["TableList"]
    while "NextToken" in tbls_resp:
        tbls_resp = glue.get_tables(NextToken=tbls_resp["NextToken"], **get_md_tables_kw)
        tbl_list.extend(tbls_resp["TableList"])
    md_tbls = [x["Name"] for x in tbl_list if x["TableType"] != "VIRTUAL_VIEW"]

    # Create a view for each metadata table
    for metadata_tblname in md_tbls:
        # Connect to the metadata table
        engine = create_engine(
            f"awsathena+rest://:@athena.us-west-2.amazonaws.com:443/{database_name}?work_group={workgroup}"
        )
        meta = sa.MetaData(bind=engine)
        metadata_tbl = sa.Table(metadata_tblname, meta, autoload=True)
        logger.info(f"Loaded metadata table: {metadata_tblname}")

        # Extract the partition columns from the table name
        bys = []
        if 'by' in metadata_tblname:
            bys = metadata_tblname.replace(f'{dataset_name}_md_', '')
            bys = bys.replace(f'agg_', '').replace(f'by_', '').replace(f'_parquet', '').split('_and_')
            logger.debug(f"Partition identifiers = {', '.join(bys)}")

        # Rename the partition column to match hive partition
        # Move it up in the column order for easier debugging
        # TODO figure out a better approach than hard-coding
        aliases = {
            'state': {'col': 'in.state','alias': 'state'},
            'puma': {'col': 'in.nhgis_puma_gisjoin', 'alias': 'puma'},
            'county': {'col': 'in.nhgis_county_gisjoin', 'alias': 'county'},
            'puma_midwest': {'col': 'in.nhgis_puma_gisjoin', 'alias': 'puma'},
            'puma_northeast': {'col': 'in.nhgis_puma_gisjoin', 'alias': 'puma'},
            'puma_south': {'col': 'in.nhgis_puma_gisjoin', 'alias': 'puma'},
            'puma_west': {'col': 'in.nhgis_puma_gisjoin', 'alias': 'puma'}
        }

        # Select columns for the metadata, aliasing partition columns
        cols = []
        for col in metadata_tbl.columns:
            cols.append(col)

            continue

        # Remove everything but the input characteristics and output energy columns from the view
        cols = list(filter(column_filter, cols))

        # Alias the out.foo columns to remove units
        # TODO: add this to timeseries stuff
        cols_aliased = []
        for col in cols:
            if col.name.startswith("out.") and col.name.find("..") > -1:
                unitless_name = col.name.split('..')[0]
                cols_aliased.append(col.label(unitless_name))
                # logger.debug(f'Aliasing {col.name} to {unitless_name}')
            elif col.name == 'in.sqft..ft2':
                unitless_name = 'in.sqft' # Special requirement for SightGlass
                cols_aliased.append(col.label(unitless_name))
                # logger.debug(f'Aliasing {col.name} to {unitless_name}')
            else:
                cols_aliased.append(col)
        cols = cols_aliased

        # Check columns
        col_type_errs = 0
        for c in cols:
            # Column name length for postgres compatibility
            if len(c.name) > 63:
                col_type_errs += 1
                logger.error(f'column: `{c.name}` must be < 64 chars for SightGlass postgres storage')

            # in.foo columns may not be bigints or booleans because they cannot be serialized to JSON
            # when determining the unique set of filter values for SightGlass
            if c.name.startswith('in.') and (str(c.type) == 'BIGINT' or (str(c.type) == 'BOOLEAN')):
                col_type_errs += 1
                logger.error(f'in.foo column {c} may not be a BIGINT or BOOLEAN for SightGlass to work')

            # Expected bigint columns in SightGlass
            expected_bigints = ['metadata_index', 'upgrade', 'bldg_id']
            if c.name in expected_bigints:
                if not str(c.type) == 'BIGINT':
                    col_type_errs += 1
                    logger.error(f'Column {c} must be a BIGINT, but found {c.type}')

        if col_type_errs > 0:
            raise RuntimeError(f'{col_type_errs} were found in columns, correct these in metadata before proceeding.')

        # For PUMAs, need to create one view for each census region
        if 'puma' in bys:
            regions = ("South", "Midwest", "Northeast", "West")
            for region in regions:
                q = sa.select(cols).where(metadata_tbl.c["in.census_region_name"].in_([region]))
                view_name = metadata_tblname.replace('_by_state_and_puma_parquet', '_puma')
                view_name = f"{view_name}_{region.lower()}_vu"
                db_plus_vu = f'{database_name}_{view_name}'
                if len(db_plus_vu) > 63:
                    raise RuntimeError(f'db + view: `{db_plus_vu}` must be < 64 chars for SightGlass postgres storage')
                view = sa.Table(view_name, meta)
                create_view = CreateView(view, q, or_replace=True)
                logger.info(f"Creating metadata view: {view_name}, partitioned by {bys}")
                engine.execute(create_view)
                # logger.debug('Columns in view:')
                # for c in cols:
                #     logger.debug(c)
        else:
            q = sa.select(cols)
            view_name = metadata_tblname.replace('_parquet', '')
            view_name = f"{view_name}_vu"
            db_plus_vu = f'{database_name}_{view_name}'
            if len(db_plus_vu) > 63:
                raise RuntimeError(f'db + view: `{db_plus_vu}` must be < 64 chars for SightGlass postgres storage')
            view = sa.Table(view_name, meta)
            create_view = CreateView(view, q, or_replace=True)
            logger.info(f"Creating metadata view: {view_name}, partitioned by {bys}")
            engine.execute(create_view)
            # logger.debug('Columns in view:')
            # for c in cols:
            #     logger.debug(c)

    # Get a list of timeseries tables
    get_ts_tables_kw = {
        "DatabaseName": database_name,
        "Expression": f"{dataset_name}_timeseries*",
    }
    tbls_resp = glue.get_tables(**get_ts_tables_kw)
    tbl_list = tbls_resp["TableList"]
    while "NextToken" in tbls_resp:
        tbls_resp = glue.get_tables(NextToken=tbls_resp["NextToken"], **get_ts_tables_kw)
        tbl_list.extend(tbls_resp["TableList"])
    ts_tbls = [x["Name"] for x in tbl_list if x["TableType"] != "VIRTUAL_VIEW"]

    # Create a view for each timeseries table, removing the emissions columns
    for ts_tblname in ts_tbls:
        engine = create_engine(
            f"awsathena+rest://:@athena.us-west-2.amazonaws.com:443/{database_name}?work_group={workgroup}"
        )
        meta = sa.MetaData(bind=engine)
        ts_tbl = sa.Table(ts_tblname, meta, autoload=True)
        cols = list(filter(column_filter, ts_tbl.columns))
        cols_aliased = []
        for col in cols:

            # rename
            conv_factor, col_alias = create_column_alias(col)
            if (col.name == col_alias) & (conv_factor==1): # and conversion factor is 1
                cols_aliased.append(col)
            elif (col.name != col_alias) & (conv_factor==1): #name different, conversion factor 1
                cols_aliased.append(col.label(col_alias)) #TODO: return both alias and new units
            else: # name and conversion different
                cols_aliased.append((col/conv_factor).label(col_alias)) #TODO: return both alias and new units

            if col.name == 'timestamp': #timestamp
                # Convert bigint to timestamp type if necessary
                if str(col.type) == 'BIGINT':
                    # Pandas uses nanosecond resolution integer timestamps.
                    # Presto expects second resolution values in from_unixtime.
                    # Must divide values by 1e9 to go from nanoseconds to seconds.
                    cols_aliased.append(sa.func.from_unixtime(col / 1e9).label('timestamp')) #NOTE: syntax for adding unit conversions
                else:
                    cols_aliased.append(col)

        cols = cols_aliased

        q = sa.select(cols)
        view_name = f"{ts_tblname}_vu"

        db_plus_vu = f'{database_name}_{view_name}'
        if len(db_plus_vu) > 63:
            raise RuntimeError(f'db + view: `{db_plus_vu}` must be < 64 chars for SightGlass postgres storage')
        view = sa.Table(view_name, meta)
        create_view = CreateView(view, q, or_replace=True)
        logger.info(f"Creating timeseries view: {view_name}")
        engine.execute(create_view)
        logger.debug('Columns in view:')
        for c in cols:
            logger.debug(c)


def main():
    # ComStock run
    comstock = cspp.ComStock(
        s3_base_dir='com-sdr',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='rtuadv_v11',  # Name of the run on S3
        comstock_run_version='rtuadv_v11',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        athena_table_name=None,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.05,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_cache=True, # True if CSV already made and want faster reload times
        include_upgrades=True,  # False if not looking at upgrades
        upgrade_ids_to_skip=[2,3], # Use [1, 3] etc. to exclude certain upgrades
        make_timeseries_plots=True,
        states={
                'MN': 'Minnesota',  # specify state to use for timeseries plots in dictionary format. State ID must correspond correctly.
                'MA':'Massachusetts',
                'OR': 'Oregon',
                'LA': 'Louisiana',
                'AZ': 'Arizona',
                'TN': 'Tennessee'
                },
        # [('state',['VA','AZ'])
        upgrade_ids_for_comparison={} # Use {'<Name you want for comparison run folder>':[0,1,2]}; add as many upgrade IDs as needed, but plots look strange over 5
        #output_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2025/comstock_amy2018_release_1'
        )

    # Stock Estimation for Apportionment:
    stock_estimate = cspp.Apportion(
        stock_estimation_version='2025R3',  # Only updated when a new stock estimate is published
        truth_data_version='v01',  # Typically don't change this
        reload_from_cache=True, # Set to "True" if you have already run apportionment and would like to keep consistant values between postprocessing runs.
        #output_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2025/comstock_amy2018_release_1'
    )

    # Scale ComStock runs to the 'truth data' from StockE V3 estimates using bucket-based apportionment
    base_sim_outs = comstock.get_sim_outs_for_upgrade(0)
    comstock.create_allocated_weights(stock_estimate, base_sim_outs, reload_from_cache=True)

    # CBECS
    cbecs = cspp.CBECS(
        cbecs_year=2018,  # 2012 and 2018 currently available
        truth_data_version='v01',  # Typically don't change this
        color_hex='#009E73',  # Color used to represent CBECS in plots
        reload_from_csv=True  # True if CSV already made and want faster reload times
        )

    # Scale ComStock to CBECS 2018 AND remove non-ComStock buildings from CBECS
    base_sim_outs = comstock.get_sim_outs_for_upgrade(0)
    alloc_wts = comstock.get_allocated_weights()
    comstock.create_allocated_weights_scaled_to_cbecs(cbecs, base_sim_outs, alloc_wts, remove_non_comstock_bldg_types_from_cbecs=True)

    # Add utility bills onto allocated weights
    for upgrade_id in comstock.upgrade_ids_to_process:
        # up_sim_outs = comstock.get_sim_outs_for_upgrade(upgrade_id)
        # up_alloc_wts = comstock.get_allocated_weights_scaled_to_cbecs_for_upgrade(upgrade_id)
         comstock.create_allocated_weights_plus_util_bills_for_upgrade(upgrade_id)

    # Export metadata files
    geo_exports = [
        #{'geo_top_dir': 'by_state_and_county',
        #    'partition_cols': {
        #        comstock.STATE_ABBRV: 'state',
        #        comstock.COUNTY_ID: 'county',
        #    },
        #    'aggregation_levels': ['in.nhgis_tract_gisjoin'], # , comstock.COUNTY_ID],  # Full tract resolution (agg=in.nhgis_tract_gisjoin)
        #    'data_types': ['full', 'basic'],
        #    'file_types': ['csv', 'parquet'],
        #},
        {'geo_top_dir': 'national_by_state',
           'partition_cols': {},
           'aggregation_levels': [[comstock.STATE_ABBRV, comstock.CZ_ASHRAE]],
           'data_types': ['full'], # other options: 'detailed', 'basic' **If using multiple options, order must go from more detailed to less detailed.
           'file_types': ['parquet'], # other options:'parquet'
        }
            ]

    #for geo_export in geo_exports:
    #    for upgrade_id in comstock.upgrade_ids_to_process:
    #        # if upgrade_id == 0:
    #        #     continue
    #        # comstock.export_metadata_and_annual_results_for_upgrade(upgrade_id, [geo_export])
    #        if comstock.make_timeseries_plots:
    #            s3_dir = f"s3://{comstock.s3_base_dir}/{comstock.comstock_run_name}/{comstock.comstock_run_name}"
    #            s3_output_dir = comstock.setup_fsspec_filesystem(s3_dir, aws_profile_name=None)
    #            comstock.export_metadata_and_annual_results_for_upgrade(upgrade_id=upgrade_id, geo_exports=[geo_export], output_dir=s3_output_dir)


    # write select results to S3 for Athena/Glue when needed for timeseries plots
    if comstock.make_timeseries_plots:
        s3_dir = f"s3://{comstock.s3_base_dir}/{comstock.comstock_run_name}/{comstock.comstock_run_name}"
        database = "enduse"
        dataset_name = f"{comstock.comstock_run_name}/{comstock.comstock_run_name}" # name of the dir in s3_dir we want to make new tables and views for
        crawler_name = comstock.comstock_run_name # used to set name of crawler, cannot include slashes
        workgroup = "eulp"  # Athena workgroup to use
        glue_service_role = "service-role/AWSGlueServiceRole-default"

        # Export parquet files to S3 for Athena/Glue
        # TODO: modify so that county data can be used for timeseries plots
        # TODO: Modify geo export structure to specify parquet files only for this part of the workflow
        #create_sightglass_tables(s3_location=f"{s3_dir}/metadata_and_annual_results_aggregates",
        #                            dataset_name=crawler_name,
        #                            database_name=database,
        #                            glue_service_role=glue_service_role)
        #fix_timeseries_tables(crawler_name, database)
        #create_views(crawler_name, database, workgroup)

    # Create measure run comparisons; only use if run has measures
    comparison = cspp.ComStockMeasureComparison(comstock, states=comstock.states, make_comparison_plots = comstock.make_comparison_plots, make_timeseries_plots = comstock.make_timeseries_plots)

    # Export dictionaries corresponding to the exported columns
    #comstock.export_data_and_enumeration_dictionary()

# Code to execute the script
if __name__=="__main__":
    main()
