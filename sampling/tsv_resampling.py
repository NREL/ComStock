# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import argparse
from copy import deepcopy
from datetime import datetime
from itertools import compress
from joblib import Parallel, delayed
import logging
from multiprocessing import Manager, cpu_count
import numpy as np
import os
import pandas as pd
import random
import shutil
import tempfile
from warnings import warn
import zipfile

from buildstockbatch.sampler.sobol_lib import i4_sobol_generate

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

class BuildStockSampler(object):

    def __init__(self, cfg, tsv_version, sim_year, project_dir):
        """
        Create the buildstock.csv file required for batch simulations using this class.

        Multiple sampling methods are available to support local & peregrine analyses, as well as to support multiple\
        sampling strategies. Currently there are separate implementations for commercial & residential stock types\
        due to unique requirements created by the commercial tsv set.

        :param cfg: YAML configuration specified by the user for the analysis
        :param tsv_version: The version of the tsv files to use, as specified by the user
        :param project_dir: The project directory within the OpenStudio-BuildStock repo
        """
        self.cfg = cfg
        self.tsv_version = tsv_version
        self.sim_year = sim_year
        self.buildstock_dir = f'tsvs-{tsv_version}'

        tmp_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(os.path.abspath(os.path.join(os.path.dirname( __file__ ), 'tsvs', f'tsvs-{tsv_version}.zip')), 'r') as zipObj:
            zipObj.extractall(tmp_dir)
        self.tmp_dir = tmp_dir
        self.tmp_output_dir = tmp_dir

        self.project_dir = project_dir

    def run_sampling(self, n_datapoints=None):
        """
        Execute the sampling generating the specified number of datapoints.

        This is a stub. It needs to be implemented in the child classes.

        :param n_datapoints: Number of datapoints to sample from the distributions.
        """
        raise NotImplementedError


