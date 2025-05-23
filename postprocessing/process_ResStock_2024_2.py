###This code is meant to process small to moderate amounts of ResStock data from the 2024.2 data release, for any purpose but especially for use in generating standard figures for TA
# First Author: Elaina Present. Started Q2 FY25.
# Additional Contributors:
# Latest edits: 2025-03-31

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
        ##eventually this will be replaced with using data directly from OEDI
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
    ##this premade csv includes the list of columns to include in the final output, and which of them should be pivoted, and other related information
    ##eventually we will rewrite this to be consistent throughout green team - get the data through a config file and check non available data
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
        self.data = self.data.reindex(columns = cols_in_plan, fill_value = np.nan)
        #create lists of columns for use in pivoting and trimming data
        self.cols_to_remove = self.col_plan.loc[self.col_plan['plan']=='remove', 'column'].tolist()
        self.cols_wide = self.col_plan.loc[self.col_plan['plan']=='keep', 'column'].tolist()
        self.cols_to_pivot = self.col_plan.loc[self.col_plan['plan']=='pivot', 'column'].tolist()

    def add_local_bills(self, rate_inputs_df):
        #define constants
        months_per_year = 12
        #recalculate the utility bills. 
        #(Optional) but (Required) for any utility bill graphics or processing
        for index, row in rate_inputs_df.iterrows():
            #if all ng consumption is removed, add ng fixed cost to bill savings. So two criteria must be met: there must be natural gas savings and the current natural gas consumption must be 0
            if row['column']== "out.bills_local.natural_gas.total.usd.savings":
                self.data[row['column']] = row['fixed monthly cost']*months_per_year*(
                    np.logical_and(
                        (abs(self.data["out.natural_gas.total.energy_consumption.kwh.savings"])>0),
                        (self.data["out.natural_gas.total.energy_consumption.kwh"]==0))) + (
                            row['variable cost per kwh']*(
                                self.data[row['col list for scaling']].sum(axis = 1))) 
            # for each row of rate inputs, create a column in the data, which will be NaN if the scaling row doesn't exist (e.g savings rows in baseline) and 0 if the relevant consumption rows don't exist
            else:
                self.data[row['column']] = row['fixed monthly cost']*months_per_year*((self.data[row['col list for scaling']].sum(axis = 1))!=0) + row['variable cost per kwh']*(self.data[row['col list for scaling']].sum(axis = 1))
            if row['plan'] == 'pivot':
                self.cols_to_pivot = self.cols_to_pivot + [row['column']]
            elif row['plan'] == 'keep':
                self.cols_wide = self.cols_wide + [row['column']]
            else:
                self.cols_to_remove = self.cols_to_remove + [row['column']]
        #recalculate energy affordability (fairly hard-coded here, assumes variable neames)
        self.data["Energy Affordability Ratio"] = self.data["out.bills_local.all_fuels.total.usd"]/self.data["in.representative_income"]
        #add new cols to col plan (so they will be pivoted or not)
        plan_for_new_cols_df = rate_inputs_df.drop(['fixed monthly cost', 'variable cost per kwh', 'col list for scaling'], axis = 1)
        ear_col_plan = pd.DataFrame({'column': ['Energy Affordability Ratio'], 
                                                'col_type': ['unique'], 
                                                'plan': ['keep'], 
                                                'Result Type': ['Energy Affordability'],
                                                'Fuel': ['Energy'], 
                                                'End Use': ['NA'], 
                                                'End Use Category':['NA']})
        self.col_plan = pd.concat([self.col_plan, plan_for_new_cols_df, ear_col_plan], axis = 0, ignore_index=True)
        self.cols_wide = self.cols_wide + ['Energy Affordability Ratio']

    def add_first_costs(self, first_costs_inputs_df, npv_discount_rate, npv_analysis_period, one_year_bill_savings_col):
        #Add first costs, SPP, and NPV to the dataset
        #(Optional), (Required) for any first cost or NPV results
        #define NREL-provided constants
        avg_door_size = 20 #ResStock 2024.2 has 20ft2 total door area for any unit with exterior doors, which is approximately one door
        avg_window_size = 15 #15 ft2 seems like a decent proxy for average window size based on standard window sizes
        kbtuh_to_tons = (1000/12000)
        pool_heater_tons = 1 #proxy for all pool heaters, based loosely on looking at availability at Home Depot website
        spa_heater_tons = 1 #proxy for all spa heaters
        attic_R_per_inch = 3 #ICF data mentions unfaced fiberglass blanket insulation for floors/ceilings in MP16. The R-30 is 9.5" and the R-19 is 6.5" which works out to roughly R-3 per inch
        attic_R_per_foot = attic_R_per_inch/12
        #define ICF-provided constants
        door_perimeter = 20 #Assumed perimeter of exterior door
        window_perimeter = 18 #Assumed perimeter of exterior window based on average size of window
        refrigerant_lbs = 20 #Expected average pounds of refrigerant to be removed from HVAC system including line set
        labor_min = 3 #Minimum labor for interior and exterior disconnect of existing ducted ASHP HVAC system, Minimum labor for new pool heater installation, Minimum labor for new spa heater installation
        #set up empty lists
        up_costs = []
        ssns = []
        #iterate through the ResStock data
        for index, row in self.data.iterrows():
            cost = 0
            ssn = 'NA'
            upgrade = row["upgrade"]
            #no cost for baseline models
            if upgrade == 0:
                up_costs.append(cost)
                ssns.append(ssn)
            #no cost for models where the upgrade wasn't applicable
            elif (row['applicability']!=True):
                up_costs.append(cost)
                ssns.append(ssn)
            #if it's an upgrade and applicable, calculate the cost
            else:
                ##extract necessary data from this row of model results                
                climate_zone = int(row["in.ashrae_iecc_climate_zone_2004"][0]) #just the number, not the letter
                hp_size_kbtuh = row["out.params.size_heating_system_primary_k_btu_h"]
                hp_size_tons = hp_size_kbtuh * kbtuh_to_tons
                attic_floor_area_sf = row["out.params.floor_area_attic_ft_2"]
                num_exterior_doors = row["out.params.door_area_ft_2"]/avg_door_size #this will be exactly 1 in ResStock 2024.2
                num_windows = row["out.params.window_area_ft_2"]/avg_window_size
                wh_gal = row["out.params.size_water_heater_gal"]
                location = row[first_costs_inputs_df["Location Field Match"]].iloc[0]#currently assuming the location field (state, county, PUMA, etc. is the same for the entire cost inputs file)
                if row["in.insulation_ceiling"] == "None":
                    existing_attic_insulation_R = 0
                elif row["in.insulation_ceiling"] is None:
                    existing_attic_insulation_R = 0
                elif row["in.insulation_ceiling"] == "Uninsulated":
                    existing_attic_insulation_R = 0
                else:
                    existing_attic_insulation_R = int(row["in.insulation_ceiling"][2:])
                #per email received from ICF 2025-02-10, "existing_system_ducted" is "a flag to confirm that the home's existing system is not an ASHP" which is what is coded below
                #despite that the label just asks whether the existing home is ducted which is a different calculation
                #this may need editing in the future
                if "ashp" in str(row["in.hvac_heating_efficiency"]).lower():
                    existing_system_ducted = True
                else:
                    existing_system_ducted = False
                ##get the cost data's appropriate Measure Package code and Sum Spec Name for this row of model results
                (mp, ssn) = self.get_mp_and_ssn(row) 
                ##find the correct cost inputs based on location, measure package, and sum spec name
                cost_inputs_this_row = first_costs_inputs_df[np.logical_and(
                    np.logical_and(first_costs_inputs_df['Measure Package']==mp,
                    first_costs_inputs_df['Sum Spec Name']==ssn),
                    first_costs_inputs_df['Location Value Match'] == location)]
                #this should always result in a dataframe with one row. If not, throw an error.
                if len(cost_inputs_this_row) != 1:
                    print("Error! Matching cost data rows found: ", len(cost_inputs_this_row), ", should be 1")
                ##extract the first (only) value for each multiplier and coefficient in the ICF cost data
                hp_cost_per_ton = cost_inputs_this_row["HP Cost (Cost Per Ton)"].iloc[0]
                hpwh_cost_per_gal = cost_inputs_this_row["HPHW Cost Per Gallon"].iloc[0] #note the ICF col name uses HPHW not HPWH
                pool_heater_cost_per_ton = cost_inputs_this_row["Pool Heater Cost Per Ton"].iloc[0]
                spa_heater_cost_per_ton = cost_inputs_this_row["Spa Heater Cost Per Ton"].iloc[0]
                calc1_coeff = cost_inputs_this_row["Calc1_Coeff - Removal Cost of Insulation"].iloc[0]
                calc2_coeff = cost_inputs_this_row["Calc2_Coeff - Removal & Install of Caulking"].iloc[0]
                calc3_coeff = cost_inputs_this_row["Calc3_Coeff - R30 Attic Insulation Installation"].iloc[0]
                calc4_coeff = cost_inputs_this_row["Calc4_Coeff - R19 Attic Insulation Installation"].iloc[0]
                calc5_coeff = cost_inputs_this_row["Calc5_Coeff - Demo AC"].iloc[0]
                calc6_coeff = cost_inputs_this_row["Calc6_Coeff - Remove Refrigerant"].iloc[0]
                calc7_coeff = cost_inputs_this_row["Calc7_Coeff - Demo AC Labor"].iloc[0]
                calc8_coeff = cost_inputs_this_row["Calc8_Coeff - Dryer R&R"].iloc[0]
                calc9_coeff = cost_inputs_this_row["Calc9_Coeff - Range R&R"].iloc[0]
                calc10_coeff = cost_inputs_this_row["Calc10_Coeff - Pool Install of Electric"].iloc[0]
                calc11_coeff = cost_inputs_this_row["Calc11_Coeff - Pool R&R Labor"].iloc[0]
                calc12_coeff = cost_inputs_this_row["Calc12_Coeff - Spa Install of Electric"].iloc[0]
                calc13_coeff = cost_inputs_this_row["Calc13_Coeff - Spa R&R Labor"].iloc[0]
                fixed_costs_demo = cost_inputs_this_row["Offset / Fixed Costs Demo"].iloc[0]
                fixed_costs_install = cost_inputs_this_row["Offset / Fixed Costs Install"].iloc[0]
                ##calculate intermediate values needed in cost calculation
                #note there are a lot of constants hard-coded in here! Double check they are correct for each location
                #calc1 "CF Removal of Attic Insulation"
                ##ICF used a constant 6" of attic insulation (calc1 = attic_floor_area_sf/2), 
                ##we are instead a calculation based on ResStock data.
                calc1 = (existing_attic_insulation_R * attic_R_per_foot) * attic_floor_area_sf
                #calc2 "LF of Caulking"
                calc2 = num_exterior_doors * door_perimeter + num_windows * window_perimeter
                #calcs 3-4 combine to get appropriate levels of insulation for each climate zone (R-30, R-49, or R-60)
                #calc3 "SF of R30 Attic Insulation"
                if climate_zone <4:
                    calc3 = attic_floor_area_sf
                else:
                    calc3 = 2*attic_floor_area_sf
                #calc4 "SF of R19 Attic Insulation"
                if np.logical_and(climate_zone>1, climate_zone<4):
                    calc4 = attic_floor_area_sf
                else:
                    calc4 = 0
                #calc5 "Demo AC"
                if existing_system_ducted == True:
                    calc5 = 1
                else:
                    calc5 = 0
                #calc6 "Remove refrigerant"
                if calc5 ==1:
                    calc6 = refrigerant_lbs
                else:
                    calc6 = 0
                #calc7 "Demo AC labor"
                if calc5 == 1:
                    calc7 = labor_min
                else:
                    calc7 = 0
                #calc8 "Dryer R&R": dealt with directly below based on whether new dryer installed
                #calc9 "Range R&R": dealt with directly below based on whether new cooking range installed
                #calc10 "Pool Install of Electric"
                if pool_heater_tons > 0:
                    calc10 = 1
                else:
                    calc10 = 0
                #calc11 "Pool R&R Labor"
                if pool_heater_tons > 0:
                    calc11 = labor_min
                else:
                    calc11 = 0
                #calc12 "Spa Install of Electric"
                if spa_heater_tons > 0:
                    calc12 = 1
                else:
                    calc12 = 0
                #calc13 "Spa R&R Labor"
                if spa_heater_tons > 0:
                    calc13 = labor_min
                else:
                    calc13 = 0                
                #calculate the cost, additively
                #add the fixed_costs
                cost = cost + fixed_costs_demo + fixed_costs_install
                #add any heat pump costs
                #note: have not checked if this works for GHPs
                #note: this does not round up the HP size to the next "real" size, uses the exact size as output by ResStock
                if "pump" in str(row['upgrade.hvac_cooling_efficiency']).lower():
                    cost = cost + (hp_cost_per_ton * hp_size_tons) + (
                        calc5 * calc5_coeff #only for some upgrades but coeffs will be 0 when calcs 5-7 these aren't applicable
                        + calc6 * calc6_coeff
                        + calc7 * calc7_coeff
                    )
                #add any HPWH costs
                if "pump" in str(row['upgrade.water_heater_efficiency']).lower():
                    cost = cost + (hpwh_cost_per_gal * wh_gal)
                #add any pool heater costs
                if "electricity" in str(row['upgrade.misc_pool_heater']).lower():
                    cost = cost + (pool_heater_cost_per_ton * pool_heater_tons) + (
                        calc10 * calc10_coeff
                        + calc11 * calc11_coeff
                    )
                #add any spa heater costs
                if "electricity" in str(row['upgrade.misc_hot_tub_spa']).lower():
                    cost = cost + (spa_heater_cost_per_ton * spa_heater_tons) + (
                        calc12 * calc12_coeff
                        + calc13 * calc13_coeff
                    )
                #add any attic insulation costs
                if "r-" in str(row['upgrade.insulation_ceiling']).lower():
                    cost = cost + (
                        calc1 * calc1_coeff #removal of attic insulation
                        + calc3 * calc3_coeff #SF of R30 attic insulation
                        + calc4 * calc4_coeff #SF of R19 attic insulation
                    )
                #add any air sealing costs
                if "%" in str(row['upgrade.infiltration_reduction']).lower():
                    cost = cost + (
                        calc2 * calc2_coeff #caulking
                    )
                #add any new dryer costs
                if "electric" in str(row['upgrade.clothes_dryer']).lower():
                    cost = cost + (1*calc8_coeff)
                #add any new cooking equipment costs
                if "electric" in str(row['upgrade.cooking_range']).lower():
                    cost = cost + (1*calc9_coeff)
                #add this cost to the list of costs
                up_costs.append(float(cost))
                ssns.append(ssn)
        #assign new column of first costs
        self.data['out.first_costs.usd'] = up_costs
        self.data['sum spec name'] = ssns
        #assign new column of simple payback periods
        self.data['out.simple_payback_period'] = self.data['out.first_costs.usd']/self.data[one_year_bill_savings_col]
        #calculate NPV
        npv_list = []
        for id_cost, id_savings in zip(self.data['out.first_costs.usd'], self.data[one_year_bill_savings_col]):
            cost_array = [0]*(npv_analysis_period + 1)
            cost_array[0] = id_cost
            savings_array = [id_savings] * (npv_analysis_period + 1)
            savings_array[0] = 0
            cash_flows = list(np.array(savings_array)-np.array(cost_array))
            npv = 0
            for year in range(0, npv_analysis_period + 1):
                npv += (1/((1+npv_discount_rate)**year)) * cash_flows[year]
            npv_list.append(npv)
        self.data['out.net_present_value'] = npv_list
        #add new cost-related to columns to the list of columns to be kept wide (not pivoted)
        self.cols_wide = self.cols_wide + ['out.first_costs.usd', 'out.simple_payback_period', 'out.net_present_value', 'sum spec name']
        #add new cost-related columns to the column plan
        first_costs_col_plan = pd.DataFrame({'column': ['out.first_costs.usd', 'out.simple_payback_period', 'out.net_present_value', 'sum spec name'], 
                                                'col_type': ['unique', 'unique', 'unique', 'unique'], 
                                                'plan': ['keep', 'keep', 'keep', 'keep'], 
                                                'Result Type': ['First Cost', 'Simple Payback Period', 'Net Present Value', 'Cost Code'],
                                                'Fuel': ['NA', 'NA', 'NA', 'NA'], 
                                                'End Use': ['NA', 'NA', 'NA','NA'], 
                                                'End Use Category':['NA', 'NA', 'NA', 'NA']})
        self.col_plan = pd.concat([self.col_plan, first_costs_col_plan], axis = 0, ignore_index=True)

    def add_additional_wide_fields(self, wide_resstock_merge_fields, wide_newdata_merge_fields, addl_wide_fields_df, addl_wide_fields_col_plan):
        #merge additional wide fields in and add them to the column plan
        #(Optional)
        self.data = pd.merge(left = self.data,
                             right = addl_wide_fields_df,
                             how = 'left',
                             left_on = wide_resstock_merge_fields,
                             right_on = wide_newdata_merge_fields)
        self.col_plan = pd.concat([self.col_plan, addl_wide_fields_col_plan], axis = 0, ignore_index = True)
        addl_wide_cols_to_pivot = addl_wide_fields_col_plan[addl_wide_fields_col_plan["plan"]=="pivot"]['column'].tolist()
        addl_wide_cols_to_keep = addl_wide_fields_col_plan[addl_wide_fields_col_plan["plan"]=="keep"]['column'].tolist()
        addl_wide_cols_to_remove = addl_wide_fields_col_plan[addl_wide_fields_col_plan["plan"]=="remove"]['column'].tolist()
        self.cols_to_pivot = self.cols_to_pivot + addl_wide_cols_to_pivot
        self.cols_wide = self.cols_wide + addl_wide_cols_to_keep
        self.cols_to_remove = self.cols_to_remove + addl_wide_cols_to_remove

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

    def add_additional_long_fields(self, long_resstock_merge_fields, long_newdata_merge_fields, addl_long_fields_df):
        self.data_long = pd.merge(left= self.data_long,
                             right = addl_long_fields_df,
                             how = 'left',
                             left_on = long_resstock_merge_fields,
                             right_on = long_newdata_merge_fields)

    def categorize_outputs(self):
        #use mappings to get the output categorizations
        #(Optional) but encouraged, needed for some fuel type labelings and similar outputs
        out_cats = self.col_plan.drop(self.col_plan[["col_type", "plan"]], axis = 1, inplace = False)
        self.data_long = self.data_long.merge(out_cats, left_on = 'Output', right_on = "column", how = 'left')

    #TODO: Can you explain the reason behind transforming the data many times? 
    def wide_fields_also_long(self, wide_cols_also_long, wide_cols_also_long_names):
        merge_data_cols = ["bldg_id"] + wide_cols_also_long
        self.data_long = self.data_long.merge(self.data[merge_data_cols], on = "bldg_id", how = "left")
        for colname, newcolname in zip(wide_cols_also_long, wide_cols_also_long_names):
            self.data_long.rename(columns = {colname:newcolname}, inplace = True)

    def add_weighted_values_column(self):
        self.data_long['Weighted Value'] = self.data_long['Value']*self.data_long['weight']

