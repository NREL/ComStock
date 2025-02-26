import os
import logging
import numpy as np
import geopandas as gpd
import plotly.express as px
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class GapPlottingMixin():

    # function to plot profiles in simple line chart
    def plot_profiles(self, df, cols, name, output_dir):
        fig = px.line(df, x=df.index, y=cols)
        fig.update_xaxes(
            rangeslider_visible=True,
            rangeselector=dict(
                buttons=list([
                    dict(count=1, label="1m", step="month", stepmode="backward"),
                ])
            )
        )
        fig.show()
        fig_name_html = f'{name}.html'
        fig_sub_dir = os.path.abspath(os.path.join(output_dir))
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path_html = os.path.abspath(os.path.join(fig_sub_dir, fig_name_html))
        fig.write_html(fig_path_html)

    def plot_side_by_side_bar_charts(self, df1, df2, label1, label2, name, output_dir):
        # check that dataframes have the same columns and number of rows
        assert(df1.shape == df2.shape, "DataFrames must have the same shape")
        assert((df1.columns == df2.columns).all(), "DataFrames must have the same columns")

        num_columns = df1.shape[1]
        index = np.arange(len(df1))

        # set figure size from number of columns
        fig, axes = plt.subplots(nrows=num_columns, ncols=1, figsize=(10, num_columns * 4))
        fig.tight_layout(pad=5)

        for i, col in enumerate(df1.columns):
            ax = axes[1] if num_columns > 1 else axes

            # plot bars for each dataframe's column on the same axis
            width = 0.35
            ax.bar(index - width / 2, df1[col], width, label=f'{label1}', color='blue')
            ax.bar(index + width / 2, df2[col], width, label=f'{label2}', color='orange')
            
            # set labels and title for each subplot
            ax.set_xlabel('Month')
            ax.set_xticks(index)
            ax.set_xticklabels(df1.index)
            ax.set_ylabel(col)
            ax.set_title(f"Comparison of {col} Monthly Net Electricity")
            ax.legend()
        
        plt.show()

        fig_name = f'{name}.jpg'
        fig_sub_dir = os.path.abspath(os.path.join(output_dir))
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path = os.path.join(fig_sub_dir, fig_name)
        plt.savefig(fig_path, dpi=600, bbox_inches = 'tight')

    def plot_regression_model_against_data_for_representative_weeks(self, df, model, model_params, dates_dict, name, output_dir):
        """
        Creates 2x2 line charts of a regression model overlayed over data for a set of four representative weeks of the year
        Params:
            df (DataFrame): dataframe of timeseries data to plot, with cols: 'target' containing actual data, plus the cols specified in model_params argument
            model (RegressionModel): regression model (e.g., LinearRegression, HistGradientBoostingRegressor)
            model_params (List): list of model parameter column names that exist in input df
            dates_dict (Dict(List)): Dict with keys season (i.e. 'Winter','Summer','Spring','Fall'), and value of Lists of start/end dates
        """

        fig, axes = plt.subplots(2, 2, figsize=(14,10))
        axes = axes.flatten()

        for i, (season, date_range) in enumerate(dates_dict.items()):
            # select data for chosen range
            data = df.loc[date_range[0]: date_range[1]]

            # prepare features
            x_range = data[model_params]
            y_pred = model.predict(x_range)

            # plot actual vs predicted values
            axes[i].plot(data.index, data['target'], label='Actual', color='blue')
            axes[i].plot(data.index, y_pred, label='Predicted', color='orange', linestyel='--')
            axes[i].set_title(f'{season}: {date_range[0]} - {date_range[1]}')
            axes[i].xaxes.set_major_formatter(mdates.DateFormatter('%b-%d'))
            axes[i].setlabel('Annual Unitized Load')
            axes[i].legend()

        plt.tight_layout()
        plt.show()

        fig_name = f'{name}.png'
        fig_sub_dir = os.path.abspath(os.path.join(output_dir))
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path = os.path.join(fig_sub_dir, fig_name)
        plt.savefig(fig_path, dpi=600, bbox_inches='tight')
