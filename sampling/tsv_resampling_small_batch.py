# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
from copy import deepcopy
from itertools import compress
from joblib import Parallel, delayed
import logging
from multiprocessing import Manager, cpu_count
import numpy as np
from numpy.random import sample
import os
import pandas as pd
import random
from warnings import warn

from buildstockbatch.sampler.sobol_lib import i4_sobol_generate

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

class BuildStockSampler(object):

    def __init__(self, cfg, buildstock_dir, project_dir):
        """
        Create the buildstock.csv file required for batch simulations using this class.

        Multiple sampling methods are available to support local & peregrine analyses, as well as to support multiple\
        sampling strategies. Currently there are separate implementations for commercial & residential stock types\
        due to unique requirements created by the commercial tsv set.

        :param cfg: YAML configuration specified by the user for the analysis
        :param buildstock_dir: The location of the OpenStudio-BuildStock repo
        :param project_dir: The project directory within the OpenStudio-BuildStock repo
        """
        self.cfg = cfg
        self.buildstock_dir = buildstock_dir
        self.project_dir = project_dir

    def run_sampling(self, n_datapoints=None):
        """
        Execute the sampling generating the specified number of datapoints.

        This is a stub. It needs to be implemented in the child classes.

        :param n_datapoints: Number of datapoints to sample from the distributions.
        """
        raise NotImplementedError


class CommercialBaseSobolSampler(BuildStockSampler):

    def __init__(self, output_dir, *args, **kwargs):
        """
        This class uses the Commercial Precomputed Sampler for Peregrine Singularity deployments

        :param output_dir: Directory in which to place buildstock.csv
        """
        super().__init__(*args, **kwargs)
        self.output_dir = output_dir

    def run_sampling(self, n_datapoints=None, county_id=None, sizing_arg=None):
        """
        Execute the sampling generating the specified number of datapoints.

        This is a stub. It needs to be implemented in the child classes for each deployment environment.

        :param n_datapoints: Number of datapoints to sample from the distributions.
        :param county_id: County FIPS ID for saving buildstock.csv with a unique filename
        """
        csv_path = os.path.join(self.output_dir, f'buildstock_{county_id}_{sizing_arg}.csv')
        return self.run_sobol_sampling(n_datapoints, csv_path, sizing_arg)

    def run_sobol_sampling(self, n_datapoints, csv_path, sizing_arg):
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

        tsv_arrays = [
            [
                'building_type', 'state_id', 'county_id', 'year_of_simulation', 'region',
                'climate_zone', 'year_built', 'subtype', 'rentable_area'
            ],
            [
                'original_building_construction', 'window_wall_ratio', 'interior_lighting',
                'ownership_status', 'party_responsible_for_operation', 'purchase_input_responsibility',
                'owner_occupied', 'owner_type', 'purchasing_power', 'operator', 'occupied_by'
            ],
            [
                'aspect_ratio', 'building_shape', 'base_peak_ratio', 'heating_fuel', 'hvac_night',
                'hvac_system', 'hvac_tst', 'rotation', 'duration', 'start_time', 'number_stories',
                'wall_construction_type', 'airtightness', 'fault_economizer_damper_fully_closed', 'fault_economizer_db_limit',
                'energy_code_compliance_hvac', 'energy_code_in_force_during_last_hvac', 'energy_code_followed_during_last_hvac',
                'year_bin_of_last_hvac'
            ],
            [
                'cook'
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
            for tsv_file in os.listdir(self.buildstock_dir):
                if ('.tsv' in tsv_file) and (any(item in tsv_file for item in array)):
                    n_tsvs += 1
                    tsv_df = pd.read_csv(os.path.join(self.buildstock_dir, tsv_file), sep='\t', keep_default_na=False)
                    dependency_columns = [item for item in list(tsv_df) if 'Dependency=' in item]
                    tsv_df[dependency_columns] = tsv_df[dependency_columns].astype('str')
                    total_tsv_hash[tsv_file.replace('.tsv', '')] = tsv_df
        
        for array in tsv_arrays:
            print(array)
            tsv_hash = {}
            for tsv_file in os.listdir(self.buildstock_dir):
                if ('.tsv' in tsv_file) and (any(item in tsv_file for item in array)):
                    tsv_df = pd.read_csv(os.path.join(self.buildstock_dir, tsv_file), sep='\t', keep_default_na=False)
                    dependency_columns = [item for item in list(tsv_df) if 'Dependency=' in item]
                    tsv_df[dependency_columns] = tsv_df[dependency_columns].astype('str')
                    if len(dependency_columns) != 0:
                        tsv_df.set_index(dependency_columns, inplace=True)
                    tsv_hash[tsv_file.replace('.tsv', '')] = tsv_df
            if os.path.isfile(os.path.join(csv_path)):
                prev_results = pd.read_csv(os.path.join(csv_path), index_col='Building', keep_default_na=False)
            else:
                prev_results = None
            dependency_hash, attr_order = self._com_order_tsvs(tsv_hash, tsv_arrays, total_tsv_hash, prev_results)
            sample_matrix = self._com_execute_sobol_sampling(attr_order.__len__(), sample_number)
            logger.info('Beginning sampling process')
            # load in previous result csv, if it exists, and pass through to _com_execute_sample
            # treat it like the sample matrix -- pull out index row number, and dump each key value pair from the row from the previous sampling into the dependency hash
            res = Parallel(n_jobs=1, verbose=5)(
                delayed(self._com_execute_sample)(tsv_hash, dependency_hash, attr_order, sample_matrix, index, total_tsv_hash, tsv_arrays, tsv_arrays.index(array), prev_results)
                for index in range(sample_number)
            )
            df = pd.DataFrame.from_dict(res)
            df['baseline_hvac_sizing'] = sizing_arg
            df.index.name = 'Building'
            df.to_csv(csv_path, index=True, na_rep='NA')
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
                raise RuntimeError('Unable to resolve the dependency tree within the set iteration limit')
        return dependency_hash, attr_order

    @staticmethod
    def _com_execute_sample(tsv_hash, dependency_hash, attr_order, sample_matrix, sample_index, total_tsv_hash, tsv_arrays, n_array, prev_results):
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


def instantiate_sampler(buildstock_output_dir, n_additional_samples, tmp_directory, lockfile_directory):
    """
    Run sampler.
    :param buildstock_output_directory: Directory where county-specific buildstock.csv files are saved
    :param n_additional_samples: Number of additional samples for the county in question
    :param tmp_directory: Temporary directory where tsv files are copied (tmp)
    :param lockfile_directory: ?
    :return: CommercialBaseSobolSampler instance instantiated for inputs
    """
    sampler = CommercialBaseSobolSampler(
        buildstock_output_dir,
        {'baseline': {'n_datapoints': n_additional_samples}},
        tmp_directory,
        lockfile_directory
    )
    return sampler