###helper functions below here###
    def assess_shared_ducts(self, row):
        #some of the ICF costs are different for units with existing shared ducts. This is EKP's logic to assess which units those are.
        if np.logical_and((row['in.hvac_has_shared_system'] == 'Heating Only'), (row['in.hvac_heating_type'] == 'Ducted Heating')):
            return(True)
        elif np.logical_and((row['in.hvac_has_shared_system'] == 'Heating Only'), (row['in.hvac_heating_type'] == 'Ducted Heat Pump')):
            return(True)
        elif np.logical_and((row['in.hvac_has_shared_system'] == 'Heating and Cooling'), (row['in.hvac_heating_type'] == 'Ducted Heating')):
            return(True)
        elif np.logical_and((row['in.hvac_has_shared_system'] == 'Heating and Cooling'), (row['in.hvac_heating_type'] == 'Ducted Heat Pump')):
            return(True)
        elif np.logical_and((row['in.hvac_has_shared_system'] == 'Heating and Cooling'), (row['in.hvac_cooling_type'] == 'Central AC')):
            return(True)
        elif np.logical_and((row['in.hvac_has_shared_system'] == 'Cooling Only'), (row['in.hvac_cooling_type'] == 'central AC')):
            return(True)
        else:
            return(False)
    
    def get_mp_and_ssn(self, row):
        #TODO: I am wondering how to best comsolidate these below. some info variations but a lot if things are repeated and could be condense
        #returns the measure package code and "sum spec name" for each row of modeled data, to allow for matching with the correct ICF data inputs
        if row["upgrade"] == 1:
            mp = 'MP1'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'eASHP'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'eNDMSHPD'
                else:
                    ssn = 'eNDMSHP'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 2:
            mp = 'MP2'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'hASHP'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'hNDMSHPD'
                else:
                    ssn = 'hNDMSHP'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 3:
            mp = 'MP3'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'uASHP'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'uNDMSHPD'
                else:
                    ssn = 'uNDMSHP'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 4:
            mp = 'MP4'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'eASHP'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                ssn = 'eNDMSHP'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 5:
            mp = 'MP5'
            ssn = 'eGHP'
        elif row["upgrade"] == 6:
            mp = 'MP6'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'eASHPwLTE'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'eNDMSHPDwLTE'
                else:
                    ssn = 'eNDMSHPwLTE'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 7:
            mp = 'MP7'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'hASHPwLTE'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'hNDMSHPDwLTE'
                else:
                    ssn = 'hNDMSHPwLTE'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 8:
            mp = 'MP8'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'uASHPwLTE'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'uNDMSHPDwLTE'
                else:
                    ssn = 'uNDMSHPwLTE'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 9:
            mp = 'MP9'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'eASHPwLTE'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                ssn = 'eNDMSHPwLTE'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 10:
            mp = 'MP10'
            ssn = 'eGHPwLTE'
        elif row["upgrade"] == 11:
            mp = 'MP11'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'eASHPwLTEwFA'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'eNDMSHPDwLTEwFA'
                else:
                    ssn = 'eNDMSHPLTEwFA'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 12:
            mp = 'MP12'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'hASHPwLTEwFA'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'hNDMSHPDwLTEwFA'
                else:
                    ssn = 'hNDMSHPwLTEwFA'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 13:
            mp = 'MP13'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'uASHPwLTEwFA'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                shared_ducts = self.assess_shared_ducts(row)
                if shared_ducts == True:
                    ssn = 'uNDMSHPDwLTEwFA'
                else:
                    ssn = 'uNDMSHPwLTEwFA'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 14:
            mp = 'MP14'
            if row['upgrade.hvac_cooling_efficiency'].lower() == 'ducted heat pump':
                ssn = 'eASHPwLTEwFA'
            elif row['upgrade.hvac_cooling_efficiency'].lower() == 'non-ducted heat pump':
                ssn = 'eNDMSHPwLTEwFA'
            else:
                ssn = 'Error'
        elif row["upgrade"] == 15:
            mp = 'MP15'
            ssn = 'eGHPwLTEwFA'
        elif row["upgrade"] == 16:
            mp = 'MP16'
            ssn = "LTE"
        else:
            mp = 'Error'
            ssn = 'Error'
        return(mp, ssn)