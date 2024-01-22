# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import argparse
from copy import deepcopy
from datetime import datetime
import json
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
        self.tsv_dirname = f'tsvs-{tsv_version}'

        tmp_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(
            os.path.abspath(os.path.join(os.path.dirname(__file__), 'tsvs', f'tsvs-{tsv_version}.zip')), 'r'
        ) as zipObj:
            zipObj.extractall(tmp_dir)
        self.tmp_dir = tmp_dir

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

        self.sample_number = self.cfg.get('baseline', {}).get('n_datapoints', 0)

    TSV_ARRAYS = [
        [
            'building_area', 'building_type', 'sampling_region', 'size_bin'
        ],
        [
            'number_stories', 'tract', 'year_built'
        ],
        [
            'building_subtype', 'census_region', 'climate_zone', 'county_id', 'ground_thermal_conductivity', 'state_id', 'year_of_simulation'
        ],
        [
            'energy_code_compliance_during_original_building_construction', 'energy_code_followed_during_original_building_construction', 'energy_code_in_force_during_original_building_construction', 'ownership_status', 'party_responsible_for_operation', 'purchase_input_responsibility', 'window_wall_ratio', 'year_bin_of_original_building_construction'
        ],
        [
            'airtightness', 'aspect_ratio', 'building_shape', 'heating_fuel', 'hvac_system_type', 'rotation', 'service_water_heating_fuel', 'wall_construction_type', 'weekday_duration', 'weekday_start_time', 'weekend_duration', 'weekend_start_time'
        ],
        [
            'energy_code_compliance_hvac', 'energy_code_followed_during_last_hvac_replacement', 'energy_code_in_force_during_last_hvac_replacement', 'fault_economizer_damper_fully_closed', 'fault_economizer_db_limit', 'hvac_night_variability', 'hvac_tst_clg_delta_f', 'hvac_tst_clg_sp_f', 'hvac_tst_htg_delta_f', 'hvac_tst_htg_sp_f', 'year_bin_of_last_hvac_replacement'
        ],
        [
            'cook_broiler_counts', 'cook_dining_type', 'cook_fryers_counts', 'cook_fuel_broiler', 'cook_fuel_fryer', 'cook_fuel_griddle', 'cook_fuel_oven', 'cook_fuel_range', 'cook_fuel_steamer', 'cook_griddles_counts', 'cook_ovens_counts', 'cook_ranges_counts', 'cook_steamers_counts'
        ],
        [
            'energy_code_compliance_service_water_heating', 'energy_code_compliance_interior_equipment', 'energy_code_followed_during_last_interior_equipment_replacement', 'energy_code_followed_during_last_service_water_heating_replacement', 'energy_code_in_force_during_last_interior_equipment_replacement', 'energy_code_in_force_during_last_service_water_heating_replacement', 'plugload_sch_base_peak_ratio_type', 'plugload_sch_weekday_base_peak_ratio', 'plugload_sch_weekend_base_peak_ratio', 'year_bin_of_last_interior_equipment_replacement', 'year_bin_of_last_service_water_heating_replacement'
        ],
        [
            'building_size_lighting_tech', 'energy_code_compliance_exterior_lighting', 'energy_code_compliance_interior_lighting', 'energy_code_followed_during_last_exterior_lighting_replacement', 'energy_code_followed_during_last_interior_lighting_replacement', 'energy_code_in_force_during_last_exterior_lighting_replacement', 'energy_code_in_force_during_last_interior_lighting_replacement', 'lighting_generation', 'ltg_sch_base_peak_ratio_type', 'ltg_sch_weekday_base_peak_ratio', 'ltg_sch_weekend_base_peak_ratio', 'year_bin_of_last_exterior_lighting_replacement', 'year_bin_of_last_interior_lighting_replacement'
        ],
        [
            'energy_code_compliance_roof', 'energy_code_compliance_walls', 'energy_code_compliance_windows', 'energy_code_followed_during_last_roof_replacement', 'energy_code_followed_during_last_walls_replacement', 'energy_code_followed_during_last_windows_replacement', 'energy_code_in_force_during_last_roof_replacement', 'energy_code_in_force_during_last_walls_replacement', 'energy_code_in_force_during_last_windows_replacement', 'year_bin_of_last_roof_replacement', 'year_bin_of_last_walls_replacement', 'year_bin_of_last_windows_replacement'
        ]
    ]

    def set_sim_year(self):
        # Import tsv manipulate
        year_of_simulation = pd.read_csv(
            os.path.join(self.tmp_dir, self.tsv_dirname, 'year_of_simulation.tsv'), sep='\t', index_col=False
        )

        # Zero out all probabilities except for the simulation year - change probability to 1
        for col in year_of_simulation.columns:
            if col == 'Option=' + str(self.sim_year):
                year_of_simulation[col].values[:] = 1
            elif col != 'Option=' + str(self.sim_year):
                year_of_simulation[col].values[:] = 0

        # Write altered tsv to temporary folder for use in resampling
        year_of_simulation.to_csv(
            os.path.join(self.tmp_dir, self.tsv_dirname, 'year_of_simulation.tsv'), sep='\t', index=False
        )

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
        if n_datapoints is not None:
            self.sample_number = n_datapoints
        if self.sample_number == 0:
            raise RuntimeError('No valid sample number specified in the run_sampling invocation or configuration.')
        csv_path = os.path.join(
            self.output_dir, 'buildstock' + '_' + date + '_' + self.tsv_version + '_' + str(self.sim_year) + '_' + \
            username + '_' + str(self.sample_number) + '_' + self.hvac_sizing + '.csv'
        )
        return self.run_sobol_sampling(tmp_csv_path, csv_path)

    def load_tsvs(self, attrs, tsv_dir, previously_sampled_attrs, load_jsons=False):
        """_summary_

        :param tsv_dir: _description_
        :type tsv_dir: _type_
        :param previously_sampled_attrs: _description_
        :type previously_sampled_attrs: _type_
        """

        tsv_hash = {}

        if load_jsons:
            for attr in attrs:
                with open(os.path.join(tsv_dir, attr + '.json'), 'r') as rfobj:
                    tsv_hash[attr] = json.load(rfobj)
            attr_order = self.TSV_ARRAYS[0] + ['tract', 'year_built', 'number_stories']
            dependency_hash = {
                'tract': ['sampling_region', 'building_type', 'size_bin'],
                'year_built': ['sampling_region', 'building_type', 'size_bin'],
                'number_stories': ['sampling_region', 'building_type', 'size_bin']
            }
            for attr in self.TSV_ARRAYS[0]:
                dependency_hash[attr] = list()
        else:
            for attr in attrs:
                tsv_df = pd.read_csv(os.path.join(tsv_dir, attr + '.tsv'), sep='\t', keep_default_na=False)
                dependency_columns = [item for item in list(tsv_df) if 'Dependency=' in item]
                tsv_df[dependency_columns] = tsv_df[dependency_columns].astype('str')
                tsv_hash[attr] = tsv_df
            dependency_hash, attr_order = self._com_order_tsvs(tsv_hash, previously_sampled_attrs)

        return tsv_hash, dependency_hash, attr_order

    def run_sobol_sampling(self, tmp_csv_path, csv_path):
        """
        Run the commercial sampling.

        This sampling method executes a sobol sequence to pre-compute optimally space-filling sample locations in the
        unit hyper-cube defined by the set of TSV files & then spawns processes to evaluate each point in the sample
        space given the input TSV set.

        :param csv_path: Where to write the output CSV to - this is deployment dependent
        :return: Absolute path to the output buildstock.csv file

        """

        self.set_sim_year()

        rw_dir = os.path.join(self.tmp_dir, self.tsv_dirname)
        for attrs_to_sample in self.TSV_ARRAYS:
            print(f'Preparing sampling for the following attributes: {attrs_to_sample}')
            jsons = False
            if 'tract' in attrs_to_sample:
                jsons = True
            # load in previous result csv, if it exists, and pass through to _com_execute_sample
            # treat it like the sample matrix -- pull out index row number, and dump each key value pair from the row from the previous sampling into the dependency hash
            if os.path.isfile(os.path.join(rw_dir, 'buildstock.csv')):
                prev_results = pd.read_csv(
                    os.path.join(rw_dir, 'buildstock.csv'), index_col='Building', keep_default_na=False
                )
            else:
                prev_results = pd.DataFrame()

            tsv_hash, dependency_hash, attr_order = self.load_tsvs(attrs_to_sample, rw_dir, list(prev_results), jsons)
            sample_matrix = self._com_execute_sobol_sampling(len(attrs_to_sample), self.sample_number)
            sample_dict = sample_matrix.to_dict(orient='list')
            prev_results_dict = prev_results.to_dict(orient='index')
            res = dict()
            if jsons:
                for index in range(self.sample_number):
                    res[index] = self._com_execute_json_sample(
                        tsv_hash, dependency_hash, attr_order, sample_dict[index], prev_results_dict.get(index, dict())
                    )
            else:
                for index in range(self.sample_number):
                    res[index] = self._com_execute_sample(
                        tsv_hash, dependency_hash, attr_order, sample_dict[index], prev_results_dict.get(index, dict())
                    )
                # res = Parallel(n_jobs=1, verbose=5)(
                #     delayed(self._com_execute_sample)(
                #         tsv_hash, dependency_hash, attr_order, sample_dict[index], prev_results_dict.get(index, dict())
                #     ) for index in range(self.sample_number)
                # )
            df = pd.DataFrame.from_dict(res).transpose()
            # breakpoint()

            df.index.name = 'Building'

            # Save the intermediate buildstock csvs within the temporary directory and the final at the specified location
            if attrs_to_sample == self.TSV_ARRAYS[-1]:
                df.loc[:, 'baseline_hvac_sizing'] = self.hvac_sizing
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
    def _com_order_tsvs(tsv_hash, prev_attrs):
        """
        This method orders the TSV files to ensure that no TSV is sampled before its dependencies are. It also returns\
        a has of dependencies which are used in subsequent code to down-select TSVs based on previous sample results.
        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :return: A dictionary defining each TSVs required inputs, as well as the ordered list of TSV files for sampling
        """

        dependency_hash = {}

        # For each attribute in the tsv_hash create a key of the attribute name where the values are a list of attributes the key attribute is dependent on, should any exist, otherwise an empty list
        for attr in tsv_hash.keys():
            dependency_hash[attr] = [
                name.replace('Dependency=', '') for name in list(tsv_hash[attr]) if 'Dependency=' in str(name)
            ]

        # For all previously sampled attributes set their dependence to nothing, since they've already been sampled
        for prev_attr in prev_attrs:
            dependency_hash[prev_attr] = list()
        # Add all attributes that have no dependencies to the attribute order first, as they can be sampled / retrieved from previous samples in any order 
        attr_order = []
        for attr in dependency_hash.keys():
            if len(dependency_hash[attr]) == 0:
                attr_order.append(attr)

        # Iteratively (up to five times) step through the dependency hash, identifying previously ordered attributes, and when possible adding attributes whose dependency set is already ordered
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
                raise RuntimeError(
                    'Unable to resolve the dependency tree within the set iteration limit. The following TSV files '\
                    f'were not resolved within 5 iterations: {set(dependency_hash.keys()) - set(attr_order)}'
                )
            
        # Return the dependency hash and attribute order
        return dependency_hash, attr_order
        
    
    @staticmethod
    def _com_execute_sample(tsv_hash, dependency_hash, attr_order, sample_vector, prev_results=dict()):
        """
        This function evaluates a single point in the sample matrix with the provided TSV files & persists the result\
        of the sample to the CSV file specified. The provided lock ensures the file is not corrupted by multiple\
        instances of this method running in parallel.
        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :param dependency_hash: Dictionary defining each TSVs required inputs
        :param attr_order: List defining the order in which to sample TSVs in the tsv_hash
        :param sample_vector: Pandas DataFrame specifying the points in the sample space to sample
        :param sample_index: Integer specifying which sample in the sample_matrix to evaluate
        """
        dep_hash = deepcopy(dependency_hash)
        results_dict = dict()
        sample_vector_index = -1
        for attr in attr_order:
            if attr in prev_results.keys():
                attr_result = prev_results[attr]
            else:
                sample_vector_index += 1
                tsv_lkup = tsv_hash[attr]
                tsv_dist_val = sample_vector[sample_vector_index]
                if tsv_lkup.shape[0] != 1:
                    for dep in dep_hash[attr]:
                        dep_col = 'Dependency=' + dep
                        tsv_lkup = tsv_lkup.loc[
                            tsv_lkup.loc[:, dep_col] == str(dep_hash[dep]), [col for col in list(tsv_lkup) if col != dep_col]
                        ]
                    if tsv_lkup.shape[0] == 0:
                        warn('TSV lookup reduced to 0 for {}, dep hash {}'.format(attr, dep_hash))
                        breakpoint()
                        return
                    if (tsv_lkup.shape[0] != 1) and (len(tsv_lkup.shape) > 1):
                        raise RuntimeError('Unable to reduce tsv for {} to 1 row, dep_hash {}'.format(attr, dep_hash))
                    tsv_lkup = tsv_lkup.transpose()
                else:
                    tsv_lkup = tsv_lkup.iloc[0, :]
                tsv_lkup = tsv_lkup.astype(float)
                attr_result = tsv_lkup[tsv_lkup.values.cumsum() > tsv_dist_val].index[0].replace('Option=', '')
            dep_hash[attr] = attr_result
            results_dict[attr] = attr_result
        return results_dict


    @staticmethod
    def _com_execute_json_sample(json_set, dependency_hash, attr_order, sample_vector, prev_results=dict()):
        """
        This function evaluates a single point in the sample matrix with the provided TSV files & persists the result\
        of the sample to the CSV file specified. The provided lock ensures the file is not corrupted by multiple\
        instances of this method running in parallel.
        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :param dependency_hash: Dictionary defining each TSVs required inputs
        :param attr_order: List defining the order in which to sample TSVs in the tsv_hash
        :param sample_vector: Pandas DataFrame specifying the points in the sample space to sample
        :param sample_index: Integer specifying which sample in the sample_matrix to evaluate
        """
        dep_hash = deepcopy(dependency_hash)
        results_dict = dict()
        sample_vector_index = -1
        for attr in attr_order:
            if attr in prev_results.keys():
                attr_result = prev_results[attr]
            else:
                sample_vector_index += 1
                attr_dict = json_set[attr]
                tsv_dist_val = sample_vector[sample_vector_index]
                for dep in dep_hash[attr]:
                    attr_dict = attr_dict[str(dep_hash[dep])]
                attr_series = pd.Series(attr_dict).astype(float)
                attr_result = attr_series[attr_series.values.cumsum() > tsv_dist_val].index[0].replace('Option=', '')
            dep_hash[attr] = attr_result
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
