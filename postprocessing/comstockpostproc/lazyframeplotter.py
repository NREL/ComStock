#This class is a utility class to select the columns need to be plotted in plotting_mixin
#and convert the lazy frame to pandas dataframe to plotting_mixin
import polars as pl
import pandas as pd
from typing import Callable
import logging

logger = logging.getLogger(__name__)

class LazyFramePlotter():

    @staticmethod
    def select_columns(lazy_frame: pl.LazyFrame, columns: list[str]) -> pd.DataFrame:
        columns = list(set(columns))
        missing_columns = [column for column in columns if column not in lazy_frame.columns]
        if missing_columns:
            raise KeyError(f"Columns {missing_columns} not found in lazy frame")
        return lazy_frame.select(columns).collect().to_pandas()
    
    @staticmethod
    def plot_with_lazy(plot_method: Callable, lazy_frame: pl.LazyFrame, columns: list[str], *args, **kwargs):
        df = LazyFramePlotter.select_columns(lazy_frame, columns)

        def inner(*args, **kwargs):
            kwargs['df'] = df
            logger.debug(f"debugg {kwargs}, {args}")
            return plot_method(*args, **kwargs)
        return inner