# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import argparse
import boto3
import botocore
from joblib import Parallel, delayed
import logging
import numpy as np
import os
import pandas as pd

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

pd.set_option('mode.chained_assignment', None)

def download_data(state):
    file_name = '{}_doe_tract.csv'.format(state)
    local_dir = os.path.join('truth_data', 'v01', 'spatial_dists_by_state')
    local_path = os.path.join(local_dir, file_name)
    s3_file_path = 'truth_data/v01/spatial_dists_by_state/{}'.format(file_name)
    bucket_name = 'eulp'

    s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))
    
    # Check if file exists, if it doesn't query from s3
    if not os.path.exists(local_path):
        print('Downloading %s from s3...' % file_name)
        # Download file
        bucket_name = 'eulp'
        s3_file_path = s3_file_path.replace('\\', '/')
        s3_client.download_file(bucket_name, s3_file_path, local_path)

    # Read file into memory
    try:
        df = pd.read_csv(local_path, low_memory=False)
    except UnicodeDecodeError:
        df = pd.read_csv(local_path, low_memory=False, encoding='latin-1')

    return df


def manual_fips_update(df_buildstock):
    """
    Due to discrepancies between Census years, county FIPS in spatial_tract_lookup_published_v6.csv do not
    exactly match the counties sampled in ComStock. This function is a manual FIPS update for these counties
    to ensure every sample in ComStock receives the proper geospatial fields in the metadata.

    These counties include (2010 Census): Bedford City County, Shannon County and Wrangell-Petersburg County
    """
    county_fips_map = {
        'G5105150': 'G5100190',         # Bedford City County changed to Bedford County
        'G4601130': 'G4601020',         # Shannon County, SD changed to Oglala Lakota County
        'G0202800': 'G0202750'          # Wrangell County, AK maps to Wrangell City and Borough
    }

    df_buildstock.replace({'county_id': county_fips_map}, inplace=True)

    return df_buildstock


def the_func(state, df_buildstock):
    # =========== Determine building size (large vs. not-large) in buildstock file ===========
    sqft = []
    for i, row in df_buildstock.iterrows():
        if row['rentable_area'] == '_1000':
            sqft.append(1000)
        elif row['rentable_area'] == '100001_200000':
            sqft.append(150000)
        elif row['rentable_area'] == '10001_25000':
            sqft.append(17500)
        elif row['rentable_area'] == '1001_5000':
            sqft.append(3000)
        elif row['rentable_area'] == '200001_500000':
            sqft.append(350000)
        elif row['rentable_area'] == '25001_50000':
            sqft.append(37500)
        elif row['rentable_area'] == '500001_1mil':
            sqft.append(750000)
        elif row['rentable_area'] == '50001_100000':
            sqft.append(75000)
        elif row['rentable_area'] == '5001_10000':
            sqft.append(7500)
        elif row['rentable_area'] == 'over_1mil':
            sqft.append(1e6)

    df_buildstock['sqft'] = sqft
    df_buildstock.loc[df_buildstock['sqft'] >= 100000, 'building_size'] = 'large'
    df_buildstock.loc[df_buildstock['sqft'] < 100000, 'building_size'] = 'not_large'

    # =========== Assign tracts to existing buildstock samples ===========
    df_tract = download_data(state)
    df_buildstock_state = df_buildstock.loc[df_buildstock['county_id'].str.contains('G{}'.format(state))].copy()

    # =========== Determine building size (large vs. not-large) ===========
    for i, row in df_tract.iterrows():
        if row.prototype == 'primary_school' or row.prototype == 'secondary_school' or row.prototype == 'hospital':
            df_tract.loc[df_tract.index == i, 'large_count'] = row['count']
            df_tract.loc[df_tract.index == i, 'not_large_count'] = 0
        else:
            if row.ra_min != row.ra_max:
                left = row.ra_min
                mode = row.ra_median
                right = row.ra_max
                size = int(row.ra_count)
                ra_dist = np.random.triangular(left, mode, right, size=size)
            else:
                ra_dist = [row.ra_median]
            
            large_count = sum(i >= 100000 for i in ra_dist)
            not_large_count = len(ra_dist) - large_count
            df_tract.loc[df_tract.index == i, 'large_count'] = large_count
            df_tract.loc[df_tract.index == i, 'not_large_count'] = not_large_count

    buildstock_groups = df_buildstock_state.groupby(['county_id', 'building_type', 'building_size']).groups
    for county, btype, size in buildstock_groups:
        num_samples = df_buildstock_state.loc[
            (df_buildstock_state.county_id == county) &
            (df_buildstock_state.building_type == btype) &
            (df_buildstock_state.building_size == size)
            ].shape[0]

        # Pull tracts within the given county and for the given building type
        df_tract_group = df_tract.loc[(df_tract.gisjoin.str.contains(county)) & (df_tract.prototype == btype)].copy()
        
        # Calculate probabilities for all building types in the county for use when there aren't building types available for the given tract
        df_tract_all_buildings = df_tract.loc[df_tract.gisjoin.str.contains(county)].copy()
        total_count_all = df_tract_all_buildings.large_count.agg('sum') + df_tract_all_buildings.not_large_count.agg('sum')
        df_tract_all_buildings.loc[:, 'probability'] = (df_tract_all_buildings['large_count'] + df_tract_all_buildings['not_large_count']) / total_count_all

        # If the building size is "large," calculate probabilities using the "large_count"
        if size == 'large':
            total_count = df_tract_group.large_count.agg('sum')
            if total_count == 0:
                random_samples = df_tract_all_buildings.loc[:, ['gisjoin', 'probability']].sample(n=num_samples, weights='probability', axis=0, replace=True)
            else:
                df_tract_group['large_probability'] = df_tract_group['large_count'] / total_count
                random_samples = df_tract_group.loc[:, ['gisjoin', 'large_probability']].sample(n=num_samples, weights='large_probability', axis=0, replace=True)
            df_buildstock_state.loc[(df_buildstock_state.county_id == county) & (df_buildstock_state.building_type == btype) & (df_buildstock_state.building_size == size), 'gisjoin'] = np.array(random_samples.gisjoin)
        # If the building size is "not_large," calculate probabilities using the "not_large_count"
        elif size == 'not_large':
            total_count = df_tract_group.not_large_count.agg('sum')
            if total_count == 0:
                if len(df_tract_all_buildings['probability']) == 0:
                    continue
                random_samples = df_tract_all_buildings.loc[:, ['gisjoin', 'probability']].sample(n=num_samples, weights='probability', axis=0, replace=True)
            else:
                df_tract_group['not_large_probability'] = df_tract_group['not_large_count'] / total_count
                random_samples = df_tract_group.loc[:, ['gisjoin', 'not_large_probability']].sample(n=num_samples, weights='not_large_probability', axis=0, replace=True)
            df_buildstock_state.loc[(df_buildstock_state.county_id == county) & (df_buildstock_state.building_type == btype) & (df_buildstock_state.building_size == size), 'gisjoin'] = np.array(random_samples.gisjoin)
    return df_buildstock_state


