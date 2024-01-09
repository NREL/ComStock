# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/bin/env/python3
# -*- coding: utf-8 -*-

import argparse
import logging
import pandas as pd
import os
import shutil
import tempfile
import time
import tsv_resampling_small_batch
import zipfile

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

def attempt_sampling(df_in, tsv_version, sim_year, buildstock_dir, sizing_arg):
    """
    Check to ensure necessary paths and files exist.  Alert user if they are not.  Then, loop through Pandas DataFrame\
    containing counties and the number of additional samples needed.  Call the gen_county_samples function within the\
    loop.
    :param df_in: Pandas DataFrame containing county id's and the number of additional samples required for each
    :param tsv_dir: Directory where tsv files are located
    :param buildstock_dir: Directory where county-specific buildstock.csv files are saved
    """
    # Check for valid simulation year
    if (sim_year < 2015) or (sim_year > 2019):
        raise RuntimeError(f'{sim_year} is not a valid simulation year. Choose a year between 2015 and 2019.')

    # Checking to ensure buildstock directory (buildstock_dir) is empty
    list_buildstock_dir = os.listdir(buildstock_dir)
    if len(list_buildstock_dir) != 0:
        raise RuntimeWarning(f'buildstock_dir `{buildstock_dir}` already contains files. This can affect the integrity of the sampling. Remove the files or select an empty directory for buildstock_dir.')

    # Checking to ensure tsv directory (tsv_dir) exists
    tsv_dir = os.path.abspath(os.path.join(os.path.dirname( __file__ ), 'tsvs', 'tsvs-{}'.format(tsv_version)))
    if not os.path.isfile(f'{tsv_dir}.zip'):
        raise IsADirectoryError(f'tsv_dir `{tsv_dir}.zip` does not exist.  Please specify valid file path.')

    tsv_dir_short = f'tsvs-{tsv_version}'

    # Iterate through counties that require more samples
    for i, row in df_in.iterrows():
        gen_county_samples(row, tsv_dir_short, tsv_dir, sim_year, buildstock_dir, sizing_arg)


# def gen_county_samples(row, tsv_dir_short, tsv_dir, sim_year, buildstock_dir, sizing_arg):
#     """
#     Run tsv_resampling_small_batch.py on a county-by-county basis for counties that require additional samples.\
#     For each county, copy the contents of the comstock_tsvs folder to temporary_folder for data manipulation.\
#     The county_id.tsv and climate_zone.tsv files are modified within temporary_folder.  In county_id.tsv, all\
#     probabilities are set to 0 except where the column is the county in question and the climate zone is that of where\
#     the county is located.  In climate_zone.tsv, all probabilities are set to 0 except the climate zone where the\
#     county is located.

#     These manipulated tsvs and the number of additional samples needed are passed to tsv_resampling_small_batch.py\
#     for county-specific sampling.  The output buildstock.csv is uniquely named with the county ID and saved in a\
#     separate folder.  temporary_folder is deleted, and the loop continues to the next county in need_more_samples.csv.
#     :param row: Specific row in file containing counties and number of additional samples
#     :param tsv_version: tsv version
#     :param tsv_dir: Directory where tsv files are located
#     :param sim_year: Simulation year (2012-2019)
#     :param buildstock_dir: Directory where county-specific buildstock.csv files are saved
#     """
#     county = row['county_id']
#     print('county =', county)

#     # Extract TSVs to temporary folder
#     tmp_dir = tempfile.mkdtemp()
#     with zipfile.ZipFile(f'{tsv_dir}.zip', 'r') as zipObj:
#         zipObj.extractall(tmp_dir)

#     # Import year_of_simulation, county_id and climate_zone to manipulate
#     year_of_simulation = pd.read_csv(os.path.join(tmp_dir, tsv_dir_short, 'year_of_simulation.tsv'), sep='\t', index_col=False)
#     county_id = pd.read_csv(os.path.join(tmp_dir, tsv_dir_short, 'county_id.tsv'), sep='\t', index_col=False)
#     climate_zone = pd.read_csv(os.path.join(tmp_dir, tsv_dir_short, 'climate_zone.tsv'), sep='\t', index_col=False)

