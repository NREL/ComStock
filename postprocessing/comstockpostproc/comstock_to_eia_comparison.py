
import os
import logging

import pandas as pd
from typing import List

from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.units_mixin import UnitsMixin
from comstockpostproc.plotting_mixin import PlottingMixin
from comstockpostproc.eia import EIA
from comstockpostproc.comstock import ComStock

logger = logging.getLogger(__name__)

class ComStockToEIAComparison(NamingMixin, UnitsMixin, PlottingMixin):
    def __init__(self, comstock_list: List[ComStock], eia_list: List[EIA], image_type='jpg', name=None, make_comparison_plots=True):

        # Initialize members
        self.comstock_list = comstock_list
        self.eia_list = eia_list
        self.monthly_data = None
        self.monthly_data_gap = None
        self.color_map = {}
        self.image_type = image_type
        self.name = name

        # Concatenate the datasets and create a color map
        dfs_to_concat = []
        dataset_names = []
        for dataset in (eia_list + comstock_list):
            if dataset.monthly_data is None:
                logger.warning(f'No monthly_data was available for {dataset.dataset_name}, not including in EIA comparison.')
                continue
            if isinstance(dataset, ComStock):
                dfs_to_concat.append(dataset.monthly_data.to_pandas())
            else:
                dfs_to_concat.append(dataset.monthly_data)
            self.color_map[dataset.dataset_name] = dataset.color
            dataset_names.append(dataset.dataset_name)

        # Name the comparison
        if self.name is None:
            self.name = ' vs '.join(dataset_names)

        # Combine into a single dataframe for convenience
        self.monthly_data = pd.concat(dfs_to_concat, join='inner', ignore_index=True)
        current_dir = os.path.dirname(os.path.abspath(__file__))

        # Make directories
        self.output_dir = os.path.join(current_dir, '..', 'output', self.name)
        for p in [self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        # Make ComStock to EIA comparison plots
        if make_comparison_plots:
            self.make_plots(self.monthly_data, self.color_map, self.output_dir)
        else:
            logger.info("make_comparison_plots is set to false, so not plots were created. Set make_comparison_plots to True for plots.")

    def export_to_csv_wide(self):
        # Exports comparison data to CSV in wide format
        file_name = f'ComStock Monthly Long.csv'
        file_path = os.path.join(self.output_dir, file_name)
        self.monthly_data.to_csv(file_path, index=False)

    def make_plots(self, df, color_map, output_dir):
        # Make plots comparing the datasets

        logger.info('Making comparison plots')
        self.plot_annual_energy_consumption_for_eia(df, color_map, output_dir)
        self.plot_monthly_energy_consumption_for_eia(df, color_map, output_dir)
