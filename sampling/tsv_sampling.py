# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import argparse
from copy import deepcopy
from datetime import datetime
import json
from joblib import Parallel, delayed
import logging
from multiprocessing import cpu_count
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

class ComStockBaseSampler:

    def __init__(
            self, tsv_version, sim_year, output_dir, hvac_sizing, n_datapoints, n_buckets, sobol,
            precomputed_sample=False
        ):
        """Create a sample for ComStock based off of the user provided inputs

        :param tsv_version: version of the TSV files to use, specified as 'vNN' in the TSV zip file
        :type tsv_version: str
        :param sim_year: year of stock to simulate (not weather year but stock year)
        :type sim_year: int
        :param cfg: optional configuration parameters passed - a vestige of buildstockbatch. See the main method in this
            file for additional details.
        :type cfg: dictionary
        :param output_dir: directory to write resulting csv file to
        :type output_dir: str
        :param hvac_sizing: string input of "autosize" or "hardsize"
        :type hvac_sizing: str
        :param n_datapoints: number of datapoints (i.e. rows) to run - this must be divisible by n_buckets
        :type n_datapoints: int
        :param n_buckets: number of buckets or chunks to subdivide the sampling by. This is entirely for performance.
        :type n_buckets: int
        :param sobol: if True use a Sobol low discrepancy sequence, otherwise use pseudorandom
        :type sobol: bool
        :param precomputed_sample: path to input file to use to pre-specify input, defaults to False
        :type precomputed_sample: bool or str, optional

        """

        self.tsv_version = tsv_version
        self.sim_year = sim_year
        self.output_dir = output_dir
        self.hvac_sizing = hvac_sizing
        self.tsv_dirname = f'tsvs-{self.tsv_version}'

        # Process and validate the sampling arguments
        self.sample_number = n_datapoints
        self.n_buckets = n_buckets
        self.sobol = sobol
        self._process_sampling_inputs()

        # Set up the directory structures required
        self._instantiate_folder_structures()

        # If there is a precomputed sample provided validate and process
        if precomputed_sample:
            self._process_precomputed_buildstock_sample(precomputed_sample)

    TSV_ARRAYS = [
        [
            'building_area', 'building_type', 'sampling_region', 'size_bin'
        ],
        [
            'number_stories', 'tract', 'year_built', 'state_id', 'county_id'
        ],
        [
            'building_subtype', 'census_region', 'climate_zone', 'ground_thermal_conductivity', 'year_of_simulation'
        ],
        [
            'energy_code_compliance_during_original_building_construction',
            'energy_code_followed_during_original_building_construction',
            'energy_code_in_force_during_original_building_construction', 'ownership_status',
            'party_responsible_for_operation', 'purchase_input_responsibility', 'window_wall_ratio',
            'year_bin_of_original_building_construction'
        ],
        [
            'airtightness', 'aspect_ratio', 'building_shape', 'heating_fuel', 'hvac_system_type', 'rotation',
            'service_water_heating_fuel', 'wall_construction_type', 'weekday_duration', 'weekday_start_time',
            'weekend_duration', 'weekend_start_time', 'thermal_bridging'
        ],
        [
            'energy_code_compliance_hvac', 'energy_code_followed_during_last_hvac_replacement',
            'energy_code_in_force_during_last_hvac_replacement', 'fault_economizer_damper_fully_closed',
            'fault_economizer_db_limit', 'hvac_night_variability', 'hvac_tst_clg_delta_f', 'hvac_tst_clg_sp_f',
            'hvac_tst_htg_delta_f', 'hvac_tst_htg_sp_f', 'year_bin_of_last_hvac_replacement'
        ],
        [
            'cook_broiler_counts', 'cook_dining_type', 'cook_fryers_counts', 'cook_fuel_broiler', 'cook_fuel_fryer',
            'cook_fuel_griddle', 'cook_fuel_oven', 'cook_fuel_range', 'cook_fuel_steamer', 'cook_griddles_counts',
            'cook_ovens_counts', 'cook_ranges_counts', 'cook_steamers_counts'
        ],
        [
            'energy_code_compliance_service_water_heating', 'energy_code_compliance_interior_equipment',
            'energy_code_followed_during_last_interior_equipment_replacement',
            'energy_code_followed_during_last_service_water_heating_replacement',
            'energy_code_in_force_during_last_interior_equipment_replacement',
            'energy_code_in_force_during_last_service_water_heating_replacement', 'plugload_sch_base_peak_ratio_type',
            'plugload_sch_weekday_base_peak_ratio', 'plugload_sch_weekend_base_peak_ratio',
            'year_bin_of_last_interior_equipment_replacement', 'year_bin_of_last_service_water_heating_replacement'
        ],
        [
            'building_size_lighting_tech', 'energy_code_compliance_exterior_lighting',
            'energy_code_compliance_interior_lighting',
            'energy_code_followed_during_last_exterior_lighting_replacement',
            'energy_code_followed_during_last_interior_lighting_replacement',
            'energy_code_in_force_during_last_exterior_lighting_replacement',
            'energy_code_in_force_during_last_interior_lighting_replacement', 'lighting_generation',
            'ltg_sch_base_peak_ratio_type', 'ltg_sch_weekday_base_peak_ratio', 'ltg_sch_weekend_base_peak_ratio',
            'year_bin_of_last_exterior_lighting_replacement', 'year_bin_of_last_interior_lighting_replacement'
        ],
        [
            'energy_code_compliance_roof', 'energy_code_compliance_walls', 'energy_code_compliance_windows',
            'energy_code_followed_during_last_roof_replacement', 'energy_code_followed_during_last_walls_replacement',
            'energy_code_followed_during_last_windows_replacement', 'energy_code_in_force_during_last_roof_replacement',
            'energy_code_in_force_during_last_walls_replacement',
            'energy_code_in_force_during_last_windows_replacement', 'year_bin_of_last_roof_replacement',
            'year_bin_of_last_walls_replacement', 'year_bin_of_last_windows_replacement', 'baseline_window_type'
        ]
    ]
    """List of lists of attributes / tsv (or json) files to sample iteratively. This list of lists must be manually
    updated as additional TSV / json files are added to the TSV set over time. Note that the full filename (excepting
    the extension) needs to be included / provided, i.e. listing 'cook_' will no longer result in all cooking related
    TSVs being included.
    """

    def _process_sampling_inputs(self):
        """Read the sampling configuration arguments passed and validate them.
        """

        if self.sample_number == 0:
            raise RuntimeError('Sample number set to 0. Please ensure non-zero sample number.')
        if self.n_buckets == 0:
            raise RuntimeError('Number or buckets set to 0. Please ensure non-zero number of buckets.')
        if self.sample_number % self.n_buckets != 0:
            raise RuntimeError('Number of samples divided by number of buckets results in non-zero remainder.')

    def _instantiate_folder_structures(self):
        """Create the tmpdir used for tsv files and ensure the output directory exists.
        """

        # Create a tmp directory for unzipping the tsv zip file
        tmp_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(
            os.path.abspath(os.path.join(os.path.dirname(__file__), 'tsvs', f'tsvs-{self.tsv_version}.zip')), 'r'
        ) as zipObj:
            zipObj.extractall(tmp_dir)
        self.tmp_dir = tmp_dir

        # Create directory if output directory does not exist
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
            print("folder '{}' created ".format(self.output_dir))

    def _process_precomputed_buildstock_sample(self, precomputed_path):
        """Validate the provided precomputed sample file and save it for the sampler.

        :param precomputed_path: Path to the precomputed CSV file
        :type precomputed_path: str

        """

        # If the precomputed sample exists validate it and save in the appropriate folder
        if os.path.isfile(precomputed_path):
            tmp_df = pd.read_csv(precomputed_path, index_col='Building')
            # Validate the sample number matches between the precomputed sample and the user inputs
            if tmp_df.shape[0] != self.sample_number:
                raise RuntimeError(
                    f'Precomputed sample at {precomputed_path} has {tmp_df.shape[0]} samples, but was '\
                    f'expecting {self.sample_number} samples'
                )
            precomputed_buildstock_path = os.path.join(self.tmp_dir, self.tsv_dirname, 'buildstock.csv')
            if tmp_df.index.name != 'Building':
                tmp_df = tmp_df.reset_index(drop=True)
                tmp_df.index.name = 'Building'
            tmp_df.to_csv(precomputed_buildstock_path, index=True, na_rep='NA')
        else:
            raise FileNotFoundError(f'Unable to find precomputed CSV {precomputed_path}')

    def _set_sim_year(self):
        """Edit the year_of_simulation TSV file in the tmpdir to match user defined value.
        """

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

    def run_sampling(self):
        """Execute the sampling methodology to generate the user specified number of datapoints.
        """

        tmp_csv_path = os.path.join(self.tmp_dir, self.tsv_dirname, 'buildstock.csv')

        username = os.getlogin()
        now = datetime.now()
        date = now.strftime("%Y%m%d-%H%m")
        if self.sample_number <= 0:
            raise RuntimeError('No valid sample number specified in the run_sampling invocation or configuration.')
        csv_path = os.path.join(
            self.output_dir, 'buildstock' + '_' + date + '_' + self.tsv_version + '_' + str(self.sim_year) + '_' + \
            username + '_' + str(self.sample_number) + '_' + self.hvac_sizing + '.csv'
        )
        return self._run_sampling(tmp_csv_path, csv_path)

    def _load_tsvs(self, attrs, tsv_dir, previously_sampled_attrs, load_jsons=False):
        """Create a dictionary of dataframes of TSV files, and optionally JSON attribute files, with order metadata.

        Load the individual files specified by the attrs input parameter. If the load_jsons optional is set to True then
        load the tract based JSON files instead. This method then calls the _com_order_tsvs method to calculate
        necessary metadata on the the required ordering of attributes and the dependency_hash data structure used to
        iteratively record sampling outcomes and provide inputs for dependency values.

        :param attrs: tsv file names as strings to retrieve data from
        :type attrs: list
        :param tsv_dir: directory of the unzipped TSV folder
        :type tsv_dir: str
        :param previously_sampled_attrs: tsv files already sampled prior to the current set defined in attrs
        :type previously_sampled_attrs: list
        :param load_jsons: flag to load nested tract-based json files in place of flat TSV files
        :type load_jsons: bool

        """

        tsv_hash = {}

        if load_jsons:
            for attr in [item for item in attrs if '_id' not in item]: # skip county_id and state_id
                with open(os.path.join(tsv_dir, attr + '.json'), 'r') as rfobj:
                    tsv_hash[attr] = json.load(rfobj)
            attr_order = previously_sampled_attrs + ['tract', 'year_built', 'number_stories']
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

    def _run_sampling(self, tmp_csv_path, csv_path):
        """Iteratively execute the sampling process stepping through the TSV_ARRAYS class variable.

        This method implements the iterative process used to generate a sample of all TSVs and JSON files used to define
        the probabilistic representation of building attributes within ComStock. These attributes are grouped into
        manageable memory footprint groups based on the network of dependencies (i.e. if state depends on tract then
        state cannot be in a group that preceded tract) and then sampled. Due to the dependency of future distributions
        on present / past results the cumulative intermediary of results is persisted and provided to each subsequent
        iteration.

        Within each iteration the first step is to load the cumulative results of the previous iterations, or nothing
        in the case of the first iteration. The dependency network for the TSVs or JSONs specified in the TSV_ARRAY is
        then solved and the required distributions loaded into memory. This sampling method uses either a sobol sequence
        or pseudorandom algorithm  based on user input to sample locations in the unit hyper-cube defined by the set of
        TSV  (& JSON) files. Following this sampling process the task of placing values into the sample space given the
        input TSV set is dispatched as a parallelized chucked list using joblib. Finally the results are pulled back
        into a dataframe and written to disk for use in the next sub-list in TSV_ARRAYS.

        :param tmp_csv_path: Temporary directory to write intermediary cumulative results to
        :type tmp_csv_path: str
        :param csv_path: Where to write the output CSV to
        :type csv_path: str
        :return: csv_path input
        :rtype: str

        """

        self._set_sim_year()

        rw_dir = os.path.join(self.tmp_dir, self.tsv_dirname)
        for attrs_to_sample in self.TSV_ARRAYS:
            print(f'Preparing sampling for the following attributes: {attrs_to_sample}')
            jsons = False
            if 'tract' in attrs_to_sample:
                jsons = True

            # load in previous result csv, if it exists, and pass through to _com_execute_sample
            # treat it like the sample matrix -- pull out index row number, and dump each key value pair from the row
            # from the previous sampling into the dependency hash
            if os.path.isfile(os.path.join(rw_dir, 'buildstock.csv')):
                prev_results = pd.read_csv(
                    os.path.join(rw_dir, 'buildstock.csv'), index_col='Building', keep_default_na=False
                )
                prev_results = np.array_split(prev_results, self.n_buckets)
            else:
                prev_results = [
                    pd.DataFrame(index=range(int(self.sample_number / self.n_buckets))) for _ in range(self.n_buckets)
                ]

            tsv_hash, dependency_hash, attr_order = self._load_tsvs(
                attrs_to_sample, rw_dir, list(prev_results[0]), jsons
            )
            prev_results_list = [df.to_dict(orient='index') for df in prev_results]
            if self.sobol:
                sample_matrices = self._com_execute_sobol_sampling(
                    len(attrs_to_sample), self.sample_number, self.n_buckets
                )
            else:
                sample_matrices = self._com_execute_rand_sampling(
                    len(attrs_to_sample), self.sample_number, self.n_buckets
                )

            if jsons:
                res = Parallel(round(cpu_count()), verbose=5, prefer='threads')(
                    delayed(self._com_execute_json_samples)(
                        tsv_hash, dependency_hash, attr_order, sample_matrices[bucket], prev_results_list[bucket]
                    ) for bucket in range(self.n_buckets))
            else:
                res = Parallel(round(cpu_count()), verbose=5, prefer='threads')(
                    delayed(self._com_execute_samples)(
                        tsv_hash, dependency_hash, attr_order, sample_matrices[bucket], prev_results_list[bucket]
                    ) for bucket in range(self.n_buckets)
                )
            df = pd.concat([pd.DataFrame.from_dict(bucket_res) for bucket_res in res])
            df = df.reset_index(drop=True)
            df.index.name = 'Building'

            # If there was a reduction to zero identify and exit out
            if 'drop_me' in list(df):
                raise RuntimeError('Kindly address the TSV lookup reduction to 0 issues identified above.')

            # Save the intermediate buildstock csvs within the temporary directory and the final at the specified
            # location
            if attrs_to_sample == self.TSV_ARRAYS[-1]:
                df.loc[:, 'baseline_hvac_sizing'] = self.hvac_sizing
                df.to_csv(csv_path, index=True, na_rep='NA')
                shutil.rmtree(self.tmp_dir)
            else:
                df.to_csv(tmp_csv_path, index=True, na_rep='NA')

        return csv_path

    @staticmethod
    def _com_execute_rand_sampling(n_dims, n_samples, n_buckets):
        """Use a pseudorandom algorithm to provide samples for the defined chunked sampling problem

        :param n_dims: number of attributes to be sampled per the ATTR_ORDER sublist
        :type n_dims: int
        :param n_samples: total number of user specified samples (rows in the output buildstock file)
        :type n_samples: int
        :param n_buckets: number of chunks in the sampling process
        :type n_buckets: int
        :return: dictionary of dataframes of pseudorandom numbers by chunk id
        :rtype: dict

        """

        res = {
            i: pd.DataFrame(np.random.random((n_dims, round(n_samples / n_buckets))))
            for i in range(n_buckets)
        }
        return res

    @staticmethod
    def _com_execute_sobol_sampling(n_dims, n_samples, n_buckets):
        """Use a Sobol low-discrepancy sequence to provide samples for the defined chunked sampling problem

        Execute a low discrepancy sampling of the unit hyper-cube defined by the n_dims input using the sobol sequence
        methodology implemented by Corrado Chisari. Please refer to the sobol_lib.py file for license & attribution
        details.

        :param n_dims: number of attributes to be sampled per the ATTR_ORDER sublist
        :type n_dims: int
        :param n_samples: total number of user specified samples (rows in the output buildstock file)
        :type n_samples: int
        :param n_buckets: number of chunks in the sampling process
        :type n_buckets: int
        :return: dictionary of dataframes of pseudorandom numbers by chunk id
        :rtype: dict

        """

        DeprecationWarning('This method is being removed in favor of pseudorandom numbers in the near future.')
        res = dict()
        for i in range(n_buckets):
            sample = i4_sobol_generate(n_dims, round(n_samples / n_buckets), 0)
            projected_sample = np.mod(sample + [random.random() for _ in range(len(sample[0]))], 1)
            projected_shuffled_sample = pd.DataFrame(projected_sample).transpose().sample(frac=1).transpose()
            projected_shuffled_sample.columns = range(int(n_samples / n_buckets))
            res[i] = projected_shuffled_sample
        return res

    @staticmethod
    def _com_order_tsvs(tsv_hash, prev_attrs):
        """Order the list of blah and error if prerequisites are not met or ordering is impossible.

        This method orders the TSV files to ensure that no TSV is sampled before its dependencies are. It also returns
        a hash of dependencies which are used in subsequent code to down-select TSVs based on previous sample results
        and record the resulting values of each iterative sample.

        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :type tsv_hash: dict
        :param prev_attrs: List of previously sampled attributes
        :type prev_attrs: list
        :return: A dictionary defining each TSVs required inputs, and the ordered list of TSV files for sampling
        :rtype: dict, list

        """

        # For each attribute in the tsv_hash create a key of the attribute name where the values are a list of attributes
        # the key attribute is dependent on, should any exist, otherwise an empty list
        dependency_hash = {}
        for attr in tsv_hash.keys():
            dependency_hash[attr] = [
                name.replace('Dependency=', '') for name in list(tsv_hash[attr]) if 'Dependency=' in str(name)
            ]

        # For all previously sampled attributes set their dependence to nothing, since they've already been sampled
        for prev_attr in prev_attrs:
            dependency_hash[prev_attr] = list()
        # Add all attributes that have no dependencies to the attribute order first, as they can be sampled / retrieved
        # from previous samples in any order
        attr_order = []
        for attr in dependency_hash.keys():
            if len(dependency_hash[attr]) == 0:
                attr_order.append(attr)

        # Iteratively (up to five times) step through the dependency hash, identifying previously ordered attributes,
        # and when possible adding attributes whose dependency set is already ordered
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
                raise RuntimeError(
                    'Unable to resolve the dependency tree within the set iteration limit. The following TSV files '\
                    f'were not resolved within 5 iterations: {set(dependency_hash.keys()) - set(attr_order)}'
                )

        # Return the dependency hash and attribute order
        return dependency_hash, attr_order


    @staticmethod
    def _com_execute_samples(tsv_hash, dependency_hash, attr_order, sample_dict, prev_results_dict):
        """Execute the lookup of values based on input TSV files, prior results, and samples for a given chunk.

        This function iteratively evaluates a single sample in the collection of samples provided in the sample matrix
        with the provided TSV files & ordered / aligned previous results. This code is unfortunately optimized for CPU
        and and memory usage, not readability, and for this Ry apologies.

        :param tsv_hash: Dictionary structure containing each TSV file as a Pandas DataFrame
        :type tsv_hash: dict
        :param dependency_hash: Dictionary defining each TSVs required inputs
        :type dependency_hash: dict
        :param attr_order: List defining the order in which to sample TSVs in the tsv_hash
        :type attr_order: list
        :param sample_dict: Integer specifying which sample in the sample_matrix to evaluate
        :type sample_dict: dict
        :param prev_results_dict: Dictionary specifying the previous results for the given datapoint by intra-chunk id
        :type prev_results_dict: dict
        :return: a list of dictionaries where each dictionary specifies the cumulative collection of TSV / JSON
            attributes and their sampled values for a single sample within the calculated chunk
        :rtype: list

        """

        res = list()
        prev_results_key_list = list(prev_results_dict.keys())
        for index in sample_dict.keys():
            results_dict = dict()
            dep_hash = deepcopy(dependency_hash)
            sample_vector = sample_dict[index]
            prev_results = prev_results_dict[prev_results_key_list[index]]
            sample_vector_index = -1
            for attr in attr_order:
                if attr in prev_results.keys():
                    attr_result = prev_results[attr]
                else:
                    sample_vector_index += 1
                    tsv_lkup = tsv_hash[attr].copy(deep=True)
                    tsv_dist_val = sample_vector[sample_vector_index]
                    if tsv_lkup.shape[0] != 1:
                        for dep in dep_hash[attr]:
                            dep_col = 'Dependency=' + dep
                            tsv_lkup = tsv_lkup.loc[
                                tsv_lkup.loc[:, dep_col] == str(dep_hash[dep]),
                                [col for col in list(tsv_lkup) if col != dep_col]
                            ]
                        if tsv_lkup.shape[0] == 0:
                            warn(f'TSV lookup reduced to 0 for {attr}, dep hash {dep_hash}. This will cause an error.')
                            results_dict['drop_me'] = True
                            res.append(results_dict)
                            break
                        if (tsv_lkup.shape[0] != 1) and (len(tsv_lkup.shape) > 1):
                            raise RuntimeError(f'Unable to reduce tsv for {attr} to 1 row, dep_hash {dep_hash}')
                        tsv_lkup = tsv_lkup.transpose()
                    else:
                        tsv_lkup = tsv_lkup.iloc[0, :]
                    tsv_lkup = tsv_lkup.astype(float)
                    attr_result = tsv_lkup[tsv_lkup.values.cumsum() > tsv_dist_val].index[0].replace('Option=', '')
                dep_hash[attr] = attr_result
                results_dict[attr] = attr_result
            res.append(results_dict)
        return res


    @staticmethod
    def _com_execute_json_samples(json_set, dependency_hash, attr_order, sample_dict, prev_results_dict):
        """Execute the lookup of values based on input JSON files, prior results, and samples for a given chunk.

        This function iteratively evaluates a single sample in the collection of samples provided in the sample matrix
        with the provided JSON files & ordered / aligned previous results. This code is unfortunately optimized for CPU
        and and memory usage, not readability, and for this Ry apologies.

        :param json_set: Dictionary structure containing each JSON file
        :type json_set: dict
        :param dependency_hash: Dictionary defining each JSONs required inputs
        :type dependency_hash: dict
        :param attr_order: List defining the order in which to sample TSVs in the tsv_hash
        :type attr_order: list
        :param sample_dict: Dictionary specifying the points in the sample space to sample by intra-chunk id
        :type sample_dict: dict
        :param prev_results_dict: Dictionary specifying the previous results for the given datapoint by intra-chunk id
        :type prev_results_dict: dict
        :return: a list of dictionaries where each dictionary specifies the cumulative collection of TSV / JSON
            attributes and their sampled values for a single sample within the calculated chunk
        :rtype: list

        """

        res = list()
        prev_results_key_list = list(prev_results_dict.keys())
        for index in sample_dict.keys():
            dep_hash = deepcopy(dependency_hash)
            try:
                prev_results = prev_results_dict[prev_results_key_list[index]]
            except:
                breakpoint()
            sample_vector = sample_dict[index]
            results_dict = dict()
            sample_vector_index = -1
            for attr in attr_order:
                try:
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
                except:
                    breakpoint()
            results_dict['state_id'] = results_dict['tract'][:4]
            results_dict['county_id'] = results_dict['tract'][:8]
            res.append(results_dict)
        return res

