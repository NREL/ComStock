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
    return "This measure evaluates the replacement of pumps with variable speed high-efficiency pumps in existing water-based systems for space heating and cooling, excluding domestic water heating. High-efficiency pumps considered in the measure refer to top-tier products currently available in the U.S. market as of July 2025. The nominal efficiencies of pump motors range from 91% to 96%, depending on the motor’s horsepower, compared to ComStock pumps, which typically range from 70% to 96%."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Constant-speed pumps in existing buildings are replaced with variable-speed pumps featuring advanced part-load performance enabled by modern control strategies. Older variable-speed pumps are upgraded to newer models with advanced part-load efficiency through modern control technologies, such as dynamic static pressure reset. Applicable to pumps used for space heating and cooling: chiller system, boiler system, and district heating and cooling system."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # add outdoor air temperature reset for chilled water supply temperature
    chw_oat_reset = OpenStudio::Measure::OSArgument.makeBoolArgument('chw_oat_reset', true)
    chw_oat_reset.setDisplayName('Add outdoor air temperature reset for chilled water supply temperature?')
    chw_oat_reset.setDefaultValue(true)
    args << chw_oat_reset

    # add outdoor air temperature reset for condenser water temperature
    cw_oat_reset = OpenStudio::Measure::OSArgument.makeBoolArgument('cw_oat_reset', true)
    cw_oat_reset.setDisplayName('Add outdoor air temperature reset for condenser water temperature?')
    cw_oat_reset.setDefaultValue(true)
    args << cw_oat_reset

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
      chw_cw_hw_pump = false
      plant_loop = pump.plantLoop.get
      plant_loop.supplyComponents.each do |sc|
        if (sc.to_ChillerElectricEIR.is_initialized ||
          sc.to_BoilerHotWater.is_initialized ||
          sc.to_CoolingTowerSingleSpeed.is_initialized ||
          sc.to_CoolingTowerTwoSpeed.is_initialized ||
          sc.to_CoolingTowerVariableSpeed.is_initialized)
          chw_cw_hw_pump = true
        end
      end

      next if chw_cw_hw_pump == false

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

  # get motor efficiency from nominal power
  def self.estimate_motor_efficiency_pcnt(nominal_power_w)
    nominal_power_kw = nominal_power_w / 1000.0

    # Regression parameters from Python popt_fixed
    a = 1.64644705
    b = 92.25875553
    c = 50.22494607
    d = 0.00061996

    # Fixed breakpoint
    x0 = 5.0

    # Efficiency bounds (%)
    eff_min = 90.53
    eff_max = 95.95

    if nominal_power_kw <= 0
      raise ArgumentError, "Nominal power must be greater than 0"
    end

    if nominal_power_kw < x0
      motor_efficiency_pcnt = a * Math.log(nominal_power_kw) + b
    else
      # Compute e to ensure continuity at x0
      left_val = a * Math.log(x0) + b
      right_val = c * (1 - Math.exp(-d * x0))
      e = left_val - right_val

      motor_efficiency_pcnt = c * (1 - Math.exp(-d * nominal_power_kw)) + e
    end

    # Clip output to [90.53%, 95.95%]
    [[motor_efficiency_pcnt, eff_min].max, eff_max].min

  end

  # get part-load fraction of full load power curve
  def self.curve_fraction_of_full_load_power(model)
    # Define coefficients for the cubic curve
    coeff_a = 0.0
    coeff_b = 0.0
    coeff_c = 0.1055
    coeff_d = 0.8945
    # Define a cubic curve with example coefficients
    curve = OpenStudio::Model::CurveCubic.new(model)
    curve.setName("Fraction of Full Load Power Curve")
    curve.setCoefficient1Constant(coeff_a)     # y-intercept
    curve.setCoefficient2x(coeff_b)             # linear term
    curve.setCoefficient3xPOW2(coeff_c)       # quadratic term
    curve.setCoefficient4xPOW3(coeff_d)        # cubic term
    curve.setMinimumValueofx(0.0)
    curve.setMaximumValueofx(1.0)
    curve.setMinimumCurveOutput(0.0)
    curve.setMaximumCurveOutput(1.0)
    return curve, coeff_a, coeff_b, coeff_c, coeff_d
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
    chw_oat_reset = runner.getBoolArgumentValue('chw_oat_reset', user_arguments)
    cw_oat_reset = runner.getBoolArgumentValue('cw_oat_reset', user_arguments)
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
    count_cst_spd_pump = applicable_pumps.size
    msg_cst_spd_pump_i = "#{count_cst_spd_pump} constant speed pumps found with #{pump_rated_flow_total_c.round(6)} m3/s total flow, #{pump_motor_eff_weighted_average_c.round(3)*100}% average motor efficiency, and #{pump_motor_bhp_weighted_average_c.round(6)} BHP."
    pump_specs_var_spd_before = UpgradeHvacPump.pump_specifications(applicable_pumps, pumps_var_spd, std)
    applicable_pumps = pump_specs_var_spd_before[0]
    pump_rated_flow_total_v = pump_specs_var_spd_before[1]
    pump_motor_eff_weighted_average_v = pump_specs_var_spd_before[2]
    pump_motor_bhp_weighted_average_v = pump_specs_var_spd_before[3]
    pump_var_part_load_curve_coeff1_weighted_avg = pump_specs_var_spd_before[4]
    pump_var_part_load_curve_coeff2_weighted_avg = pump_specs_var_spd_before[5]
    pump_var_part_load_curve_coeff3_weighted_avg = pump_specs_var_spd_before[6]
    pump_var_part_load_curve_coeff4_weighted_avg = pump_specs_var_spd_before[7]
    count_var_spd_pump = applicable_pumps.size - count_cst_spd_pump
    msg_var_spd_pump_i = "#{count_var_spd_pump} variable speed pumps found with #{pump_rated_flow_total_v.round(6)} m3/s total flow, #{pump_motor_eff_weighted_average_v.round(3)*100}% average motor efficiency, and #{pump_motor_bhp_weighted_average_v.round(6)} BHP."
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
    # applicability
    # ------------------------------------------------
    if applicable_pumps.size == 0
      runner.registerAsNotApplicable('no eligible pumps are found in the model.')
      return true
    end

    # ------------------------------------------------
    # report initial condition
    # ------------------------------------------------
    msg_initial = msg_cst_spd_pump_i + " " + msg_var_spd_pump_i
    runner.registerInitialCondition(msg_initial)

    # ------------------------------------------------
    # pump upgrades
    # ------------------------------------------------
    applicable_pumps.each do |old_pump|

      if debug_verbose
        runner.registerInfo("### replacing pump: #{old_pump.name}")
      end

      # Clone key parameters from the old pump
      pump_flow_rate = old_pump.ratedFlowRate.get
      pump_head = old_pump.ratedPumpHead
      pump_name = old_pump.name.get + "_upgrade"
      pump_power = old_pump.ratedPowerConsumption.get

      if debug_verbose
        runner.registerInfo("--- existing spec: pump_flow_rate = #{pump_flow_rate} m3/s")
        runner.registerInfo("--- existing spec: pump_head = #{pump_head} Pa")
        runner.registerInfo("--- existing spec: pump_power = #{pump_power} W")
      end

      # Remove the old pump from the loop
      supply_inlet_node = old_pump.inletModelObject.get.to_Node.get
      supply_outlet_node = old_pump.outletModelObject.get.to_Node.get
      old_pump.remove

      if debug_verbose
        runner.registerInfo("--- existing spec: supply_inlet_node = #{supply_inlet_node.name}")
        runner.registerInfo("--- existing spec: supply_outlet_node = #{supply_outlet_node.name}")
      end

      # Create the new pump (choose type based on old pump)
      new_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
      new_pump.setName(pump_name)
      new_pump.setRatedFlowRate(pump_flow_rate)
      new_pump.setRatedPumpHead(pump_head)

      # Apply motor efficiency
      

      # Apply part-load performance for variable speed pump
      _, coeff_a, coeff_b, coeff_c, coeff_d = UpgradeHvacPump.curve_fraction_of_full_load_power(model)
      new_pump.setCoefficient1ofthePartLoadPerformanceCurve(coeff_a)
      new_pump.setCoefficient2ofthePartLoadPerformanceCurve(coeff_b)
      new_pump.setCoefficient3ofthePartLoadPerformanceCurve(coeff_c)
      new_pump.setCoefficient4ofthePartLoadPerformanceCurve(coeff_d)

      # Add new pump back to original node
      new_pump.addToNode(supply_inlet_node)

      if debug_verbose
        runner.registerInfo("--- replaced pump '#{old_pump.name}' with new pump '#{new_pump.name}'.")
      end
    end

    # ------------------------------------------------
    # control upgrades
    # ------------------------------------------------
    if chw_oat_reset || cw_oat_reset
      plant_loops = model.getPlantLoops
      plant_loops.each do |plant_loop|
        std.plant_loop_enable_supply_water_temperature_reset(plant_loop) if chw_oat_reset
        plant_loop_apply_prm_baseline_condenser_water_temperatures(runner, plant_loop) if cw_oat_reset
      end
    end

    # ------------------------------------------------
    # get pump specifications after upgrade
    # ------------------------------------------------
    dummy = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    pump_specs_cst_spd_after = UpgradeHvacPump.pump_specifications(dummy, pumps_const_spd, std)
    applicable_pumps = pump_specs_cst_spd_after[0]
    pump_rated_flow_total_c = pump_specs_cst_spd_after[1]
    pump_motor_eff_weighted_average_c = pump_specs_cst_spd_after[2]
    pump_motor_bhp_weighted_average_c = pump_specs_cst_spd_after[3]
    count_cst_spd_pump = applicable_pumps.size
    msg_cst_spd_pump_f = "#{count_cst_spd_pump} constant speed pumps updated with #{pump_rated_flow_total_c.round(6)} m3/s total flow, #{pump_motor_eff_weighted_average_c.round(3)*100}% average motor efficiency, and #{pump_motor_bhp_weighted_average_c.round(6)} BHP."
    pump_specs_var_spd_after = UpgradeHvacPump.pump_specifications(dummy, pumps_var_spd, std)
    applicable_pumps = pump_specs_var_spd_after[0]
    pump_rated_flow_total_v = pump_specs_var_spd_after[1]
    pump_motor_eff_weighted_average_v = pump_specs_var_spd_after[2]
    pump_motor_bhp_weighted_average_v = pump_specs_var_spd_after[3]
    pump_var_part_load_curve_coeff1_weighted_avg = pump_specs_var_spd_after[4]
    pump_var_part_load_curve_coeff2_weighted_avg = pump_specs_var_spd_after[5]
    pump_var_part_load_curve_coeff3_weighted_avg = pump_specs_var_spd_after[6]
    pump_var_part_load_curve_coeff4_weighted_avg = pump_specs_var_spd_after[7]
    count_var_spd_pump = applicable_pumps.size - count_cst_spd_pump
    msg_var_spd_pump_f = "#{count_var_spd_pump} variable speed pumps updated with #{pump_rated_flow_total_v.round(6)} m3/s total flow, #{pump_motor_eff_weighted_average_v.round(3)*100}% average motor efficiency, and #{pump_motor_bhp_weighted_average_v.round(6)} BHP."

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
    # report final condition
    # ------------------------------------------------
    msg_final_condition = msg_cst_spd_pump_f + " " + msg_var_spd_pump_f
    runner.registerFinalCondition(msg_final_condition)

    return true
  end
end

# register the measure to be used by the application
UpgradeHvacPump.new.registerWithApplication
