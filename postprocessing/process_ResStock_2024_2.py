###This code is meant to process small to moderate amounts of ResStock data from the 2024.2 data release, for any purpose but especially for use in generating standard figures for TA
# First Author: Elaina Present. Started Q2 FY25.
# Additional Contributors:
# Latest edits: 2025-02-26

import os
from textwrap import indent
import numpy as np
import pandas as pd

class process_ResStock_2024_2():
    def __init__(self, resstock_results_folder, resstock_file_name):
        #load ResStock data
        self.resstock_results_folder = resstock_results_folder
        self.resstock_file_name = resstock_file_name
        self._load_ResStock_data()
    
    def _load_ResStock_data(self):
        #load ResStock data - called as part of init (required)
        results_file_path = os.path.join(self.resstock_results_folder, self.resstock_file_name)
        self.data = pd.read_csv(results_file_path, engine = "pyarrow")

    def downselect_rows(self, downselect_row_fields, values_to_keep):
        #downselect to a subset of results (optional)
        for field, values in zip(downselect_row_fields, values_to_keep):
            self.data = self.data.loc[self.data[field].isin(values)]
    
    def make_data_testing_size(self, testing_size):
        self.data=self.data.head(testing_size)
    
    def load_and_process_column_plan(self, col_plan_folder, col_plan_name):
    #assign a plan for each column in the dataset, from a premade csv (required)
        plan_file_path = os.path.join(col_plan_folder, col_plan_name)
        self.col_plan = pd.read_csv(plan_file_path, engine = "pyarrow")
        #flag columns in the data that aren't in the column plan
        data_cols = self.data.columns.tolist()
        cols_in_plan = self.col_plan['column'].tolist()
        cols_not_in_plan = list(set(data_cols) - set(cols_in_plan))
        if len(cols_not_in_plan) > 0:
            print ("ERROR: These columns are in the data but not the column plan:") 
            print(cols_not_in_plan)
        #flag columns in the column plan that will need to be added to the data
        cols_not_in_data = list(set(cols_in_plan) - set(data_cols))
        if len(cols_not_in_data) > 0:
            print ("These columns are not in the data and will be added, with NaNs:")
            print (cols_not_in_data)
        #remake data in standard order and with cols of NAs so that all files have the same columns
        for col in cols_not_in_data:
            self.data[col] = np.nan
        self.data = self.data[cols_in_plan]
        #create lists of columns for use in pivoting and trimming data
        self.cols_to_remove = self.col_plan.loc[self.col_plan['plan']=='remove', 'column'].tolist()
        self.cols_wide = self.col_plan.loc[self.col_plan['plan']=='keep', 'column'].tolist()
        self.cols_to_pivot = self.col_plan.loc[self.col_plan['plan']=='pivot', 'column'].tolist()

    def add_local_bills(self, rate_inputs_df):
        #recalculate the utility bills. 
        #(Optional) but (Required) for any utility bill graphics or processing
        for index, row in rate_inputs_df.iterrows():
            #if all ng consumption is removed, add ng fixed cost to bill savings. So two criteria must be met: there must be natural gas savings and the current natural gas consumption must be 0
            if row['column']== "out.bills_local.natural_gas.total.usd.savings":
                self.data[row['column']] = row['fixed monthly cost']*12*(
                    np.logical_and(
                        (abs(self.data["out.natural_gas.total.energy_consumption.kwh.savings"])>0),
                        (self.data["out.natural_gas.total.energy_consumption.kwh"]==0))) + (
                            row['variable cost per kwh']*(
                                self.data[row['col list for scaling']].sum(axis = 1))) 
            # for each row of rate inputs, create a column in the data, which will be NaN if the scaling row doesn't exist (e.g savings rows in baseline) and 0 if the relevant consumption rows don't exist
            else:
                self.data[row['column']] = row['fixed monthly cost']*12*((self.data[row['col list for scaling']].sum(axis = 1))!=0) + row['variable cost per kwh']*(self.data[row['col list for scaling']].sum(axis = 1))
            if row['plan'] == 'pivot':
                self.cols_to_pivot = self.cols_to_pivot + [row['column']]
            elif row['plan'] == 'keep':
                self.cols_wide = self.cols_wide + [row['column']]
            else:
                self.cols_to_remove = self.cols_to_remove + [row['column']]
        plan_for_new_cols_df = self.rate_inputs_df.drop(['fixed monthly cost', 'variable cost per kwh', 'col list for scaling'], axis = 1)
        self.col_plan = pd.concat([self.col_plan, plan_for_new_cols_df], axis = 0, ignore_index=True)
    
    def add_first_costs(self, first_costs_inputs_df):
        #Add first costs, SPP, and NPV to the dataset
        #(Optional), (Required) for any first cost or NPV results
        cost_inputs_filepath = os.path.join(self.cost_inputs_folder, self.cost_inputs_filename)
        cost_inputs = pd.read_csv(cost_inputs_filepath, engine = "pyarrow")
        up_costs = []
        for index, row in self.data.iterrows():
            cost = 0
            upgrade = row["upgrade"]
            if upgrade == 0:
                up_costs.append(cost)
            elif (row['applicability']!=True):
                up_costs.append(cost)
            else:     #actually calculate costs          
                #extract necessary data
                location = row[cost_inputs['Location Field Match'][0]] #just using whatever geographic resolution the first row of Cost Inputs has, for now
                climate_zone = int(row["in.ashrae_iecc_climate_zone_2004"][0]) #just the number, not the letter
                hp_size_btuh = row["out.params.size_heating_system_primary_k_btu_h"]
                hp_size_tons = (hp_size_btuh *1000)/12000
                attic_floor_area_sf = row["out.params.floor_area_attic_ft_2"]
                num_exterior_doors = row["out.params.door_area_ft_2"]/20 #ResStock 2024.2 has 20ft2 total door area for any unit with exterior doors, which is approximately one door
                num_windows = row["out.params.window_area_ft_2"]/15 #15 ft2 seems like a decent proxy for average window size based on standard window sizes
                HPWH_gal = row["out.params.size_water_heater_gal"]
                pool_heater_tons = 1 #proxy for all pool heaters, based loosely on looking at availability at Home Depot website
                spa_heater_tons = 1 #proxy for all spa heaters
                applicability_criteria_1 = row[cost_inputs['Applicability Criteria Field1'][0]]#for now this only works if there's just one applicability critiera field that's constant for the whole cost inputs dataset

                # look up sum spec name on upgrade, location, and applicability criteria
                if row['upgrade'] ==16: #there's no applicability critieria for this one
                    selected_index = cost_inputs[np.logical_and(cost_inputs['Location Value Match'] == location, 
                                            cost_inputs["Upgrade"] == upgrade)].index.values.astype(int)[0]
                else:
                    selected_index = cost_inputs[np.logical_and(np.logical_and(cost_inputs['Location Value Match'] == location, 
                                            cost_inputs["Upgrade"] == upgrade),
                                            cost_inputs['Applicability Criteria Values1'] == applicability_criteria_1)].index.values.astype(int)[0]
                    #print(selected_index)
            
                hp_cost_per_ton = cost_inputs.loc[selected_index, "HP Cost Per Ton"]
                hpwh_cost_per_gal = cost_inputs.loc[selected_index, "HPWH Cost Per Gallon"]
                pool_heater_cost_per_ton = cost_inputs.loc[selected_index, "Pool Heater Cost Per Ton"]
                spa_heater_cost_per_ton = cost_inputs.loc[selected_index, "Spa Heater Cost Per Ton"]
                calc1_constant = cost_inputs.loc[selected_index, "Calc1 Constant"]
                calc2_constant1 = cost_inputs.loc[selected_index, "Calc2 Constant1"]
                calc2_constant2 = cost_inputs.loc[selected_index, "Calc2 Constant2"]
                calc3_constant1 = cost_inputs.loc[selected_index, "Calc3 Constant1"]
                calc3_constant2 = cost_inputs.loc[selected_index, "Calc3 Constant2"]
                calc4_constant1 = cost_inputs.loc[selected_index, "Calc4 Constant1"]
                calc4_constant2 = cost_inputs.loc[selected_index, "Calc4 Constant2"]
                calc1_coeff = cost_inputs.loc[selected_index, "Calc1 Coeff"]
                calc2_coeff = cost_inputs.loc[selected_index, "Calc2 Coeff"]
                calc3_coeff = cost_inputs.loc[selected_index, "Calc3 Coeff"]
                calc4_coeff = cost_inputs.loc[selected_index, "Calc4 Coeff"]
                fixed_costs_demo = cost_inputs.loc[selected_index, "Fixed Costs Demo"]
                fixed_costs_install = cost_inputs.loc[selected_index, "Fixed Costs Install"]
                #print(hp_cost_per_ton, hpwh_cost_per_gal, pool_heater_cost_per_ton, spa_heater_cost_per_ton, calc1_constant, calc2_constant1,
                #      calc2_constant2, calc3_constant1, calc3_constant2, calc4_constant1, calc4_constant2, calc1_coeff, calc2_coeff, calc3_coeff, 
                #      calc4_coeff, fixed_costs_demo, fixed_costs_install)
                #do the algabraic cost calc
                calc1 = attic_floor_area_sf * calc1_constant * calc1_coeff
                calc2 = (num_exterior_doors * calc2_constant1 + num_windows * calc2_constant2) * calc2_coeff
                if climate_zone < 4:
                    calc3 = calc3_constant1 * attic_floor_area_sf
                else:
                    calc3 = calc3_constant2 * attic_floor_area_sf
                if (climate_zone > 1 and climate_zone) < 4:
                    calc4 = calc4_constant1 * attic_floor_area_sf
                else:
                    calc4 = calc4_constant2 * attic_floor_area_sf
                cost = cost + (hp_size_tons * hp_cost_per_ton) + ( #coeffs are 0 where not applicable
                    HPWH_gal * hpwh_cost_per_gal) + (
                        pool_heater_tons * pool_heater_cost_per_ton) + (
                            spa_heater_tons * spa_heater_cost_per_ton) + (
                                calc1 * calc1_coeff) + (
                                    calc2 * calc2_coeff) + (
                                        calc3 * calc3_coeff) + (
                                            calc4 * calc4_coeff) + (
                                                fixed_costs_demo + fixed_costs_install)
                up_costs.append(float(cost))
            #print (upgrade)
            #print (cost)
        #assign new column of first costs
        self.data['out.first_costs.usd'] = up_costs
        #assign new column of simple payback periods. Note this is currently not robust at all, assumes there is a column called "out.bills_local.all_fuels.total.usd.savings" which there won't always be (e.g. if you are using direct ResStock bill calcs)
        self.data['out.simple_payback_period'] = self.data['out.first_costs.usd']/self.data[self.one_year_bill_savings_col]
        #calculate NPV
        npv_list = []
        for id_cost, id_savings in zip(self.data['out.first_costs.usd'], self.data[self.one_year_bill_savings_col]):
            cost_array = [0]*(self.npv_analysis_period + 1)
            cost_array[0] = id_cost
            savings_array = id_savings * (self.npv_analysis_period + 1)
            cash_flows = list(np.array(savings_array)-np.array(cost_array))
            npv = 0
            for year in range(0, self.npv_analysis_period + 1):
                npv += (1/((1+self.npv_discount_rate)**year)) * cash_flows[year]
            npv_list.append(npv)
        self.data['out.net_present_value'] = npv_list
        #add new cost-related to columns to the list of columns to be kept wide (not pivoted)
        self.cols_wide = self.cols_wide + ['out.first_costs.usd', 'out.simple_payback_period', 'out.net_present_value']
        #add new cost-related columns to the column plan
        first_costs_col_plan = pd.DataFrame({'column': ['out.first_costs.usd', 'out.simple_payback_period', 'out.net_present_value'], 
                                                'col_type': ['unique', 'unique', 'unique'], 'plan': ['keep', 'keep', 'keep'], 
                                'Result Type': ['First Cost', 'Simple Payback Period', 'Net Present Value'],
                                    'Fuel': ['NA', 'NA', 'NA'], 'End Use': ['NA', 'NA', 'NA'], 'End Use Category':['NA', 'NA', 'NA']})
        self.col_plan = pd.concat([self.col_plan, first_costs_col_plan], axis = 0, ignore_index=True)
    
    def add_additional_wide_fields(self, addl_wide_fields_df):
        #TODO
        #merge additional wide fields in and add them to the column plan
        #(Optional)
        for dfw, wide_mergeon_field, wide_merge_col, wide_merge_newname, wide_col_plan in zip(
            self.dfs_for_wide_fields, self.wide_mergeon_fields, self.wide_merge_cols, self.wide_merge_newnames, self.wide_col_plans):
            self.data = self.data.merge(dfw, [[wide_mergeon_field, wide_merge_col]], on = wide_mergeon_field, how = "left")
            self.data.rename(columns = {wide_merge_col:wide_merge_newname}, inplace = True)
            if self.wide_col_plan == 'pivot':
                self.cols_to_pivot = self.cols_to_pivot + [wide_merge_newname]
            elif self.wide_col_plan == 'keep':
                self.cols_wide = self.cols_wide + [wide_merge_newname]
            else:
                self.cols_to_remove = self.cols_to_remove + [wide_merge_newname]

    def downselect_columns(self, additional_columns_to_remove):
        self.cols_to_remove = self.cols_to_remove + additional_columns_to_remove
        self.data.drop(self.data[self.cols_to_remove], axis = 1, inplace = True)

    def pivot_data(self):
    #make all the results long format, keep the characteristics wide
    #Note if this was being done from scratch, probably better to separate results (long) from characteristics (wide) and merge on bldg_id in Tableau
    #(Required)
        self.data_long = pd.melt(
            self.data,
            id_vars = self.cols_wide,
            var_name = "Output",
            value_name = "Value"
        )

    def add_additional_long_fields(self, addl_long_fields_df):
        #TODO

    def categorize_outputs(self):
        #use mappings to get the output categorizations
        #(Optional) but encouraged, needed for some fuel type labelings and similar outputs
        out_cats = self.col_plan.drop(self.col_plan[["col_type", "plan"]], axis = 1, inplace = False)
        self.data_long = self.data_long.merge(out_cats, left_on = 'Output', right_on = "column", how = 'left')

    def wide_fields_also_long(self, wide_cols_also_long, wide_cols_also_long_names):
        merge_data_cols = ["bldg_id"] + wide_cols_also_long
        self.data_long = self.data_long.merge(self.data[merge_data_cols], on = "bldg_id", how = "left")
        for colname, newcolname in zip(wide_cols_also_long, wide_cols_also_long_names):
            self.data_long.rename(columns = {colname:newcolname}, inplace = True)

    def add_weighted_values_column(self):
        self.data_long['Weighted Value'] = self.data_long['Value']*self.data_long['weight']