class CommercialBaseSobolSampler(BuildStockSampler):

    def __init__(self, output_dir, tmp_output_dir, hvac_sizing, *args, **kwargs):
        """
        This class uses the Commercial Precomputed Sampler for Peregrine Singularity deployments

        :param output_dir: Directory in which to place buildstock.csv
        :param tmp_output_dir: Automatically created temporary directory in which the the tsv files are unzipped
        """
        super().__init__(*args, **kwargs)
        self.output_dir = output_dir
        self.tmp_output_dir = tmp_output_dir
        self.hvac_sizing = hvac_sizing

        # Create directory if output directory does not exist
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
            print("folder '{}' created ".format(self.output_dir))

    def set_sim_year(self):
        # Import tsv manipulate
        year_of_simulation = pd.read_csv(os.path.join(self.tmp_dir, self.buildstock_dir, 'year_of_simulation.tsv'), sep='\t', index_col=False)

        # Zero out all probabilities except for the simulation year - change probability to 1
        for col in year_of_simulation.columns:
            if col == 'Option=' + str(self.sim_year):
                year_of_simulation[col].values[:] = 1
            elif col != 'Option=' + str(self.sim_year):
                year_of_simulation[col].values[:] = 0

        # Write altered tsv to temporary folder for use in resampling
        year_of_simulation.to_csv(os.path.join(self.tmp_dir, self.buildstock_dir, 'year_of_simulation.tsv'), sep='\t', index=False)

    def run_sampling(self, n_datapoints=None):
        """
        Execute the sampling generating the specified number of datapoints.

        This is a stub. It needs to be implemented in the child classes for each deployment environment.

        :param n_datapoints: Number of datapoints to sample from the distributions.
        """
        tmp_csv_path = os.path.join(self.tmp_dir, self.tmp_output_dir, 'buildstock.csv')

        username = os.getlogin()
        now = datetime.now()
        date = now.strftime("%Y%m%d")
        csv_path = os.path.join(self.output_dir, 'buildstock' + '_' + date + '_' + self.tsv_version + '_' + str(self.sim_year) + '_' + username + '_' + str(n_datapoints) + '_' + self.hvac_sizing + '.csv')
        return self.run_sobol_sampling(n_datapoints, tmp_csv_path, csv_path)

    def run_sobol_sampling(self, n_datapoints, tmp_csv_path, csv_path):
        """
        Run the commercial sampling.

        This sampling method executes a sobol sequence to pre-compute optimally space-filling sample locations in the\
        unit hyper-cube defined by the set of TSV files & then spawns processes to evaluate each point in the sample\
        space given the input TSV set.

        :param n_datapoints: Number of datapoints to sample from the distributions.
        :param csv_path: Where to write the output CSV to - this is deployment dependent
        :return: Absolute path to the output buildstock.csv file
        """
        sample_number = self.cfg['baseline']['n_datapoints']
        if isinstance(n_datapoints, int):
            sample_number = n_datapoints
        logging.debug('Sampling, n_datapoints={}'.format(sample_number))

        self.set_sim_year()

        tsv_arrays = [
            [
                'building_type', 'state_id', 'county_id', 'year_of_simulation', 'region',
                'climate_zone', 'year_built', 'subtype', 'rentable_area', 'ground_thermal_conductivity'
            ],
            [
                'original_building_construction', 'window_wall_ratio', 'interior_lighting',
                'ownership_status', 'party_responsible_for_operation', 'purchase_input_responsibility',
                'owner_occupied', 'owner_type', 'purchasing_power', 'operator', 'occupied_by'
            ],
            [
                'base_peak_ratio', 'heating_fuel', 'hvac_night', 'hvac_system', 'hvac_tst', 'rotation', 'duration',
                'start_time', 'fault_economizer_damper_fully_closed', 'fault_economizer_db_limit',
                'energy_code_compliance_hvac', 'energy_code_in_force_during_last_hvac', 'energy_code_followed_during_last_hvac',
                'year_bin_of_last_hvac'
            ],
            [
                'cook', 'ground_thermal_conductivity', 'thermal_bridging', 'wall_construction', 'number_stories',
                'aspect_ratio', 'building_shape', 'airtightness'
            ],
            [
                'energy_code_compliance_interior_lighting', 'energy_code_followed_during_last_interior_lighting',
                'energy_code_in_force_during_last_interior_lighting', 'year_bin_of_last_interior_lighting', 'lighting_gen',
                'building_size_lighting_tech'
            ],
            [
                'exterior_lighting', 'roof', 'interior_equipment', 'baseline_window',
                'energy_code_compliance_w', 'energy_code_compliance_service',
                'energy_code_in_force_during_last_w', 'energy_code_in_force_during_last_service',
                'energy_code_followed_during_last_w', 'energy_code_followed_during_last_service',
                'year_bin_of_last_w', 'year_bin_of_last_service'
            ]
        ]

        n_tsvs = 0
        total_tsv_hash = {}
        for array in tsv_arrays:
            for tsv_file in os.listdir(os.path.join(self.tmp_dir, self.buildstock_dir)):
                if ('.tsv' in tsv_file) and (any(item in tsv_file for item in array)):
                    n_tsvs += 1
                    tsv_df = pd.read_csv(os.path.join(self.tmp_dir, self.buildstock_dir, tsv_file), sep='\t', keep_default_na=False)
                    dependency_columns = [item for item in list(tsv_df) if 'Dependency=' in item]
                    tsv_df[dependency_columns] = tsv_df[dependency_columns].astype('str')
                    total_tsv_hash[tsv_file.replace('.tsv', '')] = tsv_df

        for array in tsv_arrays:
            print(array)
            tsv_hash = {}
            for tsv_file in os.listdir(os.path.join(self.tmp_dir, self.buildstock_dir)):
                if ('.tsv' in tsv_file) and (any(item in tsv_file for item in array)):
                    tsv_df = pd.read_csv(os.path.join(self.tmp_dir, self.buildstock_dir, tsv_file), sep='\t', keep_default_na=False)
                    dependency_columns = [item for item in list(tsv_df) if 'Dependency=' in item]
                    tsv_df[dependency_columns] = tsv_df[dependency_columns].astype('str')
                    if len(dependency_columns) != 0:
                        tsv_df.set_index(dependency_columns, inplace=True)
                    tsv_hash[tsv_file.replace('.tsv', '')] = tsv_df
            # load in previous result csv, if it exists, and pass through to _com_execute_sample
            # treat it like the sample matrix -- pull out index row number, and dump each key value pair from the row from the previous sampling into the dependency hash
            if os.path.isfile(os.path.join(self.tmp_dir, self.buildstock_dir, 'buildstock.csv')):
                prev_results = pd.read_csv(os.path.join(self.tmp_dir, self.buildstock_dir, 'buildstock.csv'), index_col='Building', keep_default_na=False)
            else:
                prev_results = None
            dependency_hash, attr_order = self._com_order_tsvs(tsv_hash, tsv_arrays, total_tsv_hash, prev_results)
            sample_matrix = self._com_execute_sobol_sampling(attr_order.__len__(), sample_number)
            index_of_array = tsv_arrays.index(array)
            logger.info('Beginning sampling process')
            res = Parallel(n_jobs=1, verbose=5)(
                delayed(self._com_execute_sample)(tsv_hash, dependency_hash, attr_order, sample_matrix, index, total_tsv_hash, tsv_arrays, index_of_array, prev_results)
                for index in range(sample_number)
            )
            df = pd.DataFrame.from_dict(res)

            df['baseline_hvac_sizing'] = self.hvac_sizing

            df.index.name = 'Building'
            # save the intermediate buildstocks within the temporary directory and the final at the specified location.
            if array == tsv_arrays[-1]:
                df.to_csv(csv_path, index=True, na_rep='NA')
                shutil.rmtree(self.tmp_dir)
            else:
                df.to_csv(tmp_csv_path, index=True, na_rep='NA')
        return csv_path

    @staticmethod
    def _com_execute_sobol_sampling(n_dims, n_samples):
        """
        Execute a low discrepancy sampling of the unit hyper-cube defined by the n_dims input using the sobol sequence\
        methodology implemented by Corrado Chisari. Please refer to the sobol_lib.py file for license & attribution\
        details.
        :param n_dims: Number of dimensions, equivalent to the number of TSV files to be sampled from
        :param n_samples: Number of samples to calculate
        :return: Pandas DataFrame object which contains the low discrepancy result of the sobol algorithm
        """
        sample = i4_sobol_generate(n_dims, n_samples, 0)
        projected_sample = np.mod(sample + [random.random() for _ in range(len(sample[0]))], 1)
        return pd.DataFrame(projected_sample)

    @staticmethod
    def _com_order_tsvs(tsv_hash, tsv_arrays, total_tsv_hash, prev_results=None):
        """
        This method orders the TSV files to ensure that no TSV is sampled before its dependencies are. It also returns\
        a has of dependencies which are used in subsequent code to down-select TSVs based on previous sample results.
        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :return: A dictionary defining each TSVs required inputs, as well as the ordered list of TSV files for sampling
        """
        dependency_hash = {}
        for attr in tsv_hash.keys():
            dependency_hash[attr] = [name.replace('Dependency=', '') for name in tsv_hash[attr].index.names if
                                     'Dependency=' in str(name)]
        if prev_results is not None:
            prev_arrays = tsv_arrays[0]
            for prev_attr in total_tsv_hash.keys():
                if any(item in prev_attr for item in prev_arrays):
                    dependency_hash[prev_attr] = [item.replace('Dependency=', '') for item in list(total_tsv_hash[prev_attr]) if
                                                    'Dependency=' in item]
        attr_order = []
        for attr in dependency_hash.keys():
            if dependency_hash[attr] == []:
                attr_order.append(attr)
        max_iterations = 5
        while True:
            for attr in dependency_hash.keys():
                if attr in attr_order:
                    continue
                dependencies_met = True
                for dependency in dependency_hash[attr]:
                    if dependency not in attr_order:
                        dependencies_met = False
                if dependencies_met:
                    attr_order.append(attr)
            if dependency_hash.keys().__len__() == attr_order.__len__():
                break
            elif max_iterations > 0:
                max_iterations -= 1
            else:
                breakpoint()
                raise RuntimeError('Unable to resolve the dependency tree within the set iteration limit')
        return dependency_hash, attr_order


    @staticmethod
    def _com_execute_sample(tsv_hash, dependency_hash, attr_order, sample_matrix, sample_index, total_tsv_hash, tsv_arrays, n_array, prev_results=None):
        """
        This function evaluates a single point in the sample matrix with the provided TSV files & persists the result\
        of the sample to the CSV file specified. The provided lock ensures the file is not corrupted by multiple\
        instances of this method running in parallel.
        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :param dependency_hash: Dictionary defining each TSVs required inputs
        :param attr_order: List defining the order in which to sample TSVs in the tsv_hash
        :param sample_matrix: Pandas DataFrame specifying the points in the sample space to sample
        :param sample_index: Integer specifying which sample in the sample_matrix to evaluate
        """
        sample_vector = list(sample_matrix.loc[:, sample_index])
        sample_dependency_hash = deepcopy(dependency_hash)
        results_dict = dict()
        if prev_results is not None:
            sample_prev_result = prev_results.loc[sample_index]
            if n_array < 3:
                prev_arrays = tsv_arrays[n_array-1]
            elif n_array == 3:
                prev_arrays = tsv_arrays[n_array-1] + tsv_arrays[n_array-2]
            elif n_array == 4:
                prev_arrays = tsv_arrays[n_array-1] + tsv_arrays[n_array-2] + tsv_arrays[n_array-3]
            elif n_array == 5:
                prev_arrays = tsv_arrays[n_array-1] + tsv_arrays[n_array-2] + tsv_arrays[n_array-3] + tsv_arrays[n_array-4]
            prev_arrays = list(set(prev_arrays))
            for prev_attr in total_tsv_hash.keys():
                if any(item in prev_attr for item in prev_arrays):
                    sample_dependency_hash[prev_attr] = [item.replace('Dependency=', '') for item in
                                                         list(total_tsv_hash[prev_attr]) if 'Dependency=' in item]
        attr_order = []
        for attr in sample_dependency_hash.keys():
            if sample_dependency_hash[attr] == []:
                attr_order.append(attr)
        max_iterations = 5
        while True:
            for attr in sample_dependency_hash.keys():
                if attr in attr_order:
                    continue
                dependencies_met = True
                for dependency in sample_dependency_hash[attr]:
                    if dependency not in attr_order:
                        dependencies_met = False
                if dependencies_met:
                    attr_order.append(attr)
            if sample_dependency_hash.keys().__len__() == attr_order.__len__():
                break
            elif max_iterations > 0:
                max_iterations -= 1
            else:
                raise RuntimeError('Unable to resolve the dependency tree within the set iteration limit')
        # insert into sample_dependency, here
        sample_vector_index = -1
        for attr_index in range(len(attr_order)):
            attr = attr_order[attr_index]
            if (attr not in tsv_hash.keys()) and (prev_results is not None):
                attr_result = sample_prev_result[attr]
            else:
                sample_vector_index += 1
                tsv_lkup = tsv_hash[attr]
                tsv_dist_val = sample_vector[sample_vector_index]
                if tsv_lkup.shape[0] != 1:
                    index_lkup = list()
                    for dependency in [indexcol.replace('Dependency=', '') for indexcol in tsv_lkup.index.names]:
                        index_lkup.append(str(sample_dependency_hash[dependency]))
                    if len(index_lkup) > 1:
                        tsv_lkup = tsv_lkup.loc[tuple(index_lkup), :]
                    else:
                        tsv_lkup = tsv_lkup.loc[index_lkup[0], :]
                    if tsv_lkup.shape[0] == 0:
                        warn('TSV lookup reduced to 0 for {}, index {}, dep hash {}'.format(attr, sample_index,
                                                                                            sample_dependency_hash))
                        return
                    if (tsv_lkup.shape[0] != 1) and (len(tsv_lkup.shape) > 1):
                        raise RuntimeError('Unable to reduce tsv for {} to 1 row, index {}'.format(attr, sample_index))
                else:
                    tsv_lkup = tsv_lkup.iloc[0, :]
                tsv_lkup = tsv_lkup.astype(float)
                tsv_lkup_cdf = tsv_lkup.values.cumsum() > tsv_dist_val
                option_values = [item.replace('Option=', '') for item in list(tsv_lkup.index.values) if 'Option=' in item]
                attr_result = list(compress(option_values, tsv_lkup_cdf))[0]
            sample_dependency_hash[attr] = attr_result
            results_dict[attr] = attr_result
        return results_dict


