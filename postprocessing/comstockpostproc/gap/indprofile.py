import os
import logging
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.linear_model import LinearRegression
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import train_test_split
from comstockpostproc.gap.eia861 import EIA861
from comstockpostproc.gap.lrd import LoadResearchData

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# dates of 2018 major holidays
MAJ_HOLIDAYS = [
    '2018-01-01', '2018-05-28', 
    '2018-07-04', '2018-09-03',
    '2018-11-22', '2018-11-23',
    '2018-12-24', '2018-12-25',
]

class IndustrialProfile():
    def __init__(self, truth_data_version='v01', relaod_from_saved=True, save_processed=True, basis_lrd_name='First Energy PA'):
        """
        A class to produce estimated industrial electrical load profiles by Balancing Authority
            Parameters:
                project_filename (String): filename to save or load profiles from
                lrd_name (String): name of LRD source to generate Industrial Profiles from 
        """

        self.truth_data_version = truth_data_version
        self.basis_lrd_name = basis_lrd_name
        self.reload_from_saved = relaod_from_saved
        self.save_processed = save_processed
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..','..','truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.processed_filename = 'ba_ind_profiles.csv'
        self.processed_path = os.path.join(self.processed_dir, self.processed_filename)

        if self.reload_from_saved:
            if os.path.exists(self.processed_path):
                logger.info('Reloading BA Industrial Profiles from CSV')
                self.data = pd.read_csv(self.processed_path, index_col=0, parse_dates=True)
            else:
                logger.warning(f'No processed data found for {self.processed_filename}. Generating profiles.')
                self.data = self.ba_ind_profiles()
        else:
            self.data = self.ba_ind_profiles()
        
    def add_model_parameters(self, df):
        """
        Adds regression parameters to dataframe..
            Parameters:
                df (DataFrame): Timeseries LRD data with DateTime index
            
            Returns:
                df (DataFrame) Dataframe with 'hour', 'cos_hour' and 'wknd_or_maj_hol' columns added.
        """
        # hour of day
        df['hour'] = df.index.hour

        # day of week
        df['dow'] = df.index.weekday

        # cos of hour
        df['cos_hour'] = np.cos(2 * np.pi * df['hour'] / 24)

        # weekend or major holiday
        wknd = df.index.weekday.isin([5,6]).astype(int)
        hol = df.index.to_series().apply(lambda x: 1 if x.strftime('%Y-%m-%d') in MAJ_HOLIDAYS else 0).to_numpy()
        df['wknd_or_maj_hol'] = wknd | hol

        self.model_parameters = ['hour', 'dow', 'wknd_or_maj_hol', 'cos_hour']

        return df
    
    def create_linear_model(self, df):
        """
        Creates linear regression model from timeseries data
            Parameters:
                df (DataFrame): Timeseries data with 'hour', 'cos_hour', 'wknd_or_maj_hol', 'target' columns
                
            Returns:
                model (LinearRegression): Regression model
        """
        # train model on whole year of data
        x_train = df[self.model_parameters]
        y_train = df['target']

        model = LinearRegression()
        model.fit(x_train, y_train)

        return model
    
    def create_hgbr_model(self, df):
        """
        Creates a Histogram Gradiant-boosting Regressor model from timeseries data
        https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.HistGradientBoostingRegressor.html
            Parameters:
                df (DataFrame): Timeseries data with 'hour', 'dow', 'wknd_or_maj_hol', 'cos_hour', 'target' columns

            Returns:
                model (HIstGradiantBoostingRegressor): Regression model
        """

        X = df[self.model_parameters]
        Y = df['target']

        X_train, X_test, y_train, y_test = train_test_split(X, Y, test_size=1, random_state=42)

        model = HistGradientBoostingRegressor(max_iter=500)
        model.fit(X_train, y_train)

        return model
    
    def apply_regression(self, df, model):
        """
        Applies regression model to predict unitized load from hour of day and day of year
        Parameters:
            df (DataFrame): Timeseries dataframe with DateTime index
            model (LinearRegression) regression model
            
        Returns:
            df (DataFrame): dataframe with 'predicted' column
        """
        df = self.add_model_parameters(df)
        df['predicted'] = model.predict(df[
            [
                'hour',
                'dow',
                'wknd_or_maj_hol',
                'cos_hour'
            ]
        ])

        self.mae = mean_absolute_error(df['target'], df['predicted'])
        self.mse = mean_squared_error(df['target'], df['predicted'])
        self.r_sq = r2_score(df['target'], df['predicted'])

        return df
    
    def ba_ind_profiles(self):
        """
        Generates estimated load profiles for industrial sector by Balancing Authority
        """

        # load LRD
        lrd_data = LoadResearchData(utility_name=self.basis_lrd_name).data
        
        # select industrial profiles
        ind_lrd = lrd_data.filter(like='Industrial_Total_kWh')

        # unitize profiles and take mean
        ind_lrd_unit = ind_lrd.div(ind_lrd.sum(axis=0), axis=1)
        ind_lrd_unit['target'] = ind_lrd_unit.mean(axis=1)

        # generate regression model from selected lrd
        ind_lrd_unit = self.add_model_parameters(ind_lrd_unit)
        model = self.create_hgbr_model(ind_lrd_unit)

        # test model
        ind_lrd_unit_out = self.apply_regression(ind_lrd_unit, model)
        
        # TODO: run regression and plot days
        # TODO: compare to other LRD - AES Ohio, PG&E

        # load total industrial sales by BA from EIA 861
        ind_sales = EIA861(segment='Industrial', measure='Sales').data
        ind_ba_sales = ind_sales.groupby('BA Code')['INDUSTRIAL_Sales_MWh'].sum()

        # create dataframe of BA profiles
        dt_index = pd.date_range(start='2018-01-01 01:00:00', end='2019-01-01 00:00:00', freq='h')
        ba_ind_profiles = pd.DataFrame(index=dt_index)
        ba_ind_profiles = self.add_model_parameters(ba_ind_profiles)
        ba_ind_profiles['unitized_load'] = model.predict(ba_ind_profiles[self.model_parameters])

        # apply unitized profile to total BA Sales
        for idx, val in ind_ba_sales.items():
            ba_ind_profiles[idx] = ba_ind_profiles['unitized_load'] * val
        
        ba_ind_profiles.drop(self.model_parameters + ['unitized_load'], axis=1, inplace=True)

        if self.save_processed:
            ba_ind_profiles.to_csv(self.processed_path)
        
        return ba_ind_profiles