def parse_arguments():
    """Implement a CLI for executing the ComStock sampling routine.

    :return: Parser arguments to run the file
    :rtype: argparse.Namespace

    """

    parser = argparse.ArgumentParser(description='Run tsv re-sampling file to generate national buildstock.csv')
    parser.add_argument('tsv_version', type=str, help='Version of tsvs to sample (e.g., v16)')
    parser.add_argument('sim_year', type=int, help='Year of simulation (2015 - 2019)')
    parser.add_argument('n_samples', type=int, help='Number of samples (full national run = 350000)')
    parser.add_argument('n_buckets', type=int, help='Number of discrete buckets to sample (full national run = 350000)')
    parser.add_argument(
        'hvac_sizing', type=str, help='Enter "autosize" or "hardsize" to indicate whether the models should have '\
        'their HVAC systems autosized or hardsized'
    )
    parser.add_argument('-v', '--verbose', action='store_true', help='Enables verbose debugging outputs')
    parser.add_argument('-r', '--random', action='store_false', help='Replaces Sobol with Pseudorandom')
    parser.add_argument(
        '-p', '--precomputed', type=str, default=None, help='Path to optional CSV specifying precomputed sample attrs'
    )
    argument = parser.parse_args()
    if argument.verbose:
        logger.setLevel('DEBUG')
    return argument

def main():
    args = parse_arguments()
    for arg in vars(args):
        logger.debug(f'{arg} = {getattr(args, arg)}')

    sampler = ComStockBaseSampler(
        tsv_version=args.tsv_version,
        sim_year=args.sim_year,
        output_dir=os.path.join('output-buildstocks', 'intermediate'),
        hvac_sizing=args.hvac_sizing,
        n_datapoints=args.n_samples,
        n_buckets=args.n_buckets,
        sobol=args.random,
        precomputed_sample=args.precomputed
    )
    sampler.run_sampling()

if __name__ == '__main__':
    main()
