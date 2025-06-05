# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'openstudio-standards'

# start the measure
class UpgradeHvacPump < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return "upgrade_hvac_pump"
  end

  # human readable description
  def description
    return "TBD"
  end

  # human readable description of modeling approach
  def modeler_description
    return "TBD"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # upgrade pumps
    upgrade_pump = OpenStudio::Measure::OSArgument.makeBoolArgument('upgrade_pump', true)
    upgrade_pump.setDisplayName('Update pump specifications based on the latest 90.1 standards?')
    upgrade_pump.setDefaultValue(true)
    args << upgrade_pump

    # print out details?
    debug_verbose = OpenStudio::Measure::OSArgument.makeBoolArgument('debug_verbose', true)
    debug_verbose.setDisplayName('Print out detailed debugging logs if this parameter is true')
    debug_verbose.setDefaultValue(false)
    args << debug_verbose

    return args
  end

  # get pump specifications
  def self.pump_specifications(applicable_pumps, pumps, std)
    # initialize variables
    pump_motor_eff_weighted_sum = 0.0
    pump_motor_bhp_weighted_sum = 0.0
    pump_rated_flow_total = 0.0
    pump_var_part_load_curve_coeff1_weighted_sum = 0.0
    pump_var_part_load_curve_coeff2_weighted_sum = 0.0
    pump_var_part_load_curve_coeff3_weighted_sum = 0.0
    pump_var_part_load_curve_coeff4_weighted_sum = 0.0

    # get pump specs
    pumps.each do |pump|
      # check if this pump is used on chiller systems
      chiller_pump = false
      plant_loop = pump.plantLoop.get
      plant_loop.supplyComponents.each do |sc|
        if sc.to_ChillerElectricEIR.is_initialized
          chiller_pump = true
        end
      end

      next if chiller_pump == false

      # add pump to applicable pump list
      applicable_pumps << pump

      # get rated flow
      rated_flow_m_3_per_s = 0
      if pump.ratedFlowRate.is_initialized
        rated_flow_m_3_per_s = pump.ratedFlowRate.get
      elsif pump.autosizedRatedFlowRate.is_initialized
        rated_flow_m_3_per_s = pump.autosizedRatedFlowRate.get
      else
        rated_flow_m_3_per_s = 0.0
      end

      # pump motor efficiency
      pump_motor_eff = pump.motorEfficiency

      # pump motor BHP
      pump_motor_bhp = std.pump_brake_horsepower(pump)

      # get partload curve coefficients from variable speed pump
      if pump.to_PumpVariableSpeed.is_initialized
        pump_var_part_load_curve_coeff1_weighted_sum += pump.coefficient1ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
        pump_var_part_load_curve_coeff2_weighted_sum += pump.coefficient2ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
        pump_var_part_load_curve_coeff3_weighted_sum += pump.coefficient3ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
        pump_var_part_load_curve_coeff4_weighted_sum += pump.coefficient4ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
      end

      # calc weighted sums
      pump_rated_flow_total += rated_flow_m_3_per_s
      pump_motor_eff_weighted_sum += pump_motor_eff * rated_flow_m_3_per_s
      pump_motor_bhp_weighted_sum += pump_motor_bhp * rated_flow_m_3_per_s
    end

    # calc weghted averages
    pump_motor_eff_weighted_average = pump_rated_flow_total > 0.0 ? pump_motor_eff_weighted_sum / pump_rated_flow_total : 0.0
    pump_motor_bhp_weighted_average = pump_rated_flow_total > 0.0 ? pump_motor_bhp_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff1_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff1_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff2_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff2_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff3_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff3_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff4_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff4_weighted_sum / pump_rated_flow_total : 0.0

    [
      applicable_pumps,
      pump_rated_flow_total,
      pump_motor_eff_weighted_average,
      pump_motor_bhp_weighted_average,
      pump_var_part_load_curve_coeff1_weighted_avg,
      pump_var_part_load_curve_coeff2_weighted_avg,
      pump_var_part_load_curve_coeff3_weighted_avg,
      pump_var_part_load_curve_coeff4_weighted_avg
    ]
  end

  # get control specifications
  def self.control_specifications(model)
    # initialize variables
    total_count_spm_chw = 0.0
    total_count_spm_cw = 0.0
    fraction_chw_oat_reset_enabled_sum = 0.0
    fraction_cw_oat_reset_enabled_sum = 0.0

    # get plant loops
    plant_loops = model.getPlantLoops

    # get pump specs
    plant_loops.each do |plant_loop|
      # get loop type
      sizing_plant = plant_loop.sizingPlant
      loop_type = sizing_plant.loopType

      # get setpoint managers
      spms = plant_loop.supplyOutletNode.setpointManagers

      case loop_type
      when 'Cooling'
        # get control specifications
        spms.each do |spm|
          total_count_spm_chw += 1
          if spm.to_SetpointManagerOutdoorAirReset.is_initialized
            fraction_chw_oat_reset_enabled_sum += 1
          end
        end
      when 'Condenser'
        # get control specifications
        spms.each do |spm|
          total_count_spm_cw += 1
          if spm.to_SetpointManagerFollowOutdoorAirTemperature.is_initialized
            fraction_cw_oat_reset_enabled_sum += 1
          end
        end
      end
    end

    # calculate fractions
    fraction_chw_oat_reset_enabled = total_count_spm_chw > 0.0 ? fraction_chw_oat_reset_enabled_sum / total_count_spm_chw : 0.0
    fraction_cw_oat_reset_enabled = total_count_spm_cw > 0.0 ? fraction_cw_oat_reset_enabled_sum / total_count_spm_cw : 0.0

    return fraction_chw_oat_reset_enabled, fraction_cw_oat_reset_enabled
  end

  # method to search through a hash for an object that meets the name criteria
  def model_find_object(copper_curve_data, curve_name)
    # initialize variable
    curve_found = nil

    # find curve
    copper_curve_data['results'].each do |curve_entry|
      if curve_entry['out_var'] == curve_name
        curve_found = curve_entry
      end
    end

    # return
    curve_found
  end

  # load curve to model from json
  # modified version from OS Standards to read from custom json file
  def model_add_curve(model, curve_name, copper_curve_data)
    # First check model and return curve if it already exists
    existing_curves = []
    existing_curves += model.getCurveLinears
    existing_curves += model.getCurveCubics
    existing_curves += model.getCurveQuadratics
    existing_curves += model.getCurveBicubics
    existing_curves += model.getCurveBiquadratics
    existing_curves += model.getCurveQuadLinears
    existing_curves.sort.each do |curve|
      if curve.name.get.to_s == curve_name
        return curve
      end
    end

    # Find curve data
    data = model_find_object(copper_curve_data, curve_name)
    if data.nil?
      return nil
    end

    # Make the correct type of curve
    case data['type']
    # when 'Linear'
    #   curve = OpenStudio::Model::CurveLinear.new(model)
    #   curve.setName(data['out_var'])
    #   curve.setCoefficient1Constant(data['coeff1'])
    #   curve.setCoefficient2x(data['coeff2'])
    #   curve.setMinimumValueofx(data['x_min']) if data['x_min']
    #   curve.setMaximumValueofx(data['x_max']) if data['x_max']
    #   if data['out_min']
    #     curve.setMinimumCurveOutput(data['out_min'])
    #   end
    #   if data['out_max']
    #     curve.setMaximumCurveOutput(data['out_max'])
    #   end
    #   curve
    # when 'Cubic'
    #   curve = OpenStudio::Model::CurveCubic.new(model)
    #   curve.setName(data['out_var'])
    #   curve.setCoefficient1Constant(data['coeff1'])
    #   curve.setCoefficient2x(data['coeff2'])
    #   curve.setCoefficient3xPOW2(data['coeff3'])
    #   curve.setCoefficient4xPOW3(data['coeff4'])
    #   curve.setMinimumValueofx(data['x_min']) if data['x_min']
    #   curve.setMaximumValueofx(data['x_max']) if data['x_max']
    #   if data['out_min']
    #     curve.setMinimumCurveOutput(data['out_min'])
    #   end
    #   if data['out_max']
    #     curve.setMaximumCurveOutput(data['out_max'])
    #   end
    #   curve
    when 'quad'
      curve = OpenStudio::Model::CurveQuadratic.new(model)
      curve.setName(data['out_var'])
      curve.setCoefficient1Constant(data['coeff1'])
      curve.setCoefficient2x(data['coeff2'])
      curve.setCoefficient3xPOW2(data['coeff3'])
      curve.setMinimumValueofx(data['x_min']) if data['x_min']
      curve.setMaximumValueofx(data['x_max']) if data['x_max']
      if data['out_min']
        curve.setMinimumCurveOutput(data['out_min'])
      end
      if data['out_max']
        curve.setMaximumCurveOutput(data['out_max'])
      end
      curve
    # when 'BiCubic'
    #   curve = OpenStudio::Model::CurveBicubic.new(model)
    #   curve.setName(data['out_var'])
    #   curve.setCoefficient1Constant(data['coeff1'])
    #   curve.setCoefficient2x(data['coeff2'])
    #   curve.setCoefficient3xPOW2(data['coeff3'])
    #   curve.setCoefficient4y(data['coeff4'])
    #   curve.setCoefficient5yPOW2(data['coeff5'])
    #   curve.setCoefficient6xTIMESY(data['coeff6'])
    #   curve.setCoefficient7xPOW3(data['coeff_7'])
    #   curve.setCoefficient8yPOW3(data['coeff_8'])
    #   curve.setCoefficient9xPOW2TIMESY(data['coeff_9'])
    #   curve.setCoefficient10xTIMESYPOW2(data['coeff_10'])
    #   curve.setMinimumValueofx(data['x_min']) if data['x_min']
    #   curve.setMaximumValueofx(data['x_max']) if data['x_max']
    #   curve.setMinimumValueofy(data['y_min']) if data['y_min']
    #   curve.setMaximumValueofy(data['y_max']) if data['y_max']
    #   if data['out_min']
    #     curve.setMinimumCurveOutput(data['out_min'])
    #   end
    #   if data['out_max']
    #     curve.setMaximumCurveOutput(data['out_max'])
    #   end
    #   curve
    when 'bi_quad'
      curve = OpenStudio::Model::CurveBiquadratic.new(model)
      curve.setName(data['out_var'])
      curve.setCoefficient1Constant(data['coeff1'])
      curve.setCoefficient2x(data['coeff2'])
      curve.setCoefficient3xPOW2(data['coeff3'])
      curve.setCoefficient4y(data['coeff4'])
      curve.setCoefficient5yPOW2(data['coeff5'])
      curve.setCoefficient6xTIMESY(data['coeff6'])
      curve.setMinimumValueofx(data['x_min']) if data['x_min']
      curve.setMaximumValueofx(data['x_max']) if data['x_max']
      curve.setMinimumValueofy(data['y_min']) if data['y_min']
      curve.setMaximumValueofy(data['y_max']) if data['y_max']
      if data['out_min']
        curve.setMinimumCurveOutput(data['out_min'])
      end
      if data['out_max']
        curve.setMaximumCurveOutput(data['out_max'])
      end
      curve
      # when 'BiLinear'
      #   curve = OpenStudio::Model::CurveBiquadratic.new(model)
      #   curve.setName(data['out_var'])
      #   curve.setCoefficient1Constant(data['coeff1'])
      #   curve.setCoefficient2x(data['coeff2'])
      #   curve.setCoefficient4y(data['coeff3'])
      #   curve.setMinimumValueofx(data['x_min']) if data['x_min']
      #   curve.setMaximumValueofx(data['x_max']) if data['x_max']
      #   curve.setMinimumValueofy(data['y_min']) if data['y_min']
      #   curve.setMaximumValueofy(data['y_max']) if data['y_max']
      #   if data['out_min']
      #     curve.setMinimumCurveOutput(data['out_min'])
      #   end
      #   if data['out_max']
      #     curve.setMaximumCurveOutput(data['out_max'])
      #   end
      #   curve
      # when 'QuadLinear'
      #   curve = OpenStudio::Model::CurveQuadLinear.new(model)
      #   curve.setName(data['out_var'])
      #   curve.setCoefficient1Constant(data['coeff1'])
      #   curve.setCoefficient2w(data['coeff2'])
      #   curve.setCoefficient3x(data['coeff3'])
      #   curve.setCoefficient4y(data['coeff4'])
      #   curve.setCoefficient5z(data['coeff5'])
      #   curve.setMinimumValueofw(data['minimum_independent_variable_w'])
      #   curve.setMaximumValueofw(data['maximum_independent_variable_w'])
      #   curve.setMinimumValueofx(data['minimum_independent_variable_x'])
      #   curve.setMaximumValueofx(data['maximum_independent_variable_x'])
      #   curve.setMinimumValueofy(data['minimum_independent_variable_y'])
      #   curve.setMaximumValueofy(data['maximum_independent_variable_y'])
      #   curve.setMinimumValueofz(data['minimum_independent_variable_z'])
      #   curve.setMaximumValueofz(data['maximum_independent_variable_z'])
      #   curve.setMinimumCurveOutput(data['out_min'])
      #   curve.setMaximumCurveOutput(data['out_max'])
      #   curve
      # when 'MultiVariableLookupTable'
      #   num_ind_var = data['number_independent_variables'].to_i
      #   table = OpenStudio::Model::TableLookup.new(model)
      #   table.setName(data['out_var'])
      #   table.setNormalizationDivisor(data['normalization_reference'].to_f)
      #   table.setOutputUnitType(data['output_unit_type'])
      #   data_points = data.each.select { |key, _value| key.include? 'data_point' }
      #   data_points = data_points.sort_by { |item| item[1].split(',').map(&:to_f) } # sorting data in ascending order
      #   data_points.each do |_key, value|
      #     var_dep = value.split(',')[num_ind_var].to_f
      #     table.addOutputValue(var_dep)
      #   end
      #   num_ind_var.times do |i|
      #     table_indvar = OpenStudio::Model::TableIndependentVariable.new(model)
      #     table_indvar.setName(data['out_var'] + "_ind_#{i + 1}")
      #     table_indvar.setInterpolationMethod(data['interpolation_method'])
      #     table_indvar.setMinimumValue(data["minimum_independent_variable_#{i + 1}"].to_f)
      #     table_indvar.setMaximumValue(data["maximum_independent_variable_#{i + 1}"].to_f)
      #     table_indvar.setUnitType(data["input_unit_type_x#{i + 1}"].to_s)
      #     var_ind_unique = data_points.map { |_key, value| value.split(',')[i].to_f }.uniq
      #     var_ind_unique.each { |var_ind| table_indvar.addValue(var_ind) }
      #     table.addIndependentVariable(table_indvar)
      #   end
      #   table
    end
  end

  # TODO: revert this back to OS Std methods (if works)
  # Determine and set type of part load control type for heating and chilled
  # note code_sections [90.1-2019_6.5.4.2]
  # modified from https://github.com/NREL/openstudio-standards/blob/412de97737369c3ee642237a83c8e5a6b1ab14be/lib/openstudio-standards/prototypes/common/objects/Prototype.PumpVariableSpeed.rb#L4-L37
  def pump_variable_speed_control_type(runner, model, pump, debug_verbose)
    # Get plant loop
    plant_loop = pump.plantLoop.get

    # Get plant loop type
    plant_loop_type = plant_loop.sizingPlant.loopType
    return false unless plant_loop_type == 'Heating' || plant_loop_type == 'Cooling'

    # Get rated pump power
    if pump.ratedPowerConsumption.is_initialized
      pump_rated_power_w = pump.ratedPowerConsumption.get
    elsif pump.autosizedRatedPowerConsumption.is_initialized
      pump_rated_power_w = pump.autosizedRatedPowerConsumption.get
    else
      runner.registerError('could not find rated pump power consumption, cannot determine w per gpm correctly.')
      return false
    end

    # Get nominal nameplate HP
    pump_nominal_hp = pump_rated_power_w * pump.motorEfficiency / 745.7

    # Assign peformance curves
    control_type = 'VSD DP Reset' # hard-code for EUSS/SDR measure

    if debug_verbose
      runner.registerInfo("### control_type = #{control_type}")
    end

    # Set pump part load performance curve coefficients
    pump_variable_speed_set_control_type(runner, pump, control_type, debug_verbose) if control_type

    return true
  end

  # TODO: revert this back to OS Std methods (if works)
  # Set the pump curve coefficients based on the specified control type.
  # note code_sections [90.1-2019_6.5.4.2]
  # modified from https://github.com/NREL/openstudio-standards/blob/412de97737369c3ee642237a83c8e5a6b1ab14be/lib/openstudio-standards/standards/Standards.PumpVariableSpeed.rb#L6-L53
  def pump_variable_speed_set_control_type(runner, pump_variable_speed, control_type, debug_verbose)
    # Determine the coefficients
    coeff_a = nil
    coeff_b = nil
    coeff_c = nil
    coeff_d = nil
    case control_type
    when 'Constant Flow'
      coeff_a = 0.0
      coeff_b = 1.0
      coeff_c = 0.0
      coeff_d = 0.0
    when 'Riding Curve'
      coeff_a = 0.0
      coeff_b = 3.2485
      coeff_c = -4.7443
      coeff_d = 2.5294
    when 'VSD No Reset'
      coeff_a = 0.0
      coeff_b = 0.5726
      coeff_c = -0.301
      coeff_d = 0.7347
    when 'VSD DP Reset'
      coeff_a = 0.0
      coeff_b = 0.0205
      coeff_c = 0.4101
      coeff_d = 0.5753
    else
      runner.registerError("Pump control type '#{control_type}' not recognized, pump coefficients will not be changed.")
      return false
    end

    if debug_verbose
      runner.registerInfo("### coeff_a = #{coeff_a}")
      runner.registerInfo("### coeff_b = #{coeff_b}")
      runner.registerInfo("### coeff_c = #{coeff_c}")
      runner.registerInfo("### coeff_d = #{coeff_d}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # Set the coefficients
    pump_variable_speed.setCoefficient1ofthePartLoadPerformanceCurve(coeff_a)
    pump_variable_speed.setCoefficient2ofthePartLoadPerformanceCurve(coeff_b)
    pump_variable_speed.setCoefficient3ofthePartLoadPerformanceCurve(coeff_c)
    pump_variable_speed.setCoefficient4ofthePartLoadPerformanceCurve(coeff_d)
    pump_variable_speed.setPumpControlType('Intermittent')

    # Append the control type to the pump name
    # self.setName("#{self.name} #{control_type}")

    return true
  end

  # Applies the condenser water temperatures to the plant loop based on Appendix G.
  #
  # hard-coding this because of https://github.com/NREL/openstudio-standards/issues/1915
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_condenser_water_temperatures(runner, plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType
    return true unless loop_type == 'Condenser'

    # Much of the thought in this section came from @jmarrec

    # Determine the design OATwb from the design days.
    # Per https://unmethours.com/question/16698/which-cooling-design-day-is-most-common-for-sizing-rooftop-units/
    # the WB=>MDB day is used to size cooling towers.
    summer_oat_wbs_f = []
    plant_loop.model.getDesignDays.sort.each do |dd|
      next unless dd.dayType == 'SummerDesignDay'
      next unless dd.name.get.to_s.include?('WB=>MDB')

      if plant_loop.model.version < OpenStudio::VersionString.new('3.3.0')
        if dd.humidityIndicatingType == 'Wetbulb'
          summer_oat_wb_c = dd.humidityIndicatingConditionsAtMaximumDryBulb
          summer_oat_wbs_f << OpenStudio.convert(summer_oat_wb_c, 'C', 'F').get
        else
          runner.registerInfo("For #{dd.name}, humidity is specified as #{dd.humidityIndicatingType}; cannot determine Twb.")
        end
      else
        if dd.humidityConditionType == 'Wetbulb' && dd.wetBulbOrDewPointAtMaximumDryBulb.is_initialized
          summer_oat_wbs_f << OpenStudio.convert(dd.wetBulbOrDewPointAtMaximumDryBulb.get, 'C', 'F').get
        else
          runner.registerInfo("For #{dd.name}, humidity is specified as #{dd.humidityConditionType}; cannot determine Twb.")
        end
      end
    end

    # Use the value from the design days or 78F, the CTI rating condition, if no design day information is available.
    design_oat_wb_f = nil
    if summer_oat_wbs_f.size == 0
      design_oat_wb_f = 78
      runner.registerInfo("For #{plant_loop.name}, no design day OATwb conditions were found.  CTI rating condition of 78F OATwb will be used for sizing cooling towers.")
    else
      # Take worst case condition
      design_oat_wb_f = summer_oat_wbs_f.max
      runner.registerInfo("The maximum design wet bulb temperature from the Summer Design Day WB=>MDB is #{design_oat_wb_f} F")
    end

    # There is an EnergyPlus model limitation that the design_oat_wb_f < 80F for cooling towers
    ep_max_design_oat_wb_f = 80
    if design_oat_wb_f > ep_max_design_oat_wb_f
      runner.registerInfo("For #{plant_loop.name}, reduced design OATwb from #{design_oat_wb_f.round(1)} F to E+ model max input of #{ep_max_design_oat_wb_f} F.")
      design_oat_wb_f = ep_max_design_oat_wb_f
    end

    # Determine the design CW temperature, approach, and range
    design_oat_wb_c = OpenStudio.convert(design_oat_wb_f, 'F', 'C').get
    leaving_cw_t_c, approach_k, range_k = plant_loop_prm_baseline_condenser_water_temperatures(runner, plant_loop, design_oat_wb_c)

    # Convert to IP units
    leaving_cw_t_f = OpenStudio.convert(leaving_cw_t_c, 'C', 'F').get
    approach_r = OpenStudio.convert(approach_k, 'K', 'R').get
    range_r = OpenStudio.convert(range_k, 'K', 'R').get

    # Report out design conditions
    runner.registerInfo("For #{plant_loop.name}, design OATwb = #{design_oat_wb_f.round(1)} F, approach = #{approach_r.round(1)} deltaF, range = #{range_r.round(1)} deltaF, leaving condenser water temperature = #{leaving_cw_t_f.round(1)} F.")

    # Set the CW sizing parameters
    sizing_plant.setDesignLoopExitTemperature(leaving_cw_t_c)
    sizing_plant.setLoopDesignTemperatureDifference(range_k)

    # Set Cooling Tower sizing parameters.
    # Only the variable speed cooling tower in E+ allows you to set the design temperatures.
    #
    # Per the documentation
    # http://bigladdersoftware.com/epx/docs/8-4/input-output-reference/group-condenser-equipment.html#field-design-u-factor-times-area-value
    # for CoolingTowerSingleSpeed and CoolingTowerTwoSpeed
    # E+ uses the following values during sizing:
    # 95F entering water temp
    # 95F OATdb
    # 78F OATwb
    # range = loop design delta-T aka range (specified above)
    plant_loop.supplyComponents.each do |sc|
      if sc.to_CoolingTowerVariableSpeed.is_initialized
        ct = sc.to_CoolingTowerVariableSpeed.get
        # E+ has a minimum limit of 68F (20C) for this field.
        # Check against limit before attempting to set value.
        eplus_design_oat_wb_c_lim = 20
        if design_oat_wb_c < eplus_design_oat_wb_c_lim
          runner.registerInfo("For #{plant_loop.name}, a design OATwb of 68F will be used for sizing the cooling towers because the actual design value is below the limit EnergyPlus accepts for this input.")
          design_oat_wb_c = eplus_design_oat_wb_c_lim
        end
        ct.setDesignInletAirWetBulbTemperature(design_oat_wb_c)
        ct.setDesignApproachTemperature(approach_k)
        ct.setDesignRangeTemperature(range_k)
      end
    end

    # Set the min and max CW temps
    # Typical design of min temp is really around 40F
    # (that's what basin heaters, when used, are sized for usually)
    min_temp_f = 34
    max_temp_f = 200
    min_temp_c = OpenStudio.convert(min_temp_f, 'F', 'C').get
    max_temp_c = OpenStudio.convert(max_temp_f, 'F', 'C').get
    plant_loop.setMinimumLoopTemperature(min_temp_c)
    plant_loop.setMaximumLoopTemperature(max_temp_c)

    # Cooling Tower operational controls
    # G3.1.3.11 - Tower shall be controlled to maintain a 70F LCnWT where weather permits,
    # floating up to leaving water at design conditions.
    float_down_to_f = 70
    float_down_to_c = OpenStudio.convert(float_down_to_f, 'F', 'C').get

    cw_t_stpt_manager = nil
    plant_loop.supplyOutletNode.setpointManagers.each do |spm|
      if spm.to_SetpointManagerFollowOutdoorAirTemperature.is_initialized && spm.name.get.include?('Setpoint Manager Follow OATwb')
        cw_t_stpt_manager = spm.to_SetpointManagerFollowOutdoorAirTemperature.get
      end
    end
    if cw_t_stpt_manager.nil?
      cw_t_stpt_manager = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(plant_loop.model)
      cw_t_stpt_manager.addToNode(plant_loop.supplyOutletNode)
    end
    cw_t_stpt_manager.setName("#{plant_loop.name} Setpoint Manager Follow OATwb with #{approach_r.round(1)}F Approach")
    cw_t_stpt_manager.setReferenceTemperatureType('OutdoorAirWetBulb')
    # At low design OATwb, it is possible to calculate
    # a maximum temperature below the minimum.  In this case,
    # make the maximum and minimum the same.
    if leaving_cw_t_c < float_down_to_c
      runner.registerInfo("For #{plant_loop.name}, the maximum leaving temperature of #{leaving_cw_t_f.round(1)} F is below the minimum of #{float_down_to_f.round(1)} F.  The maximum will be set to the same value as the minimum.")
      leaving_cw_t_c = float_down_to_c
    end
    cw_t_stpt_manager.setMaximumSetpointTemperature(leaving_cw_t_c)
    cw_t_stpt_manager.setMinimumSetpointTemperature(float_down_to_c)
    cw_t_stpt_manager.setOffsetTemperatureDifference(approach_k)
    return true
  end

  # Determine the performance rating method specified
  # design condenser water temperature, approach, and range
  #
  # hard-coding this because of https://github.com/NREL/openstudio-standards/issues/1915
  # @param plant_loop [OpenStudio::Model::PlantLoop] the condenser water loop
  # @param design_oat_wb_c [Double] the design OA wetbulb temperature (C)
  # @return [Array<Double>] [leaving_cw_t_c, approach_k, range_k]
  def plant_loop_prm_baseline_condenser_water_temperatures(runner, plant_loop, design_oat_wb_c)
    design_oat_wb_f = OpenStudio.convert(design_oat_wb_c, 'C', 'F').get

    # G3.1.3.11 - CW supply temp shall be evaluated at 0.4% evaporative design OATwb
    # per the formulat approach_F = 25.72 - (0.24 * OATwb_F)
    # 55F <= OATwb <= 90F
    # Design range = 10F.
    range_r = 10

    # Limit the OATwb
    if design_oat_wb_f < 55
      design_oat_wb_f = 55
      runner.registerInfo("For #{plant_loop.name}, a design OATwb of 55F will be used for sizing the cooling towers because the actual design value is below the limit in G3.1.3.11.")
    elsif design_oat_wb_f > 90
      design_oat_wb_f = 90
      runner.registerInfo("For #{plant_loop.name}, a design OATwb of 90F will be used for sizing the cooling towers because the actual design value is above the limit in G3.1.3.11.")
    end

    # Calculate the approach
    approach_r = 25.72 - (0.24 * design_oat_wb_f)

    # Calculate the leaving CW temp
    leaving_cw_t_f = design_oat_wb_f + approach_r

    # Convert to SI units
    leaving_cw_t_c = OpenStudio.convert(leaving_cw_t_f, 'F', 'C').get
    approach_k = OpenStudio.convert(approach_r, 'R', 'K').get
    range_k = OpenStudio.convert(range_r, 'R', 'K').get

    return [leaving_cw_t_c, approach_k, range_k]
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments) # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # read input arguments
    upgrade_pump = runner.getBoolArgumentValue('upgrade_pump', user_arguments)
    debug_verbose = runner.getBoolArgumentValue('debug_verbose', user_arguments)

    # build standard
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # ------------------------------------------------
    # get pump specifications before upgrade
    # ------------------------------------------------
    applicable_pumps = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    pump_specs_cst_spd_before = UpgradeHvacPump.pump_specifications(applicable_pumps, pumps_const_spd, std)
    applicable_pumps = pump_specs_cst_spd_before[0]
    pump_rated_flow_total_c = pump_specs_cst_spd_before[1]
    pump_motor_eff_weighted_average_c = pump_specs_cst_spd_before[2]
    pump_motor_bhp_weighted_average_c = pump_specs_cst_spd_before[3]
    pump_specs_var_spd_before = UpgradeHvacPump.pump_specifications(applicable_pumps, pumps_var_spd, std)
    applicable_pumps = pump_specs_var_spd_before[0]
    pump_rated_flow_total_v = pump_specs_var_spd_before[1]
    pump_motor_eff_weighted_average_v = pump_specs_var_spd_before[2]
    pump_motor_bhp_weighted_average_v = pump_specs_var_spd_before[3]
    pump_var_part_load_curve_coeff1_weighted_avg = pump_specs_var_spd_before[4]
    pump_var_part_load_curve_coeff2_weighted_avg = pump_specs_var_spd_before[5]
    pump_var_part_load_curve_coeff3_weighted_avg = pump_specs_var_spd_before[6]
    pump_var_part_load_curve_coeff4_weighted_avg = pump_specs_var_spd_before[7]
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### pump (used for chillers) specs before upgrade')
      runner.registerInfo("### pump_rated_flow_total_c = #{pump_rated_flow_total_c.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_c = #{pump_motor_eff_weighted_average_c.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_c = #{pump_motor_bhp_weighted_average_c.round(6)}")
      runner.registerInfo("### pump_rated_flow_total_v = #{pump_rated_flow_total_v.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_v = #{pump_motor_eff_weighted_average_v.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_v = #{pump_motor_bhp_weighted_average_v.round(6)}")
      runner.registerInfo("### pump_var_part_load_curve_coeff1_weighted_avg = #{pump_var_part_load_curve_coeff1_weighted_avg}")
      runner.registerInfo("### pump_var_part_load_curve_coeff2_weighted_avg = #{pump_var_part_load_curve_coeff2_weighted_avg}")
      runner.registerInfo("### pump_var_part_load_curve_coeff3_weighted_avg = #{pump_var_part_load_curve_coeff3_weighted_avg}")
      runner.registerInfo("### pump_var_part_load_curve_coeff4_weighted_avg = #{pump_var_part_load_curve_coeff4_weighted_avg}")
      runner.registerInfo("### total count of applicable pumps = #{applicable_pumps.size}")
      applicable_pumps.each do |applicable_pump|
        runner.registerInfo("### applicable pump name = #{applicable_pump.name}")
      end
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get control specifications before upgrade
    # ------------------------------------------------
    chw_oat_reset_enabled_before = UpgradeHvacPump.control_specifications(model)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### control specs before upgrade')
      runner.registerInfo("### fraction of CHW OAT reset control = #{chw_oat_reset_enabled_before}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # applicability
    # ------------------------------------------------
    # if counts_chillers_acc_b == 0 && counts_chillers_wcc_b == 0
    #   runner.registerAsNotApplicable('no chillers are found in the model.')
    #   return true
    # end

    # ------------------------------------------------
    # report initial condition
    # ------------------------------------------------
    # runner.registerInitialCondition("found #{counts_chillers_acc_b}/#{counts_chillers_wcc_b} air-cooled/water-cooled chillers with total capacity of #{capacity_total_w_acc_b.round(0)}/#{capacity_total_w_wcc_b.round(0)} W and capacity-weighted average COP of #{cop_weighted_average_acc_b.round(2)}/#{cop_weighted_average_wcc_b.round(2)}.")

    # ------------------------------------------------
    # pump upgrades
    # ------------------------------------------------
    if upgrade_pump
      applicable_pumps.each do |pump|
        # update pump efficiencies
        std.pump_apply_standard_minimum_motor_efficiency(pump)

        # update part load performance (for variable speed pumps) to be 'VSD DP Reset'
        if pump.to_PumpVariableSpeed.is_initialized
          pump_variable_speed_control_type(runner, model, pump, debug_verbose)
        end
      end
    end

    # ------------------------------------------------
    # get pump specifications after upgrade
    # ------------------------------------------------
    dummy = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    _, pump_rated_flow_total_c, pump_motor_eff_weighted_average_c, pump_motor_bhp_weighted_average_c, = UpgradeHvacPump.pump_specifications(dummy, pumps_const_spd, std)
    _, pump_rated_flow_total_v, pump_motor_eff_weighted_average_v, pump_motor_bhp_weighted_average_v, pump_var_part_load_curve_coeff1_weighted_avg, pump_var_part_load_curve_coeff2_weighted_avg, pump_var_part_load_curve_coeff3_weighted_avg, pump_var_part_load_curve_coeff4_weighted_avg = UpgradeHvacPump.pump_specifications(dummy, pumps_var_spd, std)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### pump (used for chillers) specs after upgrade')
      runner.registerInfo("### pump_rated_flow_total_c = #{pump_rated_flow_total_c.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_c = #{pump_motor_eff_weighted_average_c.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_c = #{pump_motor_bhp_weighted_average_c.round(6)}")
      runner.registerInfo("### pump_rated_flow_total_v = #{pump_rated_flow_total_v.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_v = #{pump_motor_eff_weighted_average_v.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_v = #{pump_motor_bhp_weighted_average_v.round(6)}")
      runner.registerInfo("### pump_var_part_load_curve_coeff1_weighted_avg = #{pump_var_part_load_curve_coeff1_weighted_avg}")
      runner.registerInfo("### pump_var_part_load_curve_coeff2_weighted_avg = #{pump_var_part_load_curve_coeff2_weighted_avg}")
      runner.registerInfo("### pump_var_part_load_curve_coeff3_weighted_avg = #{pump_var_part_load_curve_coeff3_weighted_avg}")
      runner.registerInfo("### pump_var_part_load_curve_coeff4_weighted_avg = #{pump_var_part_load_curve_coeff4_weighted_avg}")
      runner.registerInfo("### total count of applicable pumps = #{applicable_pumps.size}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get control specifications before upgrade
    # ------------------------------------------------
    chw_oat_reset_enabled_after = UpgradeHvacPump.control_specifications(model)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### control specs after upgrade')
      runner.registerInfo("### fraction of CHW OAT reset control = #{chw_oat_reset_enabled_after}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # report final condition
    # ------------------------------------------------
    msg_acc = 'TBD.'
    msg_final_condition = "#{msg_acc}"
    runner.registerFinalCondition(msg_final_condition)

    return true
  end
end

# register the measure to be used by the application
UpgradeHvacPump.new.registerWithApplication