def parse_arguments():
    """
    Create argument parser to run tsv_resampling.
    :return argument: Parser arguments to run the file
    """
    parser = argparse.ArgumentParser(description='Run tsv re-sampling file to generate national buildstock.csv')
    parser.add_argument('tsv_version', type=str, help='Version of tsvs to sample (e.g., v16)')
    parser.add_argument('sim_year', type=int, help='Year of simulation (2015 - 2019)')
    parser.add_argument('n_samples', type=int, help='Number of samples (full national run = 350000)')
    parser.add_argument('hvac_sizing', type=str, help='Enter "autosize" or "hardsize" to indicate whether the models should have their HVAC systems autosized or hardsized')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enables verbose debugging outputs')
    argument = parser.parse_args()

    if argument.verbose:
        logger.setLevel('DEBUG')
    return argument


def main():
    args = parse_arguments()
    for arg in vars(args):
        logger.debug(f'{arg} = {getattr(args, arg)}')

    sampler = CommercialBaseSobolSampler(
        tsv_version=args.tsv_version,
        sim_year=args.sim_year,
        output_dir=os.path.join('output-buildstocks', 'intermediate'),
        hvac_sizing=args.hvac_sizing,
        cfg={'baseline': {'n_datapoints': args.n_samples}},
        tmp_output_dir = f'tsvs-{args.tsv_version}',
        project_dir='/tmp/fake'
    )
    sampler.run_sampling(args.n_samples)



if __name__ == '__main__':
    main()
