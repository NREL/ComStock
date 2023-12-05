# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

import os
import logging

import pandas as pd
from typing import List

from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.units_mixin import UnitsMixin
from comstockpostproc.plotting_mixin import PlottingMixin
from comstockpostproc.ami import AMI
from comstockpostproc.comstock import ComStock

logger = logging.getLogger(__name__)

class ComStockToAMIComparison(NamingMixin, UnitsMixin, PlottingMixin):
    def __init__(self, comstock_object:ComStock, ami_object:AMI, image_type='jpg', name=None, make_comparison_plots=True):

        # Initialize members
        self.comstock_object = comstock_object
        self.ami_object = ami_object
        self.ami_timeseries_data = None
        self.color_map = {}
        self.image_type = image_type
        self.name = name

        # Concatenate the datasets and create a color map
        dfs_to_concat = []
        dataset_names = []
        for dataset in [ami_object, comstock_object]:
            if dataset.ami_timeseries_data is None:
                logger.warning(f'No monthly_data was available for {dataset.dataset_name}, not including in EIA comparison.')
                continue
            if isinstance(dataset, ComStock):
                df = dataset.ami_timeseries_data
                df['run'] = self.comstock_object.comstock_run_version
                df['year'] = self.comstock_object.year
                dfs_to_concat.append(df)
                df.iloc[0:0]
            elif isinstance(dataset, AMI):
                df = dataset.ami_timeseries_data
                df['run'] = self.ami_object.dataset_name + ' ' + self.ami_object.truth_data_version
                df['enduse'] = 'total'
                dfs_to_concat.append(df)
                df.iloc[0:0]
            self.color_map[dataset.dataset_name] = dataset.color
            dataset_names.append(dataset.dataset_name)

        # Name the comparison
        if self.name is None:
            self.name = ' vs '.join(dataset_names)

        # Combine into a single dataframe for convenience
        self.ami_timeseries_data = pd.concat(dfs_to_concat, join='outer', ignore_index=True)

        # Make directories
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.output_dir = os.path.join(current_dir, '..', 'output', self.name)
        for p in [self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        # Make ComStock to AMI comparison plots
        if make_comparison_plots:
            self.make_plots(self.ami_timeseries_data, self.color_map, self.output_dir)
        else:
            logger.info("make_comparison_plots is set to false, so not plots were created. Set make_comparison_plots to True for plots.")

    def export_to_csv_wide(self):
        # Exports comparison data to CSV in wide format
        file_name = f'ComStock AMI Comparison Timeseries Long.csv'
        file_path = os.path.join(self.output_dir, file_name)
        self.ami_timeseries_data.to_csv(file_path, index=False)

    def make_plots(self, df, color_map, output_dir):
        # Make plots comparing the datasets

        logger.info('Making comparison plots')