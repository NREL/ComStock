# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import os

import logging
import numpy as np
import pandas as pd
import polars as pl
from typing import List

from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.units_mixin import UnitsMixin
from comstockpostproc.plotting_mixin import PlottingMixin
from comstockpostproc.cbecs import CBECS
from comstockpostproc.comstock import ComStock

from comstockpostproc.lazyframeplotter import LazyFramePlotter

logger = logging.getLogger(__name__)

class ComStockToCBECSComparison(NamingMixin, UnitsMixin, PlottingMixin):
    def __init__(self, comstock_list: List[ComStock], cbecs_list: List[CBECS], upgrade_id=0, image_type='jpg', name=None, make_comparison_plots=True, make_hvac_plots = False):
        """
        Creates the ComStock to CBECS comaprison plots.

        Args:
            comstock_list (List[ComStock]): List of ComStock dataset objects.
            cbecs_list (List[CBECS]): List of CBECS dataset objects.
            upgrade_id (Union(str, int), optional): The upgrade ID to include in the plots, or 'All' to include all upgrades for the ComStock run(s).
            image_type (str, optional): Image file type to use. Defaults to 'jpg'.
            name (str, optional): Name of output directory. If None, a name will be generated. Defaults to None.
            make_comparison_plots (bool, optional): Flag to create compairison plots. Defaults to True.
        """
        # Initialize members
        self.comstock_list = comstock_list
        self.cbecs_list = cbecs_list
        self.data = None
        self.color_map = {}
        self.image_type = image_type
        self.name = name
        self.column_for_grouping = self.DATASET

        self.lazyframe_plotter: LazyFramePlotter = LazyFramePlotter()

        # Concatenate the datasets and create a color map
        dfs_to_concat = []
        comstock_dfs_to_concat = []
        dataset_names = []
        comstock_color_map = {}
        for dataset in (cbecs_list + comstock_list):
            # remove measure data from ComStock
            if isinstance(dataset, ComStock): #dataset is ComStock
                assert isinstance(dataset.data, pl.LazyFrame)
                # Instantiate the plotting data lazyframe if it doesn't yet exist:
                if not isinstance(dataset.plotting_data, pl.LazyFrame):
                    logger.info(f'Instantiating plotting lazyframe for comstock dataset {dataset.dataset_name}.')
                    dataset.create_plotting_lazyframe()
                assert isinstance(dataset.plotting_data, pl.LazyFrame)

                up_id_name: list = dataset.plotting_data.select(dataset.UPGRADE_ID, dataset.UPGRADE_NAME).collect().unique().to_numpy().tolist()
                up_name_map = {k: v for k, v in up_id_name}
                valid_upgrade_id = [x for x in up_name_map.keys()]
                valid_upgrade_name = [up_name_map[x] for x in valid_upgrade_id]

                logger.info(f"Valid upgrades for {dataset.dataset_name}: {valid_upgrade_id} with names {up_name_map}")
                if upgrade_id == 'All':
                    # df_data: pl.LazyFrame = dataset.data
                    # df_data[dataset.DATASET] = df_data[dataset.DATASET] + ' - ' + df_data['upgrade_name']
                    comstock_dfs_to_concat.append(dataset.plotting_data)
                    # df_data[dataset.DATASET] = df_data[dataset.DATASET].astype(str) + ' - ' + df_data[dataset.UPGRADE_NAME].astype(str)
                    dataset.plotting_data = dataset.plotting_data.with_columns((
                        pl.col(dataset.DATASET).cast(pl.Utf8) + ' - ' + pl.col(dataset.UPGRADE_NAME).cast(pl.Utf8)
                    ).alias(dataset.DATASET))
                    dfs_to_concat.append(dataset.plotting_data)
                    # up_name_map = dict(zip(df_data[dataset.UPGRADE_ID].unique(), df_data[dataset.UPGRADE_NAME].unique()))
                    # upgrade_list = list(df_data[dataset.UPGRADE_ID].unique())
                    color_dict = self.linear_gradient(dataset.COLOR_COMSTOCK_BEFORE, dataset.COLOR_COMSTOCK_AFTER, len(valid_upgrade_id))
                    for idx, upgrade_id in enumerate(valid_upgrade_id):
                        dataset_name = dataset.dataset_name + ' - ' + up_name_map[upgrade_id]
                        dataset_names.append(dataset_name)
                        comstock_color_map[dataset_name] = color_dict['hex'][idx]
                        self.color_map[dataset_name] = color_dict['hex'][idx]

                elif upgrade_id not in valid_upgrade_id:
                    logger.error(f"Upgrade {upgrade_id} not found in {dataset.dataset_name}. Enter a valid upgrade ID in the ComStockToCBECSComparison constructor or \"All\" to include all upgrades.")
                else:
                    df_data = dataset.plotting_data.filter(pl.col(dataset.UPGRADE_ID) == upgrade_id)
                    df_data = df_data.with_columns((pl.col(dataset.DATASET).cast(pl.Utf8) + ' - ' + pl.col(dataset.UPGRADE_NAME).cast(pl.Utf8)).alias(dataset.DATASET))
                    dataset_name = dataset.dataset_name + " - " + up_name_map[upgrade_id]
                    comstock_dfs_to_concat.append(df_data)
                    dfs_to_concat.append(df_data)
                    comstock_color_map[dataset_name] = dataset.color
                    self.color_map[dataset_name] = dataset.color
                    dataset_names.append(dataset_name)
            else: #dataset is CBECS
                assert isinstance(dataset.data, pl.LazyFrame)
                df_data = dataset.data
                dfs_to_concat.append(df_data)
                self.color_map[dataset.dataset_name] = dataset.color
                dataset_names.append(dataset.dataset_name)

        # Name the comparison
        if self.name is None:
            if len(dataset_names) > 2:
                self.name = ' vs '.join(sorted(dataset_names, key=len)[:2]) + ' and Upgrades'
            else:
                self.name = ' vs '.join(sorted(dataset_names))

        # Combine into a single dataframe for convenience
        # self.data = pd.concat(dfs_to_concat, join='inner', ignore_index=True)

        #There is no such a join='inner' in polars.concat, implement it mannualy
        common_columns = set(dfs_to_concat[0].columns)
        for df in dfs_to_concat:
            common_columns = common_columns.intersection(set(df.columns))
        dfs_to_concat = [df.select(common_columns) for df in dfs_to_concat]
        self.data: pl.LazyFrame = pl.concat(dfs_to_concat, how="vertical_relaxed")
        current_dir = os.path.dirname(os.path.abspath(__file__))

        # Combine just comstock runs into single dataframe for QOI plots
        common_columns = set(comstock_dfs_to_concat[0].columns)
        all_columns = common_columns
        for df in comstock_dfs_to_concat:
            common_columns = common_columns & set(df.columns)
        logger.info(f"Not including columns {all_columns - common_columns} in comstock only plots")
        comstock_dfs_to_concat = [df.select(common_columns) for df in comstock_dfs_to_concat]
        comstock_df = pl.concat(comstock_dfs_to_concat, how="vertical_relaxed")
        # comstock_df = comstock_df[[self.DATASET] + self.QOI_MAX_DAILY_TIMING_COLS + self.QOI_MAX_USE_COLS + self.QOI_MIN_USE_COLS + self.QOI_MAX_USE_COLS_NORMALIZED + self.QOI_MIN_USE_COLS_NORMALIZED]
        comstock_qoi_columns = [self.DATASET] + self.QOI_MAX_DAILY_TIMING_COLS + self.QOI_MAX_USE_COLS + self.QOI_MIN_USE_COLS + self.QOI_MAX_USE_COLS_NORMALIZED + self.QOI_MIN_USE_COLS_NORMALIZED
        comstock_df: pl.LazyFrame = comstock_df.select(comstock_qoi_columns)

        # Make directories
        self.output_dir = os.path.join(current_dir, '..', 'output', self.name)
        for p in [self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)

        logger.info(f"type of self.data columns: {self.data.columns, self.data.dtypes, len(self.data.columns), len(self.data.dtypes)}")
        logger.info(f"type of comstock_df columns: {comstock_df.columns, comstock_df.dtypes}")

        assert isinstance(self.data, pl.LazyFrame)
        assert isinstance(comstock_df, pl.LazyFrame)
        # self.data: pd.DataFrame = self.data.collect().to_pandas()
        # comstock_df: pd.DataFrame = comstock_df.collect().to_pandas()
        # assert isinstance(self.data, pd.DataFrame)
        # assert isinstance(comstock_df, pd.DataFrame)

        # Make ComStock to CBECS comparison plots
        if make_comparison_plots:
            self.make_plots(self.data, self.column_for_grouping, self.color_map, self.output_dir, make_hvac_plots)
            # QOI plots can only be made with comstock data because CBECS data do not have QOI columns
            self.make_qoi_plots(comstock_df, self.column_for_grouping, comstock_color_map, self.output_dir)

        else:
            logger.info("make_comparison_plots is set to false, so not plots were created. Set make_comparison_plots to True for plots.")

    def make_plots(self, lazy_frame: pl.LazyFrame, column_for_grouping, color_map: dict, output_dir, make_hvac_plots):
        # Make plots comparing the datasets

        BASIC_PARAMS = {
            'column_for_grouping': column_for_grouping,
            'color_map': color_map,
            'output_dir': output_dir
        }
        logger.info('Making comparison plots')

        logger.info('Making Floor Area and Energy Totals plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=self.plot_floor_area_and_energy_totals,
            lazy_frame=lazy_frame.clone(),
            columns=(self.lazyframe_plotter.WTD_COLUMNS_SUMMARIZE +  [column_for_grouping]))(**BASIC_PARAMS)

        logger.info('Making EUI plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=lambda df, **kwargs: self.plot_eui_boxplots(df, **kwargs, make_hvac_plots=make_hvac_plots),
            lazy_frame=lazy_frame.clone(),
            columns=( [column_for_grouping] + self.lazyframe_plotter.EUI_ANN_TOTL_COLUMNS + [self.BLDG_TYPE, self.HVAC_SYS]))(**BASIC_PARAMS)

        logger.info('Making floor area and energy total by building type plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=self.plot_floor_area_and_energy_totals_by_building_type,
            lazy_frame=lazy_frame.clone(),
            columns=( [column_for_grouping] + self.lazyframe_plotter.WTD_COLUMNS_SUMMARIZE))(**BASIC_PARAMS)

        logger.info('Making end use totals by building type plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=self.plot_end_use_totals_by_building_type,
            lazy_frame=lazy_frame.clone(),
            columns=( [column_for_grouping] + self.lazyframe_plotter.WTD_COLUMNS_ANN_ENDUSE + [self.BLDG_TYPE, self.CEN_DIV]))(**BASIC_PARAMS)

        logger.info('Making EUI historgram by building type plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=self.plot_eui_histograms_by_building_type,
            lazy_frame=lazy_frame.clone(),
            columns=( [column_for_grouping] + self.lazyframe_plotter.EUI_ANN_TOTL_COLUMNS + [self.BLDG_TYPE]))(**BASIC_PARAMS)

        logger.info('Making EUI boxplots by building type plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=self.plot_eui_boxplots_by_building_type,
            lazy_frame=lazy_frame.clone(),
            columns=( [column_for_grouping] + self.lazyframe_plotter.EUI_ANN_TOTL_COLUMNS + [self.CEN_DIV, self.BLDG_TYPE]))(**BASIC_PARAMS)

        logger.info('Making Energy Rate plots')
        LazyFramePlotter.plot_with_lazy(
            plot_method=self.plot_energy_rate_boxplots,
            lazy_frame=lazy_frame.clone(),
            columns=(self.lazyframe_plotter.BASE_COLUMNS + self.lazyframe_plotter.SUMMARIZE_COLUMNS + self.lazyframe_plotter.WTD_UTILITY_COLUMNS + [column_for_grouping, self.CEN_DIV, self.BLDG_TYPE]))(**BASIC_PARAMS)

        if make_hvac_plots:
            logger.info('Making HVAC plots')
            logger.info('Making floor area and energy totals by HVAC type plots')
            LazyFramePlotter.plot_with_lazy(
                plot_method=self.plot_floor_area_and_energy_totals_by_hvac_type,
                lazy_frame=lazy_frame.clone(),
                columns=( [column_for_grouping] + self.lazyframe_plotter.WTD_COLUMNS_SUMMARIZE + [self.HVAC_SYS, self.BLDG_TYPE]))(**BASIC_PARAMS)
            logger.info('Making Floor Area and energy totals grouped by HVAC plots')
            LazyFramePlotter.plot_with_lazy(
                plot_method=self.plot_floor_area_and_energy_totals_grouped_hvac,
                lazy_frame=lazy_frame.clone(),
                columns=( [column_for_grouping] + self.lazyframe_plotter.WTD_COLUMNS_SUMMARIZE + [self.HVAC_SYS, self.BLDG_TYPE]))(**BASIC_PARAMS)

            logger.info('Making EUI by HVAC type plots')
            LazyFramePlotter.plot_with_lazy(
                plot_method=self.plot_eui_boxplots_by_hvac_type,
                lazy_frame=lazy_frame.clone(),
                columns=( [column_for_grouping] + self.lazyframe_plotter.EUI_ANN_TOTL_COLUMNS + [self.HVAC_SYS, self.CEN_DIV, self.BLDG_TYPE]))(**BASIC_PARAMS)




    def make_qoi_plots(self, lazy_frame, column_for_grouping, color_map, output_dir):
        BASIC_PARAMS = {
            'column_for_grouping': column_for_grouping,
            'color_map': color_map,
            'output_dir': output_dir
        }
        LazyFramePlotter.plot_with_lazy(plot_method=self.plot_qoi_timing, lazy_frame=lazy_frame.clone(),
                                        columns=(self.lazyframe_plotter.QOI_COLUMNS + [column_for_grouping]))(**BASIC_PARAMS)
        # self.plot_qoi_timing(df, column_for_grouping, color_map, output_dir)
        LazyFramePlotter.plot_with_lazy(plot_method=self.plot_qoi_max_use, lazy_frame=lazy_frame.clone(),
                                        columns=(self.lazyframe_plotter.QOI_COLUMNS + [column_for_grouping]))(**BASIC_PARAMS)
        # self.plot_qoi_max_use(df, column_for_grouping, color_map, output_dir)
        LazyFramePlotter.plot_with_lazy(plot_method=self.plot_qoi_min_use, lazy_frame=lazy_frame.clone(),
                                        columns=(self.lazyframe_plotter.QOI_COLUMNS + [column_for_grouping]))(**BASIC_PARAMS)
        # self.plot_qoi_min_use(df, column_for_grouping, color_map, output_dir)

    def export_to_csv_wide(self):
        file_name = 'ComStock wide.csv'
        file_path = os.path.join(self.output_dir, file_name)

        try:
            self.data.collect().write_csv(file_path)
            logger.info(f'Exported comparison data to {file_path}')
        except Exception as e:
            logger.error(f"CSV export failed: {e}")