#     # Zero out all probabilities except for the simulation year - change probability to 1
#     for col in year_of_simulation.columns:
#         if col == 'Option=' + str(sim_year):
#             year_of_simulation[col].values[:] = 1
#         elif col != 'Option=' + str(sim_year):
#             year_of_simulation[col].values[:] = 0

#     # Zero out all probabilities except for the county in question - change probability to 1
#     # Note location of non-zero probability for identifying the county's climate zone
#     y = 0
#     for col in county_id.columns:
#         if col == 'Dependency=climate_zone':
#             continue
#         elif col == 'Option=' + row['county_id']:
#             y = int(county_id[county_id[col] != 0].index[0])
#             county_id.loc[y, col] = 1
#         elif col != 'Option=' + row['county_id']:
#             county_id[col].values[:] = 0

#     # Identify climate zone county is located in
#     zone = county_id.iloc[y, 0]

#     # Zero all climate zones except zone county is located in
#     # Change probability to 1
#     for col in climate_zone.columns:
#         if col == ('Option=' + zone):
#             climate_zone[col].values[:] = 1
#         elif col != ('Option=' + zone):
#             climate_zone[col].values[:] = 0

#     # Write altered TSVs to temporary folder for use in tsv_resampling
#     year_of_simulation.to_csv(os.path.join(tmp_dir, tsv_dir_short, 'year_of_simulation.tsv'), sep='\t', index=False)
#     county_id.to_csv(os.path.join(tmp_dir, tsv_dir_short, 'county_id.tsv'), sep='\t', index=False)
#     climate_zone.to_csv(os.path.join(tmp_dir, tsv_dir_short, 'climate_zone.tsv'), sep='\t', index=False)

#     # Number of additional samples needed for this county
#     n_add_samples = int(row['additional_samples'])
#     print('number of samples =', n_add_samples)

#     # Run sampling for county
#     lock_dir = tempfile.mkdtemp()
#     sampler = tsv_resampling_small_batch.instantiate_sampler(
#         buildstock_dir,
#         n_add_samples,
#         os.path.join(tmp_dir, tsv_dir_short),
#         lock_dir
#     )
#     sampler.run_sampling(n_datapoints=n_add_samples, county_id=county, sizing_arg=sizing_arg)
#     time.sleep(1)

#     # Remove temporary folder
#     shutil.rmtree(tmp_dir)
#     shutil.rmtree(lock_dir)


def parse_arguments():
    """
    Create argument parser to run tsv_resampling_wrapper.  Include check to ensure county_spec_path exists.
    :return argument: Parser arguments to run the file
    """
    parser = argparse.ArgumentParser(description='Run tsv re-sampling file to up-sample specified counties')
    parser.add_argument('tsv_version', type=str, help='Version of tsvs to sample (e.g., v16)')
    parser.add_argument('sim_year', type=int, help='Year of simulation (2015 - 2019)')
    parser.add_argument('county_spec_path', type=str, help='File containing counties and additional number of samples')
    parser.add_argument('buildstock_dir', type=str, help='Empty folder in which to save county-specific buildstock.csv file(s)')
    parser.add_argument('hvac_sizing', type=str, help='Enter "autosize" or "hardsize" to indicate whether the models should have their HVAC systems autosized or hardsized')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enables verbose debugging outputs')
    argument = parser.parse_args()
    # Check to ensure county_spec_path exists
    if not os.path.isfile(argument.county_spec_path):
        raise FileExistsError(f'File specified for county_spec_path `{argument.county_spec_path}` does not exist.')
    if argument.verbose:
        logger.setLevel('DEBUG')
    return argument


if __name__ == '__main__':
    args = parse_arguments()
    for arg in vars(args):
        logger.debug(f'{arg} = {getattr(args, arg)}')
    # Import file that contains how many additional samples are needed for each county
    df = pd.read_csv(args.county_spec_path)
    logger.info('Attempting to run')
    # Call sampling function
    attempt_sampling(df, args.tsv_version, args.sim_year, args.buildstock_dir, args.hvac_sizing)
    logger.info('Unmitigated success!')
