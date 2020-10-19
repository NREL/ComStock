# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************
# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# Dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'

# start the measure
class HVACVariableSpeedCoolingTower < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'add_cooling_tower_controls'
  end

  # human readable description
  def description
    return 'This energy efficiency measure (EEM) replaces each existing cooling tower object present in an OpenStudio model with a CoolingTower:VariableSpeed object. While many of the existing cooling tower attributes are persisted, the following tower performance attributes will be changed:  Create and apply a theoretical fan curve where fan power ratio is directly proportional to the air flow rate ratio cubed, set Minimum Air Flow Rate Ratio to 20%, set Evaporation Loss Mode to ?Saturated Exit?, set Drift Loss Percent to 0.05, set Blowdown Calculation mode to ?ConcentrationRatio? and set Blowdown Concentration Ratio to 3.0.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This energy efficiency measure (EEM) replaces all cooling tower objects in a model of the following types: (OS:CoolingTowerPerformanceCoolTools, OS:CoolingTowerPerformanceYorkCalc,  OS:CoolingTowerSingleSpeed, OS:CoolingTowerTwoSpeed, or OS:CoolingTowerVariableSpeed) with a new OS:CoolingTower:VariableSpeed object. If an existing cooling tower is already configured for variable speed, the measure will inform the user. When replacing an existing tower object, the following values from the existing tower configuration will be reused: Design Inlet Air Wet Bulb Temp, Design Approach Temperature, Design Range Temperature, Design Water Flow Rate, Design Air Flow Rate, Design Fan Power, Fraction of Tower Capacity in the Free Convection Regime, Basin Heater Capacity,  Basin Heater Setpoint Temperature, Basin Heater Operating Schedule, Number of Cells,  Cell Control, Cell Minimum and Maximum Water Flow Rate Fractions and Sizing Factor. A performance curve relating fan power to tower airflow rates is used. The curve assumes the fan power ratio is directly proportional to the air flow rate ratio cubed. A Minimum Air Flow Rate Ratio of 20% will be set. To model minimal but realistic water consumption, the Evaporation Loss Mode for new Tower objects will be set to ?Saturated Exit? and Drift Loss Percent will be set to a value of 0.05% of the Design Water Flow.  Blowdown water usage will be based on maintaining a Concentration Ratio of 3.0.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Initialize variables for allowing variable scopes within the method
    cooltools = []
    yorkcalc = []
    single_speed = []
    two_speed = []
    variable_speed = []

    # Create array of all plant loops where plantLoop.SizingPlant.Looptype = "Condensor"
    cooling_tower_plant_loop_array = []
    model.getPlantLoops.each do |plant_loop|
      loop_type = plant_loop.sizingPlant.loopType
      if loop_type == 'Condenser'
        cooling_tower_plant_loop_array << plant_loop
      end
    end

    # write NA message if no condenser plant loops
    if cooling_tower_plant_loop_array.empty?
      runner.registerAsNotApplicable('Model does not contain any plantloops where Loop Type = Condenser. This measure will not alter the model.')
      return false
    end

    # Loop through cooling_tower_plant_loop_array to find cooling tower objects
    cooling_tower_plant_loop_array.each do |pl|
      pl.supplyComponents.each do |sc|
        # get count of OS:CoolingTowerPerformanceCoolTools objects
        if sc.to_CoolingTowerPerformanceCoolTools.is_initialized
          cooltools << sc.to_CoolingTowerPerformanceCoolTools.get
        end

        # get count of OS:CoolingTowerPerformanceYorkCalc objects
        if sc.to_CoolingTowerPerformanceYorkCalc.is_initialized
          yorkcalc << sc.to_CoolingTowerPerformanceYorkCalc.get
        end

        # get count of OS:CoolingTowerSingleSpeed objects
        if sc.to_CoolingTowerSingleSpeed.is_initialized
          single_speed << sc.to_CoolingTowerSingleSpeed.get
        end

        # get count of OS:CoolingTowerTwoSpeed objects
        if sc.to_CoolingTowerTwoSpeed.is_initialized
          two_speed << sc.to_CoolingTowerTwoSpeed.get
        end

        # get count of OS:CoolingTowerTwoSpeed objects
        if sc.to_CoolingTowerVariableSpeed.is_initialized
          variable_speed << sc.to_CoolingTowerVariableSpeed.get
        end
      end
    end

    # count the number of objects in the resulting array
    cooltools_count = cooltools.length
    yorkcalc_count = yorkcalc.length
    single_speed_count = single_speed.length
    two_speed_count = two_speed.length
    variable_speed_count = variable_speed.length

    applicable = single_speed_count + two_speed_count
    non_applicable = variable_speed_count + yorkcalc_count + cooltools_count
    total = applicable + non_applicable

    # report initial condition of model
    runner.registerInitialCondition("The model has #{total} cooling tower objects, out of which #{applicable} will be modified. Number of existing cooling towers which is (are) already configured for variable speed fan operation = #{non_applicable}, and will not be modified.")

    # report NA message if all cooling towers are already configured for variable speed fans
    if applicable == 0
      runner.registerAsNotApplicable('This measure is not applicable. All existing cooling tower objects in the model are all already configured for variable airflow operation.')
      return false
    end

    # Initialize registerValue variables
    flow_rate_gpm = 0
    cooling_load_ton = 0

    # Step 1 - Loop through Applicible Single Speed Tower objects
    single_speed.each do |ss|
      # Retrieve status of object attributes that are optional and not able to be autosized
      if ss.nominalCapacity.is_initialized
        nominal_capacity = ss.nominalCapacity.get
      end

      if ss.freeConvectionCapacity.is_initialized
        free_convection_capacity = ss.freeConvectionCapacity.get
      end

      if ss.basinHeaterOperatingSchedule.is_initialized
        basin_heater_operating_schedule = ss.basinHeaterOperatingSchedule.get
      end

      if ss.evaporationLossMode.is_initialized
        evaporation_loss_mode = ss.evaporationLossMode.get
      end

      if ss.blowdownCalculationMode.is_initialized
        blowdown_calculation_mode = ss.blowdownCalculationMode.get
      end

      if ss.blowdownMakeupWaterUsageSchedule.is_initialized
        blowdown_makeup_water_usage_schedule = ss.blowdownMakeupWaterUsageSchedule.get
      end

      # Retrieving status of fields that are optional but are able to be autosized
      if ss.designWaterFlowRate.is_initialized
        design_water_flow_rate = ss.designWaterFlowRate.get
      end

      if ss.designAirFlowRate.is_initialized
        design_air_flow_rate = ss.designAirFlowRate.get
      end

      if ss.fanPoweratDesignAirFlowRate.is_initialized
        fan_power_at_design_air_flow_rate = ss.fanPoweratDesignAirFlowRate.get
      end

      if ss.uFactorTimesAreaValueatDesignAirFlowRate.is_initialized
        u_factor_times_area_value_at_design_airflow_rate = ss.uFactorTimesAreaValueatDesignAirFlowRate.get
      end

      if ss.airFlowRateinFreeConvectionRegime.is_initialized
        air_flow_rate_in_free_convenction_regime = ss.airFlowRateinFreeConvectionRegime.get
      end

      if ss.uFactorTimesAreaValueatFreeConvectionAirFlowRate.is_initialized
        ufactor_times_area_value_at_free_convection_air_flow_rate = ss.uFactorTimesAreaValueatFreeConvectionAirFlowRate.get
      end

      # Retrieving status of autosizable files
      design_water_flow_rate_autosize_status = ss.isDesignWaterFlowRateAutosized
      design_air_flow_rate_autosize_status = ss.isDesignAirFlowRateAutosized
      fan_power_at_design_flow_rate_autosize_status = ss.isFanPoweratDesignAirFlowRateAutosized
      u_factor_times_area_value_at_design_airflow_rate_autosize_status = ss.isUFactorTimesAreaValueatDesignAirFlowRateAutosized
      air_flow_rate_in_free_convection_regime_autosize_status = ss.isAirFlowRateinFreeConvectionRegimeAutosized
      ufactor_times_area_value_at_free_convection_air_flow_rate_autosize_status = ss.isUFactorTimesAreaValueatFreeConvectionAirFlowRateAutosized

      # Retrieving Attributes that are required (not optional or autosizable)
      ss_name = ss.name
      performance_input_method = ss.performanceInputMethod
      basin_heater_capacity = ss.basinHeaterCapacity
      basin_heater_setpoint_temp = ss.basinHeaterSetpointTemperature
      evaporation_loss_factor = ss.evaporationLossFactor
      drift_loss_percent = ss.driftLossPercent
      blowdown_concentration_ratio = ss.blowdownConcentrationRatio
      capacity_control = ss.capacityControl
      number_of_cells = ss.numberofCells
      cell_control = ss.cellControl
      cell_minimum_water_flow_rate_fraction = ss.cellMinimumWaterFlowRateFraction
      cell_maximum_water_flow_rate_fraction = ss.cellMaximumWaterFlowRateFraction
      sizing_factor = ss.sizingFactor

      # Step 2 - Get inlet node of the current single speed cooling tower object
      inlet_node = ss.inletModelObject.get.to_Node.get

      # Step 3 - Add new variable speed cooling tower object to the same inlet node
      new_vs_cooling_tower = OpenStudio::Model::CoolingTowerVariableSpeed.new(model)
      new_vs_cooling_tower.addToNode(inlet_node)

      # Step 4 - Create a new fan power ratio function of airflow rate ratio curve
      # TODO: check the coefficient values against several VS cooling tower selections using selection software
      fan_pwr_func_airflow_ratio_curve = OpenStudio::Model::CurveCubic.new(model)
      fan_pwr_func_airflow_ratio_curve.setCoefficient1Constant(-0.0093)
      fan_pwr_func_airflow_ratio_curve.setCoefficient2x(0.0512)
      fan_pwr_func_airflow_ratio_curve.setCoefficient3xPOW2(-0.0838)
      fan_pwr_func_airflow_ratio_curve.setCoefficient4xPOW3(1.0419)
      fan_pwr_func_airflow_ratio_curve.setMinimumValueofx(0.15)
      fan_pwr_func_airflow_ratio_curve.setMaximumValueofx(1.0)

      # Step 5 - Configure attributes of new variable speed cooling tower
      new_vs_cooling_tower.setName("#{ss.name} - Replaced Tower with VS Fan")
      new_vs_cooling_tower.setBasinHeaterCapacity(basin_heater_capacity)
      new_vs_cooling_tower.setDesignInletAirWetBulbTemperature(25.56) # See source below
      new_vs_cooling_tower.setDesignRangeTemperature(5.56)	          # See source below
      new_vs_cooling_tower.setDesignApproachTemperature(3.89)		      # See source below

      # Source: Based on CTI Standrard 201 Appendix E Cooling Tower Test Condition #47
      # See http://www.cti.org/downloads/STD201_AppendixE-CT_CC_EC_Feb2015.xlsx
      # Condition Reference #47
      # Wet Bulb = 25.56 C
      # Range C = 5.56
      # Approach = 3.89 C
      # Inlet Water Temperature = 35.00 C
      # Outlet Water Temperature = 29.44 C

      if design_water_flow_rate_autosize_status == true
        new_vs_cooling_tower.autosizeDesignWaterFlowRate
      else
        new_vs_cooling_tower.setDesignWaterFlowRate(design_water_flow_rate)
      end

      if design_air_flow_rate_autosize_status == true
        new_vs_cooling_tower.autosizeDesignAirFlowRate
      else
        new_vs_cooling_tower.setDesignAirFlowRate(design_air_flow_rate)
      end

      if fan_power_at_design_flow_rate_autosize_status == true
        new_vs_cooling_tower.autosizeDesignFanPower
      else
        new_vs_cooling_tower.setDesignFanPower(fan_power_at_design_air_flow_rate)
      end

      new_vs_cooling_tower.setFanPowerRatioFunctionofAirFlowRateRatioCurve(fan_pwr_func_airflow_ratio_curve)

      ss_min_airflow_ratio = 0.20 # TODO: check against selection software
      new_vs_cooling_tower.setMinimumAirFlowRateRatio(ss_min_airflow_ratio)
      ss_fract_twr_cap_free_con = 0.125 # TODO: check against selection software
      new_vs_cooling_tower.setFractionofTowerCapacityinFreeConvectionRegime(ss_fract_twr_cap_free_con)
      new_vs_cooling_tower.setBasinHeaterSetpointTemperature(basin_heater_setpoint_temp)

      if ss.basinHeaterOperatingSchedule.is_initialized
        new_vs_cooling_tower.setBasinHeaterOperatingSchedule(basin_heater_operating_schedule)
      end

      if ss.evaporationLossMode.is_initialized
        new_vs_cooling_tower.setEvaporationLossMode(evaporation_loss_mode)
      end

      new_vs_cooling_tower.setEvaporationLossFactor(evaporation_loss_factor)
      new_vs_cooling_tower.setDriftLossPercent(drift_loss_percent)

      if ss.blowdownCalculationMode.is_initialized
        new_vs_cooling_tower.setBlowdownCalculationMode(blowdown_calculation_mode)
      end

      new_vs_cooling_tower.setBlowdownConcentrationRatio(blowdown_concentration_ratio)

      if ss.blowdownMakeupWaterUsageSchedule.is_initialized
        new_vs_cooling_tower.setBlowdownMakeupWaterUsageSchedule(blowdown_makeup_water_usage_schedule)
      end

      new_vs_cooling_tower.setNumberofCells(number_of_cells)
      new_vs_cooling_tower.setCellControl(cell_control)
      new_vs_cooling_tower.setCellMinimumWaterFlowRateFraction(cell_minimum_water_flow_rate_fraction)
      new_vs_cooling_tower.setCellMaximumWaterFlowRateFraction(cell_maximum_water_flow_rate_fraction)
      new_vs_cooling_tower.setSizingFactor(sizing_factor)

      # Step 6 - Remove the existing single speed cooling tower
      ss.remove

      if design_water_flow_rate_autosize_status == true
      end

      if design_air_flow_rate_autosize_status == true
      end

      if fan_power_at_design_flow_rate_autosize_status == true
      end

      if ss.basinHeaterOperatingSchedule.is_initialized
      end

      if ss.evaporationLossMode.is_initialized
      end

      if ss.blowdownCalculationMode.is_initialized
      end

      if ss.blowdownMakeupWaterUsageSchedule.is_initialized
      end

      # Calculate cooling tower water flow rate and cooling load
      if new_vs_cooling_tower.designWaterFlowRate.is_initialized
        flow_rate_gpm += new_vs_cooling_tower.designWaterFlowRate.get.to_f
        flow_rate_m3_per_s = OpenStudio.convert(flow_rate_gpm, 'gal/min', 'm^3/s').get
        flow_rate_kg_per_s = flow_rate_m3_per_s * 1000
      else
        runner.registerWarning("Cooling tower '#{ts.name}' does not have a design water flow rate and will not be considered in total flow rate calculation.")
      end

      temp_diff = new_vs_cooling_tower.plantLoop.get.sizingPlant.loopDesignTemperatureDifference.to_f
      cooling_load_w = flow_rate_kg_per_s * temp_diff
      cooling_load_ton += OpenStudio.convert(cooling_load_W, 'W', 'ton').get

      runner.registerInfo("Removed CoolingTowerSingleSpeed object = '#{ss.name}'.\n New CoolingTowerVariableSpeed object = '#{new_vs_cooling_tower.name}'\n Basin heater capacity = #{basin_heater_capacity} W \n Design Inlet Air Wetbulb Temp based on CTI testing standards = 25.6C \n Design Range Temp based on CTI testing standards = 5.56°C \n Design Approach Temperature based on CTI testing standards = 3.89°C \n Design water flow rate (m3/sec)  = Autosize#{design_water_flow_rate}, same as the original cooling tower \n Design air flow rate setting (m3/sec) = Autosize#{design_air_flow_rate} \n Design Fan Power setting (W) = Autosize#{fan_power_at_design_air_flow_rate} \n New performance curve to describe the tower fan power vs airflow unloading curve = '#{fan_pwr_func_airflow_ratio_curve.name}' \n Minimum tower airflow ratio, design airflow based on best engineering practice = #{ss_min_airflow_ratio} \n Fraction of tower capacity in free convection regime, based on industry standards = #{ss_fract_twr_cap_free_con} \n Basin heater setpoint temp = #{basin_heater_setpoint_temp} Deg C, #{basin_heater_operating_schedule} \n Evaporation loss mode setting = '#{evaporation_loss_mode}' \n Evaporation loss factor of #{evaporation_loss_factor} \n Drift loss = #{drift_loss_percent}% \n Blowdown calculation mode setting = '#{blowdown_calculation_mode}' \n Blowdown concentration ratio = #{blowdown_concentration_ratio} #{blowdown_makeup_water_usage_schedule} \n Info on Cells: \nSame number of cells of the original tower, #{number_of_cells} cell(s) \n Cell control strategy = '#{cell_control}' \n Cell minimum water flow rate fraction = #{cell_minimum_water_flow_rate_fraction} \n Cell minimum water flow rate fraction = #{cell_maximum_water_flow_rate_fraction} \n Sizing factor of #{sizing_factor}")
    end

    # loop through array of two speed towers
    two_speed.each do |ts|
      # Step 1 - Store existing attribute values for re-use
      # Retrieve status of object attributes that are optional and not able to be autosized

      if ts.highSpeedNominalCapacity.is_initialized
        high_speed_nominal_capacity = ts.highSpeedNominalCapacity.get
      end

      if ts.basinHeaterOperatingSchedule.is_initialized
        basin_heater_operating_schedule = ts.basinHeaterOperatingSchedule.get
      end

      if ts.evaporationLossMode.is_initialized
        evaporation_loss_mode = ts.evaporationLossMode.get
      end

      if ts.blowdownCalculationMode.is_initialized
        blowdown_calculation_mode = ts.blowdownCalculationMode.get
      end

      if ts.blowdownMakeupWaterUsageSchedule.is_initialized
        blowdown_makeup_water_usage_schedule = ts.blowdownMakeupWaterUsageSchedule.get
      end

      # Retrieving status of fields that are optional but are able to be autosized
      if ts.designWaterFlowRate.is_initialized
        design_water_flow_rate = ts.designWaterFlowRate.get
      end

      if ts.highFanSpeedAirFlowRate.is_initialized
        high_fan_speed_air_flow_rate = ts.highFanSpeedAirFlowRate.get
      end

      if ts.highFanSpeedFanPower.is_initialized
        high_fan_speed_power = ts.highFanSpeedFanPower.get
      end

      if ts.highFanSpeedUFactorTimesAreaValue.is_initialized
        high_fan_speed_u_factor_times_area_value = ts.highFanSpeedUFactorTimesAreaValue.get
      end

      if ts.lowFanSpeedAirFlowRate.is_initialized
        low_fan_speed_air_flow_rate = ts.lowFanSpeedAirFlowRate.get
      end

      if ts.lowFanSpeedFanPower.is_initialized
        low_fan_speed_fan_power = ts.lowFanSpeedFanPower.get
      end

      if ts.lowFanSpeedUFactorTimesAreaValue.is_initialized
        low_fan_speed_u_factor_times_area_value = ts.lowFanSpeedUFactorTimesAreaValue.get
      end

      if ts.freeConvectionRegimeAirFlowRate.is_initialized
        free_convection_regime_air_flow_rate = ts.freeConvectionRegimeAirFlowRate.get
      end

      if ts.freeConvectionRegimeUFactorTimesAreaValue.is_initialized
        free_convection_regime_u_factor_time_area_value = ts.freeConvectionRegimeUFactorTimesAreaValue.get
      end

      if ts.lowSpeedNominalCapacity.is_initialized
        low_speed_nominal_capacity = ts.lowSpeedNominalCapacity.get
      end

      if ts.freeConvectionNominalCapacity.is_initialized
        free_convection_nominal_capacity = ts.freeConvectionNominalCapacity.get
      end

      # Retrieving status of autosizable files
      design_water_flow_rate_autosize_status = ts.isDesignWaterFlowRateAutosized
      high_fan_speed_fan_air_flow_rate_autosize_status = ts.isHighFanSpeedAirFlowRateAutosized
      high_fan_speed_fan_power_autosize_status = ts.isHighFanSpeedFanPowerAutosized
      high_fan_speed_u_factor_times_area_value_autosize_status = ts.isHighFanSpeedUFactorTimesAreaValueAutosized
      low_fan_speed_fan_air_flow_rate_autosize_status = ts.isLowFanSpeedAirFlowRateAutosized
      low_fan_speed_fan_fan_power_autosize_status = ts.isLowFanSpeedFanPowerAutosized
      low_fan_speed_u_factor_times_area_value_autosize_status = ts.isLowFanSpeedUFactorTimesAreaValueAutosized
      free_convection_regime_air_flow_rate_autosize_status = ts.isFreeConvectionRegimeAirFlowRateAutosized
      free_convection_regime_u_factor_times_area_value_autosize_status = ts.isFreeConvectionRegimeUFactorTimesAreaValueAutosized
      low_speed_nominal_capacity_autosize_status = ts.isLowSpeedNominalCapacityAutosized
      free_convection_nominal_capacity_autosize_status = ts.isFreeConvectionNominalCapacityAutosized

      # Retrieving Attributes that are required (not optional or autosizable)
      ts_name = ts.name
      low_fan_speed_fan_air_flow_rate_sizing_factor = ts.lowFanSpeedAirFlowRateSizingFactor
      low_fan_speed_fan_power_sizing_factor = ts.lowFanSpeedFanPowerSizingFactor
      low_fan_speed_u_factor_times_area_sizing_factor = ts.lowFanSpeedUFactorTimesAreaSizingFactor
      free_convection_regime_air_flow_rate_sizing_factor = ts.freeConvectionRegimeAirFlowRateSizingFactor
      free_convection_regime_u_factor_times_area_value_sizing_factor = ts.freeConvectionUFactorTimesAreaValueSizingFactor
      performance_input_method = ts.performanceInputMethod
      heat_rejection_capacity_and_nominal_capacity_sizing_ratio = ts.heatRejectionCapacityandNominalCapacitySizingRatio
      low_speed_nominal_capacity_sizing_factor = ts.lowSpeedNominalCapacitySizingFactor
      free_convection_nominal_capacity_sizing_factor = ts.freeConvectionNominalCapacitySizingFactor
      basin_heater_capacity = ts.basinHeaterCapacity
      basin_heater_setpoint_temp = ts.basinHeaterSetpointTemperature
      evaporation_loss_factor = ts.evaporationLossFactor
      drift_loss_percent = ts.driftLossPercent
      blowdown_concentration_ratio = ts.blowdownConcentrationRatio
      number_of_cells = ts.numberofCells
      cell_control = ts.cellControl
      cell_minimum_water_flow_rate_fraction = ts.cellMinimumWaterFlowRateFraction
      cell_maximum_water_flow_rate_fraction = ts.cellMaximumWaterFlowRateFraction
      sizing_factor = ts.sizingFactor

      # Step 2 - Get inlet node of the current single speed cooling tower object
      inlet_node = ts.inletModelObject.get.to_Node.get

      # Step 3 - Add new variable speed cooling tower object to the same inlet node
      new_vs_cooling_tower = OpenStudio::Model::CoolingTowerVariableSpeed.new(model)
      new_vs_cooling_tower.addToNode(inlet_node)

      # Step 4 - Create new fan power ratio function of airflow rate ratio curve
      # TODO: check the coefficient values against several VS cooling tower selections using selection software
      fan_pwr_func_airflow_ratio_curve = OpenStudio::Model::CurveCubic.new(model)
      fan_pwr_func_airflow_ratio_curve.setCoefficient1Constant(-0.0093)
      fan_pwr_func_airflow_ratio_curve.setCoefficient2x(0.0512)
      fan_pwr_func_airflow_ratio_curve.setCoefficient3xPOW2(-0.0838)
      fan_pwr_func_airflow_ratio_curve.setCoefficient4xPOW3(1.0419)
      fan_pwr_func_airflow_ratio_curve.setMinimumValueofx(0.15)
      fan_pwr_func_airflow_ratio_curve.setMaximumValueofx(1.0)

      # Step 5 - Configure attributes of new variable speed cooling tower
      new_vs_cooling_tower.setName("#{ts.name} - Replaced Tower with VS Fan")
      new_vs_cooling_tower.setBasinHeaterCapacity(basin_heater_capacity)
      new_vs_cooling_tower.setDesignInletAirWetBulbTemperature(25.56) # See source below
      new_vs_cooling_tower.setDesignRangeTemperature(5.56)	          # See source below
      new_vs_cooling_tower.setDesignApproachTemperature(3.89)		      # See source below

      # Source: Based on CTI Standrard 201 Appendix E Cooling Tower Test Condition #47
      # See http://www.cti.org/downloads/STD201_AppendixE-CT_CC_EC_Feb2015.xlsx
      # Condition Reference #47
      # Wet Bulb = 25.56 C
      # Range C = 5.56
      # Approach = 3.89 C
      # Inlet Water Temperature = 35.00 C
      # Outlet Water Temperature = 29.44 C

      if design_water_flow_rate_autosize_status == true
        new_vs_cooling_tower.autosizeDesignWaterFlowRate
      else
        new_vs_cooling_tower.setDesignWaterFlowRate(design_water_flow_rate)
      end

      if high_fan_speed_fan_air_flow_rate_autosize_status == true
        new_vs_cooling_tower.autosizeDesignAirFlowRate
      else
        new_vs_cooling_tower.setDesignAirFlowRate(high_fan_speed_air_flow_rate)
      end

      if high_fan_speed_fan_power_autosize_status == true
        new_vs_cooling_tower.autosizeDesignFanPower
      else
        new_vs_cooling_tower.setDesignFanPower(high_fan_speed_power)
      end

      new_vs_cooling_tower.setFanPowerRatioFunctionofAirFlowRateRatioCurve(fan_pwr_func_airflow_ratio_curve)
      ts_min_airflow_ratio = 0.20 # TODO: check against selection software
      new_vs_cooling_tower.setMinimumAirFlowRateRatio(ts_min_airflow_ratio)
      ts_fract_twr_cap_free_con = 0.125 # TODO: check against selection software
      new_vs_cooling_tower.setFractionofTowerCapacityinFreeConvectionRegime(ts_fract_twr_cap_free_con)
      new_vs_cooling_tower.setBasinHeaterSetpointTemperature(basin_heater_setpoint_temp)

      if ts.basinHeaterOperatingSchedule.is_initialized
        new_vs_cooling_tower.setBasinHeaterOperatingSchedule(basin_heater_operating_schedule)
      end

      if ts.evaporationLossMode.is_initialized
        new_vs_cooling_tower.setEvaporationLossMode(evaporation_loss_mode)
      end

      new_vs_cooling_tower.setEvaporationLossFactor(evaporation_loss_factor)
      new_vs_cooling_tower.setDriftLossPercent(drift_loss_percent)

      if ts.blowdownCalculationMode.is_initialized
        new_vs_cooling_tower.setBlowdownCalculationMode(blowdown_calculation_mode)
      end

      new_vs_cooling_tower.setBlowdownConcentrationRatio(blowdown_concentration_ratio)

      if ts.blowdownMakeupWaterUsageSchedule.is_initialized
        new_vs_cooling_tower.setBlowdownMakeupWaterUsageSchedule(blowdown_makeup_water_usage_schedule)
      end

      new_vs_cooling_tower.setNumberofCells(number_of_cells)
      new_vs_cooling_tower.setCellControl(cell_control)
      new_vs_cooling_tower.setCellMinimumWaterFlowRateFraction(cell_minimum_water_flow_rate_fraction)
      new_vs_cooling_tower.setCellMaximumWaterFlowRateFraction(cell_maximum_water_flow_rate_fraction)
      new_vs_cooling_tower.setSizingFactor(sizing_factor)

      # Step 6 - Remove the existing two speed cooling tower
      ts.remove

      # Step 7 - Write info messages
      runner.registerInfo("Removed CoolingTowerTwoSpeed object named #{ts.name}.")
      runner.registerInfo("Adding new CoolingTowerVariableSpeed object named #{new_vs_cooling_tower.name} to replace #{ts.name}.")
      runner.registerInfo("Replacement Tower for #{ts.name} has same basin heater capacity of #{basin_heater_capacity} W.")
      runner.registerInfo("Replacement Tower for #{ts.name} has Design Inlet Air Wetbub Temperature of 25.56°C based on CTI testing standards.")
      runner.registerInfo("Replacement Tower for #{ts.name} has Design Range Temperature of 5.56°C based on CTI testing standards.")
      runner.registerInfo("Replacement Tower for #{ts.name} has Design Approach Temperature of 3.89°C based on CTI testing standards.")

      if design_water_flow_rate_autosize_status == true
        runner.registerInfo("Replacement Tower for #{ts.name} design water flow rate set to Autosize, same as the original cooling tower.")
      else
        runner.registerInfo("Replacement Tower for #{ts.name} design water flow rate set to #{design_water_flow_rate} m3/sec, same as the original cooling tower.")
      end

      if high_fan_speed_fan_air_flow_rate_autosize_status == true
        runner.registerInfo("Setting Design AirFlow Rate for #{ts.name} equal to 'Autosize', same as High Fan Speed Air Flow rate of original tower.")
      else
        runner.registerInfo("Setting the Design Airflow Rate for #{ts.name} equal to #{high_fan_speed_air_flow_rate} m3/sec, same as High Fan Speed Air Flow Rate of original tower.")
      end

      if high_fan_speed_fan_power_autosize_status == true
        runner.registerInfo("Replacement Tower for #{ts.name} re-uses the Autosized value for High Fan Speed Fan Power for setting the Design Fan Power to Autosize.")
      else
        runner.registerInfo("Replacement Tower for #{ts.name} re-uses the High Fan Speed Fan Power setting of #{high_fan_speed_power}W for the Design Fan Power setting.")
      end

      runner.registerInfo("Replacement Tower for #{ts.name} uses a new performance curve named #{fan_pwr_func_airflow_ratio_curve.name} to describe the tower fan power vs airflow unloading curve.")
      runner.registerInfo("Replacement Tower for #{ts.name} sets the minimum tower airflow ratio to #{ts_min_airflow_ratio} of design airflow based on best engineering practice.")
      runner.registerInfo("Replacement Tower for #{ts.name} sets the fraction of tower capacity in free convection regime = #{ts_fract_twr_cap_free_con} based on induicstry standards.")
      runner.registerInfo("Replacement Tower for #{ts.name} reuses the basin heater setpoint temperature of #{basin_heater_setpoint_temp} Deg C.")

      if ts.basinHeaterOperatingSchedule.is_initialized
        runner.registerInfo("Replacement Tower for #{ts.name} reuses the Basin Heater Operating Schedule of #{basin_heater_operating_schedule}.")
      end

      if ts.evaporationLossMode.is_initialized
        runner.registerInfo("Replacement Tower for #{ts.name} reuses the evaporation loass mode setting of #{evaporation_loss_mode}.")
      end

      runner.registerInfo("XXXX - Replacement Tower for #{ts.name} reuses the evaporation loss factor of #{evaporation_loss_factor}.")
      runner.registerInfo("Replacement Tower for #{ts.name} reuses the drift loss % of #{drift_loss_percent}.")

      if ts.blowdownCalculationMode.is_initialized
        runner.registerInfo("Replacement Tower for #{ts.name} reuses the blowdown calculation mode setting of #{blowdown_calculation_mode}.")
      end

      runner.registerInfo("Replacement Tower for #{ts.name} reuses the blowdown concentration ration of #{blowdown_concentration_ratio}.")

      if ts.blowdownMakeupWaterUsageSchedule.is_initialized
        runner.registerInfo("Replacement Tower for #{ts.name} reuses the blowdown makeup water usage schedule named #{blowdown_makeup_water_usage_schedule}.")
      end

      runner.registerInfo("Replacement Tower for #{ts.name} reuses the same number of cells as the original tower, #{number_of_cells} cells.")

      runner.registerInfo("Replacement Tower for #{ts.name} reuses the cell control strategy of #{cell_control}.")
      runner.registerInfo("Replacement Tower for #{ts.name} reuses the cell minimum water flow rate fraction of #{cell_minimum_water_flow_rate_fraction}.")
      runner.registerInfo("Replacement Tower for #{ts.name} reuses the cell minimum water flow rate fraction of #{cell_maximum_water_flow_rate_fraction}.")
      runner.registerInfo("Replacement Tower for #{ts.name} reuses the sizing factor of #{sizing_factor}.")

      # Calculate cooling tower water flow rate and cooling load
      if new_vs_cooling_tower.designWaterFlowRate.is_initialized
        flow_rate_gpm += new_vs_cooling_tower.designWaterFlowRate.get.to_f
        flow_rate_m3_per_s = OpenStudio.convert(flow_rate_gpm, 'gal/min', 'm^3/s').get
        flow_rate_kg_per_s = flow_rate_m3_per_s * 1000
      else
        runner.registerWarning("Cooling tower '#{ts.name}' does not have a design water flow rate and will not be considered in cooling load calculation.")
        flow_rate_kg_per_s = 0
      end

      temp_diff = new_vs_cooling_tower.plantLoop.get.sizingPlant.loopDesignTemperatureDifference.to_f
      cooling_load_w = flow_rate_kg_per_s * temp_diff
      cooling_load_ton += OpenStudio.convert(cooling_load_w, 'W', 'ton').get
    end

    # Write Final Condiitons Message
    runner.registerFinalCondition("Measure completed by replacing #{single_speed.count} 'single speed' & #{two_speed.count} 'two speed' cooling towers with CoolingTowerVariableSpeed objects.")
    runner.registerValue('hvac_var_speed_cooling_tower_cooling_load_in_tons', cooling_load_ton, 'tons')
    runner.registerValue('hvac_var_speed_cooling_tower_flow_rate_in_gpm', flow_rate_gpm, 'gpm')

    return true
  end
end

# register the measure to be used by the application
HVACVariableSpeedCoolingTower.new.registerWithApplication
