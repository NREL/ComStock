# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import os

import logging
import numpy as np
import pandas as pd
import matplotlib
import matplotlib.pyplot as plt
import plotly.express as px
import seaborn as sns
import plotly.graph_objects as go

matplotlib.use('Agg')
logger = logging.getLogger(__name__)

# color setting for savings distributions
color_violin = "#EFF2F1"
color_interquartile = "#6A9AC3"

class PlottingMixin():

    # plot energy consumption by fuel type and enduse
    def plot_energy_by_enduse_and_fuel_type(self, df, column_for_grouping, color_map, output_dir):

        # ghg columns; uses Cambium low renewable energy cost 15-year for electricity
        cols_enduse_ann_en = self.COLS_ENDUSE_ANN_ENGY
        wtd_cols_enduse_ann_en = [self.col_name_to_weighted(c, 'tbtu') for c in cols_enduse_ann_en]


        # plots for both applicable and total stock
        for applicable_scenario in ['stock', 'applicable_only']:

            df_scen = df.copy()
            

            if applicable_scenario == 'applicable_only':
                applic_bldgs = df_scen.loc[(df_scen[self.UPGRADE_NAME]!='Baseline') & (df_scen['applicability']==True), self.BLDG_ID]
                df_scen = df_scen.loc[df_scen[self.BLDG_ID].isin(applic_bldgs), :]

            # groupby and long format for plotting
            df_emi_gb = (df_scen.groupby(column_for_grouping, observed=True)[wtd_cols_enduse_ann_en].sum()).reset_index()
            df_emi_gb = df_emi_gb.loc[:, (df_emi_gb !=0).any(axis=0)]
            df_emi_gb_long = df_emi_gb.melt(id_vars=[column_for_grouping], value_name='Annual Energy Consumption (TBtu)').sort_values(by='Annual Energy Consumption (TBtu)', ascending=False)

            # naming for plotting
            df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('calc.weighted.', '', regex=True)
            df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('.energy_consumption..tbtu', '', regex=True)
            # split end use and fuel names for coordianted color and texture assignments
            df_emi_gb_long[['Fuel Type', 'End Use']] = df_emi_gb_long['variable'].str.split('.', expand=True)
            df_emi_gb_long['Fuel Type'] = df_emi_gb_long['Fuel Type'].str.replace('_', ' ', regex=True)
            df_emi_gb_long['Fuel Type'] = df_emi_gb_long['Fuel Type'].str.title()
            df_emi_gb_long['End Use'] = df_emi_gb_long['End Use'].str.replace('_', ' ', regex=True)
            df_emi_gb_long['End Use'] = df_emi_gb_long['End Use'].str.title()

            # add OS color map
            color_dict = {'Heating':'#EF1C21',
            'Cooling':'#0071BD',
            'Interior Lighting':'#F7DF10',
            'Exterior Lighting':'#DEC310',
            'Interior Equipment':'#4A4D4A',
            'Exterior Equipment':'#B5B2B5',
            'Fans':'#FF79AD',
            'Pumps':'#632C94',
            'Heat Rejection':'#F75921',
            'Humidification':'#293094',
            'Heat Recovery': '#CE5921',
            'Water Systems': '#FFB239',
            'Refrigeration': '#29AAE7',
            'Generators': '#8CC739'}

            # set patterns by fuel type
            pattern_dict = {
                'Electricity': "",
                'Natural Gas':"/",
                'District Cooling':"x",
                'District Heating':".",
                'Other Fuel':'+'
            }

            # set category orders by end use
            cat_order = {
               'End Use': [ 'Interior Equipment',
                            'Fans',
                            'Cooling',
                            'Interior Lighting',
                            'Heating',
                            'Water Systems',
                            'Exterior Lighting',
                            'Refrigeration',
                            'Pumps',
                            'Heat Recovery',
                            'Heat Rejection'],
                'Fuel Type': [
                            'Electricity',
                            'Natural Gas',
                            'District Cooling',
                            'District Heating',
                            'Other Fuel',
                ]
            }

            # plot
            order_map = dict(zip(color_map.keys(), [2,1])) # this will set baseline first in plots
            fig = px.bar(df_emi_gb_long, x=column_for_grouping, y='Annual Energy Consumption (TBtu)', color='End Use', pattern_shape='Fuel Type',
                    barmode='stack', text_auto='.1f', template='simple_white', width=700, category_orders=cat_order, color_discrete_map=color_dict,
                    pattern_shape_map=pattern_dict)

            # formatting and saving image
            title = 'ann_energy_by_enduse_and_fuel'
            # format title and axis
            fig.update_traces(textposition='inside', width=0.5)
            fig.update_xaxes(type='category', mirror=True, showgrid=False, showline=True, title=None, ticks='outside', linewidth=1, linecolor='black',
                            categoryorder='array', categoryarray=np.array(list(color_map.keys())))
            fig.update_yaxes(mirror=True, showgrid=False, showline=True, ticks='outside', linewidth=1, linecolor='black', rangemode="tozero")
            fig.update_layout(title=None,  margin=dict(l=20, r=20, t=27, b=20), width=550, legend_title=None, legend_traceorder="reversed",
                            uniformtext_minsize=8, uniformtext_mode='hide', bargap=0.05)
            fig.update_layout(
                font=dict(
                    size=12)
                )

            # add summed values at top of bar charts
            df_emi_plot = df_emi_gb_long.groupby(column_for_grouping, observed=True)['Annual Energy Consumption (TBtu)'].sum()
            fig.add_trace(go.Scatter(
            x=df_emi_plot.index,
            y=df_emi_plot,
            text=round(df_emi_plot, 0),
            mode='text',
            textposition='top center',
            textfont=dict(
                size=12,
            ),
            showlegend=False
            ))

            # figure name and save
            fig_name = f'{title.replace(" ", "_").lower()}_{applicable_scenario}.{self.image_type}'
            fig_name_html = f'{title.replace(" ", "_").lower()}_{applicable_scenario}.html'
            fig_sub_dir = os.path.join(output_dir)
            if not os.path.exists(fig_sub_dir):
                os.makedirs(fig_sub_dir)
            fig_path = os.path.join(fig_sub_dir, fig_name)
            fig_path_html = os.path.join(fig_sub_dir, fig_name_html)
            fig.write_image(fig_path, scale=10)
            fig.write_html(fig_path_html)

    # plot for GHG emissions by fuel type for baseline and upgrade
    def plot_emissions_by_fuel_type(self, df, column_for_grouping, color_map, output_dir):

        # ghg columns; uses Cambium low renewable energy cost 15-year for electricity
        ghg_cols = self.GHG_FUEL_COLS
        wtd_ghg_cols = [self.col_name_to_weighted(c, 'co2e_mmt') for c in ghg_cols]

        # groupby and long format for plotting
        df_emi_gb = (df.groupby(column_for_grouping, observed=True)[wtd_ghg_cols].sum()).reset_index()
        df_emi_gb_long = df_emi_gb.melt(id_vars=[column_for_grouping], value_name='Annual GHG Emissions (MMT CO2e)').sort_values(by='Annual GHG Emissions (MMT CO2e)', ascending=False)
        df_emi_gb_long.loc[:, 'in.upgrade_name'] = df_emi_gb_long['in.upgrade_name'].astype(str)

        # naming for plotting
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('ghg.weighted.', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('_emissions..co2e_mmt', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('..co2e_mmt', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('_emissions_', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('electricity', 'electricity:_', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('_', ' ', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.title()
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('Lrmer', 'LRMER', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('Egrid', 'eGRID', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('Re', 'RE', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('Calc.Weighted.Emissions.', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('calc.weighted.emissions.', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('.', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace('Subregion', '', regex=True)
        df_emi_gb_long['variable'] = df_emi_gb_long['variable'].str.replace(' 2023 Start', '', regex=True)

        # plot
        order_map = list(color_map.keys()) # this will set baseline first in plots
        dict_order_map = {column_for_grouping: order_map}
        fig = px.bar(df_emi_gb_long, x='variable', y='Annual GHG Emissions (MMT CO2e)', color=column_for_grouping,
                   barmode='group', text_auto='.1f', template='simple_white', color_discrete_map=color_map, category_orders=dict_order_map,
                    width=700)

        # formatting and saving image
        title = 'ghg_emissions_by_fuel'
        # format title and axis
        fig.update_xaxes(mirror=True, showgrid=True, showline=True, title=None, ticks='outside', linewidth=1, linecolor='black', tickangle=25)
        fig.update_yaxes(mirror=True, showgrid=True, showline=True, ticks='outside', linewidth=1, linecolor='black', rangemode="tozero", range=[0,500])
        fig.update_layout(title=None,  margin=dict(l=20, r=20, t=27, b=20), width=800, legend_title=None) #legend_traceorder="reversed",
        fig.update_layout(legend=dict(
            yanchor="top",
            y=0.95,
            xanchor="left",
            x=0.6,
            bgcolor ='rgba(255,255,255,0.8)',
            bordercolor='black',
            borderwidth=1),
            font=dict(
                size=14)
            )

        # # adds savings at top of plot
        # measure_name = list(color_map.keys())[1]
        # # print(measure_name)
        # # print(df_emi_gb_long)
        # df_emi_plot_gb = df_emi_gb_long.groupby(column_for_grouping)['Greenhouse Gas Emissions (MMT)'].sum().to_frame()
        # # print(df_emi_plot_gb)
        # # print('')
        # # print((df_emi_plot_gb.loc['Baseline'] - df_emi_plot_gb.loc[measure_name]).values[0])
        # # print(type((df_emi_plot_gb.loc['Baseline'] - df_emi_plot_gb.loc[measure_name]) + 3))
        # # print('')
        # df_emi_plot_gb.loc[measure_name] = f"Savings = {round((df_emi_plot_gb.loc['Baseline'] - df_emi_plot_gb.loc[measure_name]).values[0], 1)} ({round(((df_emi_plot_gb.loc['Baseline'] - df_emi_plot_gb.loc[measure_name])/(df_emi_plot_gb.loc['Baseline'])*100).values[0], 1)}%)"
        # df_emi_plot_gb.loc['Baseline'] = ''
        # # print(df_emi_plot_gb)

        # fig.add_trace(go.Scatter(
        # x=df_emi_plot_gb.index,
        # y=df_emi_plot_gb,
        # text=df_emi_plot_gb,
        # mode='text',
        # textposition='top center',
        # textfont=dict(
        #     size=12,
        # ),
        # showlegend=False
        # ))

        # add callout for electricity scenarios - make 4 lines and text
        fig.add_shape(type="line",
        xref="paper", yref="paper",
        x0=0.005, y0=0.98,
        x1=0.50, y1=0.98,
        line_color="black",
        opacity=1,
        line_width=1,
        )

        fig.add_shape(type="line",
        xref="paper", yref="paper",
        x0=0.005, y0=0.98,
        x1=0.005, y1=0.94,
        line_color="black",
        opacity=1,
        line_width=1,
        )

        fig.add_shape(type="line",
        xref="paper", yref="paper",
        x0=0.50, y0=0.98,
        x1=0.50, y1=0.94,
        line_color="black",
        opacity=1,
        line_width=1,
        )

        fig.add_shape(type="line",
        xref="paper", yref="paper",
        x0=0.25, y0=0.98,
        x1=0.25, y1=1.00,
        line_color="black",
        opacity=1,
        line_width=1,
        )

        text="Electricity Grid Scenarios: Choose 1"
        fig.add_annotation(
        x=0.1,
        y=1.05,
        text=text,
        xref="paper",
        yref="paper",
        showarrow=False,
        font_size=12
        )

        # figure name and save
        fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
        fig_sub_dir = os.path.join(output_dir)
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path = os.path.join(fig_sub_dir, fig_name)
        fig.write_image(fig_path, scale=10)

    def plot_floor_area_and_energy_totals(self, df, column_for_grouping, color_map, output_dir):
        # Summarize square footage and energy totals

        # Columns to summarize
        cols_to_summarize = {
            self.col_name_to_weighted(self.FLR_AREA): np.sum,
            self.col_name_to_weighted(self.ANN_TOT_ENGY_KBTU, 'tbtu'): np.sum,
            self.col_name_to_weighted(self.ANN_TOT_ELEC_KBTU, 'tbtu'): np.sum,
            self.col_name_to_weighted(self.ANN_TOT_GAS_KBTU, 'tbtu'): np.sum,
            # 'Normalized Annual major fuel consumption (thous Btu per sqft)': np.mean,
            # 'Normalized Annual electricity consumption (thous Btu per sqft)': np.mean,
            # 'Normalized Annual natural gas consumption (thous Btu per sqft)': np.mean
        }

        # Disaggregate to these levels
        group_bys = [
            None,
            self.CEN_DIV,
            self.BLDG_TYPE,
            # self.FLR_AREA_CAT, TODO reenable after adding to both CBECS and ComStock
            self.VINTAGE,
        ]

        for col, agg_method in cols_to_summarize.items(): # loops through column names and provides agg function for specific column

            for group_by in group_bys: # loops through group by options

                # Summarize the data
                if group_by is None:

                    # No group-by
                    g = sns.catplot(
                        data=df,
                        x=column_for_grouping,
                        y=col,
                        estimator=agg_method,
                        order=list(color_map.keys()),
                        palette=color_map.values(),
                        kind='bar',
                        errorbar=None,
                        aspect=1.5
                    )
                else:
                    # With group-by
                    g = sns.catplot(
                        data=df,
                        y=col,
                        estimator=agg_method,
                        hue=column_for_grouping,
                        x=group_by,
                        order=self.ORDERED_CATEGORIES[group_by],
                        hue_order=list(color_map.keys()),
                        palette=color_map.values(),
                        kind='bar',
                        errorbar=None,
                        aspect=2
                    )
                    g._legend.set_title(self.col_name_to_nice_name(column_for_grouping))

                fig = g.figure

                # Extract the units from the column name
                units = self.nice_units(self.units_from_col_name(col))

                # Title and axis labels
                if group_by is None:
                    # No group-by
                    title = f'{self.col_name_to_nice_name(col)}'
                    for ax in g.axes.flatten():
                        ax.set_ylabel(f'{self.col_name_to_nice_name(col)} ({units})')
                        ax.set_xlabel('')
                else:
                    # With group-by
                    title = f'{self.col_name_to_nice_name(col)}\n by {self.col_name_to_nice_name(group_by)}'
                    for ax in g.axes.flatten():
                        ax.set_ylabel(f'{self.col_name_to_nice_name(col)} ({units})')
                        ax.set_xlabel(f'{self.col_name_to_nice_name(group_by)}')
                        ax.tick_params(axis='x', labelrotation = 90)

                # Formatting
                fig.subplots_adjust(top=0.9)

                # Save figure
                title = title.replace('\n', '')
                fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
                fig_name = fig_name.replace('_total_energy_consumption', '')
                fig_path = os.path.join(output_dir, fig_name)
                plt.savefig(fig_path, bbox_inches = 'tight')
                plt.close()

    def plot_eui_boxplots(self, df, column_for_grouping, color_map, output_dir):
        # EUI box plot comparisons by building type and several disaggregations

        # Columns to summarize
        cols_to_summarize = [
            self.col_name_to_eui(self.ANN_TOT_ENGY_KBTU),
            self.col_name_to_eui(self.ANN_TOT_ELEC_KBTU),
            self.col_name_to_eui(self.ANN_TOT_GAS_KBTU),
        ]

        # Disaggregate to these levels
        group_bys = [
            None,
            self.BLDG_TYPE
        ]

        for col in cols_to_summarize:
            # for bldg_type, bldg_type_ts_df in df.groupby(self.BLDG_TYPE):

            # Make a plot for each group
            for group_by in group_bys:
                if group_by is None:
                    # No group-by
                    g = sns.catplot(
                        data=df,
                        y=column_for_grouping,
                        x=col,
                        order=list(color_map.keys()),
                        palette=color_map.values(),
                        kind='box',
                        orient='h',
                        fliersize=0,
                        showmeans=True,
                        meanprops={"marker":"d",
                            "markerfacecolor":"yellow",
                            "markeredgecolor":"black",
                            "markersize":"8"
                        }
                    )
                else:
                    # With group-by
                    g = sns.catplot(
                        data=df,
                        x=col,
                        hue=column_for_grouping,
                        y=group_by,
                        order=self.ORDERED_CATEGORIES[group_by],
                        hue_order=list(color_map.keys()),
                        palette=color_map.values(),
                        kind='box',
                        orient='h',
                        fliersize=0,
                        showmeans=True,
                        meanprops={"marker":"d",
                            "markerfacecolor":"yellow",
                            "markeredgecolor":"black",
                            "markersize":"8"
                        },
                        aspect=2
                    )
                    g._legend.set_title(self.col_name_to_nice_name(column_for_grouping))

                fig = g.figure

                # Extract the units from the column name
                units = self.nice_units(self.units_from_col_name(col))

                # Titles and axis labels
                col_title = self.col_name_to_nice_name(col)
                # col_title = col.replace(f' {units}', '')
                # col_title = col_title.replace('Normalized Annual ', '')
                fuel = self.col_name_to_fuel(col_title)

                # Formatting
                if group_by is None:
                    # No group-by
                    title = f"Boxplot of {col_title}".title()
                    for ax in g.axes.flatten():
                        ax.set_xlabel(f'{fuel} EUI ({units})')
                        ax.set_ylabel('')
                else:
                    # With group-by
                    gb = self.col_name_to_nice_name(group_by)
                    title = f"Boxplot of {col_title} by {f'{gb}'}".title()
                    for ax in g.axes.flatten():
                        ax.set_xlabel(f'{fuel} EUI ({units})')
                        ax.set_ylabel(f'{gb}')

                # Save figure
                title = title.replace('\n', '')
                fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
                fig_name = fig_name.replace('boxplot_of_', 'bp_')
                fig_name = fig_name.replace('total_energy_consumption_', '')
                fig_path = os.path.join(output_dir, fig_name)
                plt.savefig(fig_path, bbox_inches = 'tight')
                plt.close()

    def plot_floor_area_and_energy_totals_by_building_type(self, df, column_for_grouping, color_map, output_dir):
        # Summarize square footage and energy totals by building type

        # Columns to summarize
        cols_to_summarize = {
            self.col_name_to_weighted(self.FLR_AREA): np.sum,
            self.col_name_to_weighted(self.ANN_TOT_ENGY_KBTU, 'tbtu'): np.sum,
            self.col_name_to_weighted(self.ANN_TOT_ELEC_KBTU, 'tbtu'): np.sum,
            self.col_name_to_weighted(self.ANN_TOT_GAS_KBTU, 'tbtu'): np.sum,
            # 'Normalized Annual major fuel consumption (thous Btu per sqft)': np.mean,
            # 'Normalized Annual electricity consumption (thous Btu per sqft)': np.mean,
            # 'Normalized Annual natural gas consumption (thous Btu per sqft)': np.mean
        }

        # Disaggregate to these levels
        group_bys = [
            None,
            self.CEN_DIV,
            # self.FLR_AREA_CAT, TODO reenable after adding to both CBECS and ComStock
            # self.VINTAGE,
        ]

        for col, agg_method in cols_to_summarize.items():
            for bldg_type, bldg_type_ts_df in df.groupby(self.BLDG_TYPE):

                # Make a plot for each group
                for group_by in group_bys:
                    if group_by is None:
                        # No group-by
                        g = sns.catplot(
                            data=bldg_type_ts_df,
                            x=column_for_grouping,
                            y=col,
                            estimator=agg_method,
                            order=list(color_map.keys()),
                            palette=color_map.values(),
                            errorbar=None,
                            kind='bar',
                            aspect=1.5
                        )
                    else:
                        # With group-by
                        g = sns.catplot(
                            data=bldg_type_ts_df,
                            y=col,
                            hue=column_for_grouping,
                            x=group_by,
                            estimator=agg_method,
                            order=self.ORDERED_CATEGORIES[group_by],
                            hue_order=list(color_map.keys()),
                            palette=color_map.values(),
                            kind='bar',
                            errorbar=None,
                            aspect=2
                        )
                        g._legend.set_title(self.col_name_to_nice_name(column_for_grouping))

                    fig = g.figure

                    # Extract the units from the column name
                    units = self.nice_units(self.units_from_col_name(col))

                    # Titles and axis labels
                    col_title = self.col_name_to_nice_name(col)
                    # col_title = col.replace(f' {units}', '')
                    # col_title = col_title.replace('Normalized Annual ', '')

                    # Formatting
                    if group_by is None:
                        # No group-by
                        title = f"{col_title}\n for {bldg_type.replace('_', ' ')}".title()
                        for ax in g.axes.flatten():
                            ax.set_ylabel(f'{col_title} ({units})')
                            ax.set_xlabel('')
                    else:
                        # With group-by
                        gb = self.col_name_to_nice_name(group_by)
                        title = f"{col_title}\n for {bldg_type.replace('_', ' ')} by {f'{gb}'}".title()
                        for ax in g.axes.flatten():
                            ax.set_ylabel(f'{col_title} ({units})')
                            ax.set_xlabel(f'{gb}')
                            ax.tick_params(axis='x', labelrotation = 90)

                    # Save figure
                    title = title.replace('\n', '')
                    fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
                    fig_name = fig_name.replace('_total_energy_consumption', '')
                    fig_sub_dir = os.path.join(output_dir, bldg_type)
                    if not os.path.exists(fig_sub_dir):
                        os.makedirs(fig_sub_dir)
                    fig_path = os.path.join(fig_sub_dir, fig_name)
                    plt.savefig(fig_path, bbox_inches = 'tight')
                    plt.close()

    def plot_end_use_totals_by_building_type(self, df, column_for_grouping, color_map, output_dir):
        # Summarize end use energy totals by building type

        # End uses to include
        end_use_cols = self.COLS_ENDUSE_ANN_ENGY
        wtd_end_use_cols = [self.col_name_to_weighted(c, 'tbtu') for c in end_use_cols]

        # Disaggregate to these levels
        group_bys = [
            # None,
            self.CEN_DIV,
            # self.FLR_AREA_CAT, TODO reenable after adding to both CBECS and ComStock
            # self.VINTAGE,
        ]

        # How the data will be combined
        agg_method = np.sum  # Could use np.mean etc. for different look at data

        # Extract the units from the name of the first column
        units = self.nice_units(self.units_from_col_name(wtd_end_use_cols[0]))

        for bldg_type, bldg_type_df in df.groupby(self.BLDG_TYPE):
            for group_by in group_bys:
                var_name = 'End Use'
                val_name = f'Energy Consumption ({units})'
                tots_long = pd.melt(
                    bldg_type_df,
                    id_vars=[
                        column_for_grouping,
                        group_by
                    ],
                    value_vars=wtd_end_use_cols,
                    var_name=var_name,
                    value_name=val_name
                )
                # logger.debug(tots_long)

                g = sns.catplot(
                    data=tots_long,
                    x=group_by,
                    y=val_name,
                    row=var_name,
                    hue=column_for_grouping,
                    estimator=agg_method,
                    order=self.ORDERED_CATEGORIES[group_by],
                    hue_order=list(color_map.keys()),
                    palette=color_map.values(),
                    sharex=False,
                    kind='bar',
                    errorbar=None,
                    aspect=3
                )
                g._legend.set_title(self.col_name_to_nice_name(column_for_grouping))

                fig = g.figure

                # Titles and axis labels

                # Formatting
                gb = self.col_name_to_nice_name(group_by)
                title = f"End Use Energy Consumption \n for {bldg_type.replace('_', ' ')} by {f'{gb}'}".title()
                for ax in g.axes.flatten():
                    # Improve the title and move to the y-axis label
                    ax_title = ax.get_title()
                    ax_title = ax_title.replace(f'{var_name} = ', '')
                    ax_units = self.units_from_col_name(ax_title)
                    ax_title = self.col_name_to_nice_name(ax_title)
                    ax_title = ax_title.replace('Energy Consumption', f'({ax_units})')
                    ax_title = ax_title.replace(' ', '\n')
                    ax.set_ylabel(ax_title, rotation=0, ha='right')
                    ax.set_title('')
                ax.set_xlabel(gb)

                g.tight_layout()

                # Save figure
                title = title.replace('\n', '')
                fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
                fig_sub_dir = os.path.join(output_dir, bldg_type)
                if not os.path.exists(fig_sub_dir):
                    os.makedirs(fig_sub_dir)
                fig_path = os.path.join(fig_sub_dir, fig_name)
                plt.savefig(fig_path, bbox_inches = 'tight')
                plt.close()

    def plot_eui_histograms_by_building_type(self, df, column_for_grouping, color_map, output_dir):
        # EUI histogram comparisons by building type

        # Columns to summarize
        cols_to_summarize = [
            self.col_name_to_eui(self.ANN_TOT_ENGY_KBTU),
            self.col_name_to_eui(self.ANN_TOT_ELEC_KBTU),
            self.col_name_to_eui(self.ANN_TOT_GAS_KBTU),
        ]

        # Disaggregate to these levels
        group_bys = [
            None,
            # self.CEN_DIV,
            # self.FLR_AREA_CAT, TODO reenable after adding to both CBECS and ComStock
            # self.VINTAGE,
        ]

        for col in cols_to_summarize:
            for bldg_type, bldg_type_ts_df in df.groupby(self.BLDG_TYPE):
                # Group as specified
                group_ts_dfs = {}
                for group_by in group_bys:
                    if group_by is None:
                        # No group-by
                        group_ts_dfs[None] = bldg_type_ts_df
                    else:
                        # With group-by
                        for group, group_ts_df in bldg_type_ts_df.groupby(group_by):
                            group_ts_dfs[group] = group_ts_df

                # Plot a histogram for each group
                for group, group_ts_df in group_ts_dfs.items():
                    # Create a common bin size and count to use for both datasets
                    min_eui = group_ts_df[col].min()
                    max_eui = group_ts_df[col].max()
                    # max_eui = group_ts_df[col].quantile(0.9)  # Could use 90th percentile to trim tails if desired
                    n_bins = 100
                    bin_size = (max_eui - min_eui) / n_bins
                    logger.debug(f'bldg_type: {bldg_type}, min_eui: {min_eui}, max_eui: {max_eui}, n_bins: {n_bins}, bin_size: {bin_size}')

                    # Make the histogram
                    for dataset, dataset_ts_df in group_ts_df.groupby(column_for_grouping):
                        euis = dataset_ts_df[col]
                        n_samples = len(euis)

                        # Select the color for this dataset
                        ds_color = color_map[dataset]

                        # Weight each sample by the fraction of total sqft it represents, NOT by the fraction of the building count it represents
                        wts = dataset_ts_df[self.col_name_to_weighted(self.FLR_AREA)] / dataset_ts_df[self.col_name_to_weighted(self.FLR_AREA)].sum()
                        n, bins, barcontainer = plt.hist(euis, weights=wts, range=(min_eui, max_eui), bins=n_bins, alpha=0.75, label=f'{dataset}, n={n_samples}', color=ds_color)

                        # Calculate the area-weighted mean
                        mean_eui = (euis * wts).sum()
                        plt.axvline(x=mean_eui, ymin=0, ymax=0.02,  alpha=1, ls = '', marker = 'd', mec='black', ms=10, label=f'{dataset} Mean', color=ds_color)

                    # Extract the units from the column name
                    units = self.nice_units(self.units_from_col_name(col))

                    # Titles and axis labels
                    col_title = self.col_name_to_nice_name(col)
                    col_title = col_title.replace('Normalized Annual ', '')
                    fuel = self.col_name_to_fuel(col_title)
                    if group is None:
                        # No group-by
                        title = f"Distribution of {col_title}\n for {bldg_type.replace('_', ' ')}".title()
                    else:
                        # With group-by
                        title = f"Distribution of {col_title}\n for {bldg_type.replace('_', ' ')} in {f'{group}'}".title()

                    plt.xlabel(f'{fuel} EUI ({units})\nbin size = {round(bin_size, 1)}')
                    plt.ylabel('Area-weighted fraction')
                    plt.legend()

                    # Save figure
                    title = title.replace('\n', '')
                    fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
                    fig_name = fig_name.replace('distribution_of_', 'dist_')
                    fig_sub_dir = os.path.join(output_dir, bldg_type)
                    if not os.path.exists(fig_sub_dir):
                        os.makedirs(fig_sub_dir)
                    fig_path = os.path.join(fig_sub_dir, fig_name)
                    plt.savefig(fig_path, bbox_inches = 'tight')
                    plt.cla()
                    plt.close()

    def plot_eui_boxplots_by_building_type(self, df, column_for_grouping, color_map, output_dir):
        # EUI box plot comparisons by building type and several disaggregations

        # Columns to summarize
        cols_to_summarize = [
            self.col_name_to_eui(self.ANN_TOT_ENGY_KBTU),
            self.col_name_to_eui(self.ANN_TOT_ELEC_KBTU),
            self.col_name_to_eui(self.ANN_TOT_GAS_KBTU),
        ]

        # Disaggregate to these levels
        group_bys = [
            None,
            self.CEN_DIV,
            # self.FLR_AREA_CAT, TODO reenable after adding to both CBECS and ComStock
            # self.VINTAGE,
        ]

        for col in cols_to_summarize:
            for bldg_type, bldg_type_ts_df in df.groupby(self.BLDG_TYPE):

                # Make a plot for each group
                for group_by in group_bys:
                    if group_by is None:
                        # No group-by
                        g = sns.catplot(
                            data=bldg_type_ts_df,
                            y=column_for_grouping,
                            x=col,
                            order=list(color_map.keys()),
                            palette=color_map.values(),
                            kind='box',
                            orient='h',
                            fliersize=0,
                            showmeans=True,
                            meanprops={"marker":"d",
                                "markerfacecolor":"yellow",
                                "markeredgecolor":"black",
                                "markersize":"8"
                            }
                        )
                    else:
                        # With group-by
                        g = sns.catplot(
                            data=bldg_type_ts_df,
                            x=col,
                            hue=column_for_grouping,
                            y=group_by,
                            order=self.ORDERED_CATEGORIES[group_by],
                            hue_order=list(color_map.keys()),
                            palette=color_map.values(),
                            kind='box',
                            orient='h',
                            fliersize=0,
                            showmeans=True,
                            meanprops={"marker":"d",
                                "markerfacecolor":"yellow",
                                "markeredgecolor":"black",
                                "markersize":"8"
                            },
                            aspect=2
                        )
                        g._legend.set_title(self.col_name_to_nice_name(column_for_grouping))

                    fig = g.figure

                    # Extract the units from the column name
                    units = self.nice_units(self.units_from_col_name(col))

                    # Titles and axis labels
                    col_title = self.col_name_to_nice_name(col)
                    # col_title = col.replace(f' {units}', '')
                    # col_title = col_title.replace('Normalized Annual ', '')
                    fuel = self.col_name_to_fuel(col_title)

                    # Formatting
                    if group_by is None:
                        # No group-by
                        title = f"Boxplot of {col_title}\n for {bldg_type.replace('_', ' ')}".title()
                        for ax in g.axes.flatten():
                            ax.set_xlabel(f'{fuel} EUI ({units})')
                            ax.set_ylabel('')
                    else:
                        # With group-by
                        gb = self.col_name_to_nice_name(group_by)
                        title = f"Boxplot of {col_title}\n for {bldg_type.replace('_', ' ')} by {f'{gb}'}".title()
                        for ax in g.axes.flatten():
                            ax.set_xlabel(f'{fuel} EUI ({units})')
                            ax.set_ylabel(f'{gb}')

                    # Save figure
                    title = title.replace('\n', '')
                    fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
                    fig_name = fig_name.replace('boxplot_of_', 'bp_')
                    fig_name = fig_name.replace('total_energy_consumption_', '')
                    fig_sub_dir = os.path.join(output_dir, bldg_type)
                    if not os.path.exists(fig_sub_dir):
                        os.makedirs(fig_sub_dir)
                    fig_path = os.path.join(fig_sub_dir, fig_name)
                    plt.savefig(fig_path, bbox_inches = 'tight')
                    plt.close()

    def plot_measure_savings_distributions_by_building_type(self, df, output_dir):

        # remove baseline; not needed
        df_upgrade = df.loc[df[self.UPGRADE_ID]!=0, :]

        # get upgrade name and id for labeling
        upgrade_num = df_upgrade[self.UPGRADE_ID].iloc[0]
        upgrade_name = df_upgrade[self.UPGRADE_NAME].iloc[0]

        # group column
        col_group = self.BLDG_TYPE

        # energy column
        en_col = self.ANN_TOT_ENGY_KBTU

        # set grouping list
        li_group = sorted(list(df_upgrade[col_group].drop_duplicates().astype(str)), reverse=True)

        # make lists of columns; these savings columns should exist in dataframe
        # enduse
        dict_saving = {}
        li_eui_svgs_btype = self.col_name_to_savings(self.col_name_to_eui(en_col))
        dict_saving['Site EUI Savings by Building Type (kBtu/ft<sup>2</sup>)'] = li_eui_svgs_btype
        li_pct_svgs_btype = self.col_name_to_percent_savings(en_col, 'percent')
        dict_saving['Percent Site Energy Savings by Building Type (%)'] = li_pct_svgs_btype

        # # loop through plot types
        for group_name, energy_col in dict_saving.items():

            # remove unit from group_name
            group_name_wo_unit = group_name.rsplit(" ", 1)[0]

            # filter to group and energy column
            df_upgrade_plt = df_upgrade.loc[:, [col_group, energy_col]]

            # apply method for filtering percent savings; this will not affect EUI
            df_upgrade_plt = self.filter_outlier_pct_savings_values(df_upgrade_plt, 1)

            # create figure template
            fig = go.Figure()

            # loop through groups, i.e. building type etc.
            for group in li_group:

                # get data for enduse; remove 0s and na values
                df_enduse = df_upgrade_plt.loc[(df_upgrade_plt[energy_col]!=0) & ((df_upgrade_plt[col_group]==group)), energy_col]

                # add traces to plot
                fig.add_trace(go.Violin(
                    x=df_enduse,
                    y=np.array(group),
                    orientation = 'h',
                    box_visible=True,
                    points='outliers',
                    pointpos=1,
                    spanmode='hard',
                    marker_size=1,
                    showlegend=False,
                    name=str(group) + f' (n={len(df_enduse)})',
                    meanline_visible=True,
                    line=dict(width=0.7),
                    fillcolor=color_violin,
                    box_fillcolor=color_interquartile,
                    line_color='black',
                    width=0.95
                ))

            fig.add_annotation(
                align="right",
                font_size=12,
                showarrow=False,
                text=f"Upgrade {str(upgrade_num).zfill(2)}: {upgrade_name} (unweighted)",
                x=1,
                xanchor="right",
                xref="x domain",
                y=1.01,
                yanchor="bottom",
                yref="y domain",
            )

            title = group_name_wo_unit
            # formatting and saving image
            fig.update_layout(template='simple_white', margin=dict(l=20, r=20, t=20, b=20), width=800)
            fig.update_xaxes(mirror=True, showgrid=True, zeroline=True, nticks=16, title=group_name)
            fig.update_yaxes(mirror=True, showgrid=True, type='category', dtick=1)
            fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
            fig_name = fig_name.replace('_total_energy_consumption', '')
            fig_sub_dir = os.path.join(output_dir, 'savings_distributions')
            if not os.path.exists(fig_sub_dir):
                os.makedirs(fig_sub_dir)
            fig_path = os.path.join(fig_sub_dir, fig_name)
            fig.write_image(fig_path, scale=10)

        return

    def plot_measure_savings_distributions_by_climate_zone(self, df, output_dir):

        # remove baseline; not needed
        df_upgrade = df.loc[df[self.UPGRADE_ID]!=0, :]

        # get upgrade name and id for labeling
        upgrade_num = df_upgrade[self.UPGRADE_ID].iloc[0]
        upgrade_name = df_upgrade[self.UPGRADE_NAME].iloc[0]

        # group column
        col_group = self.CZ_ASHRAE

        # energy column
        en_col = self.ANN_TOT_ENGY_KBTU

        # set grouping list
        li_group = sorted(list(df_upgrade[col_group].unique().astype(str)), reverse=True)

        # make lists of columns; these savings columns should exist in dataframe
        # enduse
        dict_saving = {}
        li_eui_svgs_btype = self.col_name_to_savings(self.col_name_to_eui(en_col))
        dict_saving['Site EUI Savings by Climate Zone (kBtu/ft<sup>2</sup>)'] = li_eui_svgs_btype
        li_pct_svgs_btype = self.col_name_to_percent_savings(en_col, 'percent')
        dict_saving['Percent Site Energy Savings by Climate Zone (%)'] = li_pct_svgs_btype

        # # loop through plot types
        for group_name, energy_col in dict_saving.items():

            # remove unit from group_name
            group_name_wo_unit = group_name.rsplit(" ", 1)[0]

            # filter to group and energy column
            df_upgrade_plt = df_upgrade.loc[:, [col_group, energy_col]]

            # apply method for filtering percent savings; this will not affect EUI metrics
            df_upgrade_plt = self.filter_outlier_pct_savings_values(df_upgrade_plt, 1)

            # create figure template
            fig = go.Figure()

            # loop through groups, i.e. building type etc.
            for group in li_group:

                # get data for enduse; remove 0s and na values
                df_enduse = df_upgrade_plt.loc[(df_upgrade_plt[energy_col]!=0) & ((df_upgrade_plt[col_group]==group)), energy_col]

                # add traces to plot
                fig.add_trace(go.Violin(
                    x=df_enduse,
                    y=np.array(group),
                    orientation = 'h',
                    box_visible=True,
                    points='outliers',
                    pointpos=1,
                    spanmode='hard',
                    marker_size=1,
                    showlegend=False,
                    name=str(group) + f' (n={len(df_enduse)})',
                    meanline_visible=True,
                    line=dict(width=0.7),
                    fillcolor=color_violin,
                    box_fillcolor=color_interquartile,
                    line_color='black',
                    width=0.95
                ))

            fig.add_annotation(
                align="right",
                font_size=12,
                showarrow=False,
                text=f"Upgrade {str(upgrade_num).zfill(2)}: {upgrade_name} (unweighted)",
                x=1,
                xanchor="right",
                xref="x domain",
                y=1.01,
                yanchor="bottom",
                yref="y domain",
            )

            title = group_name_wo_unit
            # formatting and saving image
            fig.update_layout(template='simple_white', margin=dict(l=20, r=20, t=20, b=20), width=800)
            fig.update_xaxes(mirror=True, showgrid=True, zeroline=True, nticks=16, title=group_name)
            fig.update_yaxes(mirror=True, showgrid=True, type='category', dtick=1)
            fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
            fig_sub_dir = os.path.join(output_dir, 'savings_distributions')
            if not os.path.exists(fig_sub_dir):
                os.makedirs(fig_sub_dir)
            fig_path = os.path.join(fig_sub_dir, fig_name)
            fig.write_image(fig_path, scale=10)

        return

    def plot_measure_savings_distributions_by_hvac_system_type(self, df, output_dir):

        # remove baseline; not needed
        df_upgrade = df.loc[df[self.UPGRADE_ID]!=0, :]

        # get upgrade name and id for labeling
        upgrade_num = df_upgrade[self.UPGRADE_ID].iloc[0]
        upgrade_name = df_upgrade[self.UPGRADE_NAME].iloc[0]

        # group column
        col_group = self.HVAC_SYS

        # energy column
        en_col = self.ANN_TOT_ENGY_KBTU

        # set grouping list
        li_group = sorted(list(df_upgrade[col_group].drop_duplicates().astype(str)), reverse=True)

        # make lists of columns; these savings columns should exist in dataframe
        # enduse
        dict_saving = {}
        li_eui_svgs_btype = self.col_name_to_savings(self.col_name_to_eui(en_col))
        dict_saving['Site EUI Savings by HVAC System (kBtu/ft<sup>2</sup>)'] = li_eui_svgs_btype
        li_pct_svgs_btype = self.col_name_to_percent_savings(en_col, 'percent')
        dict_saving['Percent Site Energy Savings by HVAC System (%)'] = li_pct_svgs_btype

        # # loop through plot types
        for group_name, energy_col in dict_saving.items():

            # remove unit from group_name
            group_name_wo_unit = group_name.rsplit(" ", 1)[0]

            # filter to group and energy column
            df_upgrade_plt = df_upgrade.loc[:, [col_group, energy_col]]

            # apply method for filtering percent savings; this will not affect EUI
            df_upgrade_plt = self.filter_outlier_pct_savings_values(df_upgrade_plt, 1)

            # create figure template
            fig = go.Figure()

            # loop through groups, i.e. building type etc.
            for group in li_group:

                # get data for enduse; remove 0s and na values
                df_enduse = df_upgrade_plt.loc[(df_upgrade_plt[energy_col]!=0) & ((df_upgrade_plt[col_group]==group)), energy_col]

                # add traces to plot
                fig.add_trace(go.Violin(
                    x=df_enduse,
                    y=np.array(group),
                    orientation = 'h',
                    box_visible=True,
                    points='outliers',
                    pointpos=1,
                    spanmode='hard',
                    marker_size=1,
                    showlegend=False,
                    name=str(group) + f' (n={len(df_enduse)})',
                    meanline_visible=True,
                    line=dict(width=0.7),
                    fillcolor=color_violin,
                    box_fillcolor=color_interquartile,
                    line_color='black',
                    width=0.95
                ))

            fig.add_annotation(
                align="right",
                font_size=12,
                showarrow=False,
                text=f"Upgrade {str(upgrade_num).zfill(2)}: {upgrade_name} (unweighted)",
                x=1,
                xanchor="right",
                xref="x domain",
                y=1.01,
                yanchor="bottom",
                yref="y domain",
            )

            title = group_name_wo_unit
            # formatting and saving image
            fig.update_layout(template='simple_white', margin=dict(l=20, r=20, t=20, b=20), width=800)
            fig.update_xaxes(mirror=True, showgrid=True, zeroline=True, nticks=16, title=group_name, automargin=True)
            fig.update_yaxes(mirror=True, showgrid=True, nticks=len(li_group), type='category', dtick=1, automargin=True)
            fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
            fig_sub_dir = os.path.join(output_dir, 'savings_distributions')
            if not os.path.exists(fig_sub_dir):
                os.makedirs(fig_sub_dir)
            fig_path = os.path.join(fig_sub_dir, fig_name)
            fig.write_image(fig_path, scale=10)


        return

    def plot_measure_savings_distributions_enduse_and_fuel(self, df, output_dir):

        # remove baseline; not needed
        df_upgrade = df.loc[df[self.UPGRADE_ID]!=0, :]

        # get upgrade name and id for labeling;
        upgrade_num = df_upgrade[self.UPGRADE_ID].iloc[1]
        upgrade_name = df_upgrade[self.UPGRADE_NAME].iloc[1]

        # make lists of columns; these savings columns should exist in dataframe
        # enduse
        dict_saving = {}
        li_eui_svgs_enduse_cols = [self.col_name_to_savings(self.col_name_to_eui(c)) for c in self.COLS_ENDUSE_ANN_ENGY]
        dict_saving['Site EUI Savings by End Use (kBtu/ft<sup>2</sup>)'] = li_eui_svgs_enduse_cols
        li_pct_svgs_enduse_cols = [self.col_name_to_percent_savings(c, 'percent') for c in self.COLS_ENDUSE_ANN_ENGY]
        dict_saving['Percent Site Energy Savings by End Use (%)'] = li_pct_svgs_enduse_cols
        # fuel
        li_eui_svgs_fuel_cols = [self.col_name_to_savings(self.col_name_to_eui(c)) for c in self.COLS_TOT_ANN_ENGY]
        dict_saving['Site EUI Savings by Fuel (kBtu/ft<sup>2</sup>)'] = li_eui_svgs_fuel_cols
        li_pct_svgs_fuel_cols = [self.col_name_to_percent_savings(c, 'percent') for c in self.COLS_TOT_ANN_ENGY]
        dict_saving['Percent Site Energy Savings by Fuel (%)'] = li_pct_svgs_fuel_cols

        # loop through plot types
        for savings_name, col_list in dict_saving.items():

            # remove unit from savings_name
            savings_name_wo_unit = savings_name.rsplit(" ", 1)[0]

            # apply method for filtering percent savings; this will not affect EUI
            df_upgrade_plt = self.filter_outlier_pct_savings_values(df_upgrade[col_list], 1.5)

            # create figure template
            fig = go.Figure()

            # loop through enduses
            for enduse_col in col_list:

                # get data for enduse; remove 0s and na values
                df_enduse = df_upgrade_plt.loc[(df_upgrade_plt[enduse_col]!=0), enduse_col]

                # column name
                col_name = self.col_name_to_nice_saving_name(df_enduse.name)

                # add traces to plot
                fig.add_trace(go.Violin(
                    x=df_enduse,
                    y=np.array(col_name),
                    orientation = 'h',
                    box_visible=True,
                    points='outliers',
                    pointpos=1,
                    spanmode='hard',
                    marker_size=1,
                    showlegend=False,
                    name=str(col_name) + f'(n={len(df_enduse)})',
                    meanline_visible=True,
                    line=dict(width=0.7),
                    fillcolor=color_violin,
                    box_fillcolor=color_interquartile,
                    line_color='black',
                    width=0.95
                ))

            fig.add_annotation(
                align="right",
                font_size=12,
                showarrow=False,
                text=f"Upgrade {str(upgrade_num).zfill(2)}: {upgrade_name} (unweighted)",
                x=1,
                xanchor="right",
                xref="x domain",
                y=1.01,
                yanchor="bottom",
                yref="y domain",
            )

            title = savings_name_wo_unit
            # formatting and saving image
            fig.update_layout(template='simple_white', margin=dict(l=20, r=20, t=20, b=20), width=800)
            fig.update_xaxes(mirror=True, showgrid=True, zeroline=True, nticks=16, title=savings_name)
            fig.update_yaxes(mirror=True, showgrid=True, nticks=len(li_pct_svgs_enduse_cols), type='category', dtick=1)
            fig_name = f'{title.replace(" ", "_").lower()}.{self.image_type}'
            fig_sub_dir = os.path.join(output_dir, 'savings_distributions')
            if not os.path.exists(fig_sub_dir):
                os.makedirs(fig_sub_dir)
            fig_path = os.path.join(fig_sub_dir, fig_name)
            fig.write_image(fig_path, scale=10)

    def plot_qoi_timing(self, df, column_for_grouping, color_map, output_dir):

        qoi_timing = self.QOI_MAX_DAILY_TIMING_COLS

        short_names = []
        for col_name in qoi_timing:
            col_name = self.shorten_qoi_names(col_name)
            short_names.append(col_name)

        violin_qoi_timing = px.violin(
            data_frame = df,
            x = qoi_timing,
            orientation = 'h',
            box = True,
            points = 'outliers',
            color = column_for_grouping,
            color_discrete_sequence = list(color_map.values()),
            violinmode = "group",
            template='simple_white'
        )

        # formatting and saving image
        title="maximum_daily_peak_timing_hr"
        violin_qoi_timing.update_yaxes(mirror=True, title="Season", tickmode = "array", ticktext =short_names, tickvals=qoi_timing)
        violin_qoi_timing.update_xaxes(mirror=True, title="Maximum Daily Peak Timing by Season (Hour of Day)")
        violin_qoi_timing.update_layout(
            legend_title = self.col_name_to_nice_name(column_for_grouping),
            margin=dict(l=5, r=5, t=5, b=5),
            )
        fig_name = f'{title}.{self.image_type}'
        fig_sub_dir = os.path.join(output_dir, 'qoi_distributions')
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path = os.path.join(fig_sub_dir, fig_name)
        violin_qoi_timing.write_image(fig_path, scale=10)

    def plot_qoi_max_use(self, df, column_for_grouping, color_map, output_dir):

        max_use_cols_normalized = self.QOI_MAX_USE_COLS_NORMALIZED

        short_names = []
        for col_name in max_use_cols_normalized:
            col_name = self.shorten_qoi_names(col_name)
            short_names.append(col_name)

        violin_qoi_timing = px.violin(
            data_frame = df,
            x = max_use_cols_normalized,
            orientation = 'h',
            box = True,
            points = 'outliers',
            color = column_for_grouping,
            color_discrete_sequence = list(color_map.values()),
            violinmode = "group",
            template='simple_white'
        )

        # formatting and saving image
        title="maximum_daily_peak_magnitude_w_ft2"
        violin_qoi_timing.update_yaxes(mirror=True, title="Season",  tickmode = "array", ticktext =short_names, tickvals=max_use_cols_normalized)
        violin_qoi_timing.update_xaxes(mirror=True, title="Maximum Daily Peak Magnitude by Season (W/ft<sup>2</sup>)")
        violin_qoi_timing.update_layout(
            legend_title = self.col_name_to_nice_name(column_for_grouping),
            margin=dict(l=5, r=5, t=5, b=5),
            )
        fig_name = f'{title}.{self.image_type}'
        fig_sub_dir = os.path.join(output_dir, 'qoi_distributions')
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path = os.path.join(fig_sub_dir, fig_name)
        violin_qoi_timing.write_image(fig_path, scale=10)

    def plot_qoi_min_use(self, df, column_for_grouping, color_map, output_dir):

        min_use_cols_normalized = self.QOI_MIN_USE_COLS_NORMALIZED

        short_names = []
        for col_name in min_use_cols_normalized:
            col_name = self.shorten_qoi_names(col_name)
            short_names.append(col_name)

        violin_qoi_timing = px.violin(
            data_frame = df,
            x = min_use_cols_normalized,
            orientation = 'h',
            box = True,
            points = 'outliers',
            color = column_for_grouping,
            color_discrete_sequence = list(color_map.values()),
            violinmode = "group",
            template='simple_white'
        )

        # formatting and saving image
        title="minimum_daily_peak_magnitude_w_ft2"
        violin_qoi_timing.update_yaxes(mirror=True, title="Season", tickmode="array", ticktext=short_names, tickvals=min_use_cols_normalized)
        violin_qoi_timing.update_xaxes(mirror=True, title="Minimum Daily Peak Magnitude by Season (W/ft<sup>2</sup>)")
        violin_qoi_timing.update_layout(
            legend_title = self.col_name_to_nice_name(column_for_grouping),
            margin=dict(l=5, r=5, t=5, b=5),
            )
        fig_name = f'{title}.{self.image_type}'
        fig_sub_dir = os.path.join(output_dir, 'qoi_distributions')
        if not os.path.exists(fig_sub_dir):
            os.makedirs(fig_sub_dir)
        fig_path = os.path.join(fig_sub_dir, fig_name)
        violin_qoi_timing.write_image(fig_path, scale=10)

    def filter_outlier_pct_savings_values(self, df, max_fraction_change):

        # get applicable columns
        cols = df.loc[:, df.columns.str.contains('percent_savings')].columns

        # make copy of dataframe
        df_2 = df.copy()

        # filter out data that falls outside of user-input range by changing them to nan
        # when plotting, nan values will be skipped
        df_2.loc[:, cols] = df_2[cols].mask(df[cols]>max_fraction_change, np.nan)
        df_2.loc[:, cols] = df_2[cols].mask(df[cols]<-max_fraction_change, np.nan)

        # multiply by 100 to get percent savings
        df_2.loc[:, cols] = df_2[cols] * 100

        return df_2