def parse_arguments():
    """
    Create argument parser to run assign-tracts-multiprocessing.  Include check to ensure the buildstock file includes a file extension.
    :return argument: Parser arguments to run the file
    """
    parser = argparse.ArgumentParser(description='Sample tracts on a county level to assign geospatial properties')
    parser.add_argument('buildstock_name', type=str, help='Name of buildstock.csv file in "output-buildstocks/intermediate"')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enables verbose debugging outputs')
    argument = parser.parse_args()
    # Check for ".csv" in buildstock name
    if '.csv' not in argument.buildstock_name:
        raise ValueError(f'buildstock_name "{argument.buildstock_name}" is missing the ".csv" file extension.')
    if argument.verbose:
        logger.setLevel('DEBUG')
    return argument


def main():
    args = parse_arguments()
    for arg in vars(args):
        logger.debug(f'{arg} = {getattr(args, arg)}')
    
    # Create directory if output directory does not exist
    if not os.path.exists(os.path.join('output-buildstocks', 'final')):
        os.makedirs(os.path.join('output-buildstocks', 'final'))
        print("folder '{}' created ".format(os.path.join('output-buildstocks', 'final')))
    # Create directory to download tract data to if it does not already exist
    local_dir = os.path.join('truth_data', 'v01', 'spatial_dists_by_state')
    if not os.path.isdir(local_dir):
        os.makedirs(local_dir)
        print("folder '{}' created ".format(local_dir))


    # Import buildstock.csv
    df_buildstock = pd.read_csv(os.path.join('output-buildstocks', 'intermediate', args.buildstock_name), index_col='Building', na_filter=False)
    
    # Manually update select FIPS codes due to Census year differences
    df_buildstock = manual_fips_update(df_buildstock)
    
    df_nan = df_buildstock.loc[df_buildstock['rentable_area'].isna()]
    df_buildstock = df_buildstock.loc[~df_buildstock['rentable_area'].isna()]
    
    state_fips = [
        '01', '02', '04', '05', '06', '08', '09', '10', '11', '12', '13', '15', '16', '17', '18', '19',
        '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32', '33', '34', '35',
        '36', '37', '38', '39', '40', '41', '42', '44', '45', '46', '47', '48', '49', '50', '51', '53',
        '54', '55', '56'
        ]
    res = pd.concat(Parallel(n_jobs=-1, verbose=10, prefer='threads')(delayed(the_func)(state, df_buildstock) for state in state_fips))
    res_total = pd.concat([res, df_nan])
    df_geospatial_lkup = pd.read_csv(os.path.join('resources', 'spatial_tract_lookup_table_publish_v6.csv'))
    df_results_geospatial = res_total.merge(df_geospatial_lkup, left_on='gisjoin', right_on='nhgis_tract_gisjoin', how='left')
    df_results_geospatial.drop(['sqft', 'building_size', 'gisjoin'], axis=1, inplace=True)
    df_results_geospatial.index = np.linspace(1, len(df_results_geospatial), len(df_results_geospatial)).astype(int)
    df_results_geospatial.index.name = 'Building'

    df_results_geospatial.to_csv(os.path.join('output-buildstocks', 'final', args.buildstock_name), na_rep='NA', index='Building')


if __name__ == '__main__':
    main()
