# This class is a utility class to select the columns need to be plotted in plotting_mixin
# and convert the lazy frame to pandas dataframe to plotting_mixin
import polars as pl
import pandas as pd
from typing import Callable
from comstockpostproc.naming_mixin import NamingMixin
from comstockpostproc.units_mixin import UnitsMixin
import logging
logger = logging.getLogger(__name__)


class LazyFramePlotter(NamingMixin):

    def __init__(self):

        # Every ploting method need these columns
        self.BASE_COLUMNS = ["applicability", self.UPGRADE_NAME, self.BLDG_ID]

        self.WTD_COLUMNS_ANN_ENDUSE = [self.col_name_to_weighted(
            col_name=c, new_units=UnitsMixin.UNIT.ENERGY.TBTU) for c in self.COLS_ENDUSE_ANN_ENGY]

        self.WTD_GHG_COLUMNS = [self.col_name_to_weighted(
            c, UnitsMixin.UNIT.MASS.CO2E_MMT) for c in self.GHG_FUEL_COLS]

        self.UTILITY_COLUMNS = self.COLS_UTIL_BILLS + \
            ['out.utility_bills.electricity_bill_max..usd',
             'out.utility_bills.electricity_bill_min..usd']
        self.WTD_UTILITY_COLUMNS = [self.col_name_to_weighted(
            c, UnitsMixin.UNIT.CURRENCY.BILLION_USD) for c in self.UTILITY_COLUMNS]

        self.WTD_COLUMNS_SUMMARIZE = [self.col_name_to_weighted(col_name=c, new_units=UnitsMixin.UNIT.ENERGY.TBTU) for c in [
            self.ANN_TOT_ENGY_KBTU, self.ANN_TOT_ELEC_KBTU, self.ANN_TOT_GAS_KBTU]]

        self.WTD_COLUMNS_SUMMARIZE += [self.col_name_to_weighted(col_name=self.FLR_AREA),
                                    self.CEN_DIV, self.BLDG_TYPE, self.VINTAGE]

        self.EUI_ANN_TOTL_COLUMNS = list(map(self.col_name_to_eui, [
            self.ANN_TOT_ENGY_KBTU, self.ANN_TOT_ELEC_KBTU, self.ANN_TOT_GAS_KBTU]))
        self.EUI_ANN_TOTL_COLUMNS += [self.col_name_to_weighted(self.FLR_AREA)]

        self.SAVINGS_DISTRI_ENDUSE_COLUMNS = [self.col_name_to_savings(self.col_name_to_eui(
            c)) for c in self.COLS_ENDUSE_ANN_ENGY + self.COLS_TOT_ANN_ENGY]
        self.SAVINGS_DISTRI_ENDUSE_COLUMNS += [self.col_name_to_percent_savings(
            c, UnitsMixin.UNIT.DIMLESS.PERCENT) for c in self.COLS_ENDUSE_ANN_ENGY + self.COLS_TOT_ANN_ENGY]
        
        self.EUI_SAVINGS_COLUMNS = [self.col_name_to_savings(self.col_name_to_area_intensity(c)) for c in [self.UTIL_BILL_TOTAL_MEAN] + self.COLS_UTIL_BILLS]
        self.EUI_SAVINGS_COLUMNS += [self.col_name_to_percent_savings(c, UnitsMixin.UNIT.DIMLESS.PERCENT) for c in [self.UTIL_BILL_TOTAL_MEAN] + self.COLS_UTIL_BILLS]

        self.SAVINGS_DISTRI_BUILDINTYPE = [self.col_name_to_savings(self.col_name_to_eui(self.ANN_TOT_ENGY_KBTU)),
                                           self.col_name_to_percent_savings(self.ANN_TOT_ENGY_KBTU, UnitsMixin.UNIT.DIMLESS.PERCENT)]

        self.QOI_COLUMNS = list(set(self.QOI_MAX_DAILY_TIMING_COLS
                                    + self.QOI_MAX_USE_COLS_NORMALIZED + self.QOI_MIN_USE_COLS_NORMALIZED))

    @staticmethod
    def select_columns(lazy_frame: pl.LazyFrame, columns: list[str]) -> pd.DataFrame:
        missing_columns = [
            col for col in columns if col not in lazy_frame.columns]
        assert len(
            missing_columns) == 0, f"Columns {missing_columns} not in lazy_frame columns"
        return lazy_frame.select(columns).collect().to_pandas()

    @staticmethod
    def plot_with_lazy(plot_method: Callable, lazy_frame: pl.LazyFrame, columns: list[str], *args, **kwargs):
        df: pd.DataFrame = LazyFramePlotter.select_columns(
            lazy_frame, columns)  # convert lazy frame to pandas dataframe
        time_start = pd.Timestamp.now()

        def inner(*args, **kwargs):
            # pass the filtered dataframe to the plotting method
            kwargs['df'] = df
            return plot_method(*args, **kwargs)
        time_end = pd.Timestamp.now()
        logger.info(
            f"{plot_method.__name__} took {time_end - time_start} to plot.")
        return inner
