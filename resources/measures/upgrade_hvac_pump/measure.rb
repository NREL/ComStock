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
