# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'openstudio-standards'

# start the measure
class UpgradeHvacChiller < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'upgrade_hvac_chiller'
  end

  # human readable description
  def description
    return 'tbd'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'tbd'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # print out details?
    debug_verbose = OpenStudio::Measure::OSArgument.makeBoolArgument('debug_verbose', true)
    debug_verbose.setDisplayName('Print out detailed debugging logs if this parameter is true')
    debug_verbose.setDefaultValue(false)
    args << debug_verbose

    return args
  end

  # check if certain hvac type is applicable for chiller upgrade
  def applicable_hvac_type(hvac_system_type)
    # applicable hvac types for chiller upgrade
    list_of_applicable_hvac_types = [
      'DOAS with fan coil air-cooled chiller with baseboard electric',
      'DOAS with fan coil air-cooled chiller with boiler',
      'DOAS with fan coil air-cooled chiller with district hot water',
      'DOAS with fan coil chiller with baseboard electric',
      'VAV air-cooled chiller with PFP boxes',
      'VAV air-cooled chiller with district hot water reheat',
      'VAV air-cooled chiller with gas boiler reheat',
      'DOAS with fan coil chiller with baseboard electric',
      'DOAS with fan coil chiller with boiler',
      'DOAS with fan coil chiller with district hot water',
      'DOAS with fan coil chiller with baseboard electric',
      'VAV chiller with PFP boxes',
      'VAV chiller with district hot water reheat',
      'VAV chiller with gas boiler reheat'
    ]

    # return result
    return true if list_of_applicable_hvac_types.include?(hvac_system_type)
  end

  # get chiller specifications
  def chiller_specifications(chillers)
    # initialize variables
    cop_weighted_sum_acc = 0
    capacity_total_w_acc = 0
    counts_chillers_acc = 0
    cop_weighted_sum_wcc = 0
    capacity_total_w_wcc = 0
    counts_chillers_wcc = 0

    # loop through chillers and get specifications
    chillers.each do |chiller|
      condenser_type = chiller.condenserType

      case condenser_type
      when 'AirCooled'
        capacity_w = 0
        if chiller.referenceCapacity.is_initialized
          capacity_w = chiller.referenceCapacity.get
        elsif chiller.autosizedReferenceCapacity.is_initialized
          capacity_w = chiller.autosizedReferenceCapacity.get
        else
          capacity_w = 0.0
        end
        cop = chiller.referenceCOP
        capacity_total_w_acc += capacity_w
        cop_weighted_sum_acc += cop * capacity_w
        counts_chillers_acc += 1
      when 'WaterCooled'
        capacity_w = 0
        if chiller.referenceCapacity.is_initialized
          capacity_w = chiller.referenceCapacity.get
        elsif chiller.autosizedReferenceCapacity.is_initialized
          capacity_w = chiller.autosizedReferenceCapacity.get
        else
          capacity_w = 0.0
        end
        cop = chiller.referenceCOP
        capacity_total_w_wcc += capacity_w
        cop_weighted_sum_wcc += cop * capacity_w
        counts_chillers_wcc += 1
      end
    end
    cop_weighted_average_acc = capacity_total_w_acc > 0.0 ? cop_weighted_sum_acc / capacity_total_w_acc : 0.0
    cop_weighted_average_wcc = capacity_total_w_wcc > 0.0 ? cop_weighted_sum_wcc / capacity_total_w_wcc : 0.0
    return counts_chillers_acc, capacity_total_w_acc, cop_weighted_average_acc, counts_chillers_wcc, capacity_total_w_wcc, cop_weighted_average_wcc
  end

  # get pump specifications
  def pump_specifications(applicable_pumps, pumps, std)

    # initialize variables
    pump_motor_eff_weighted_sum = 0
    pump_motor_bhp_weighted_sum = 0
    pump_rated_flow_total = 0

    # get pump specs
    pumps.each do |pump|

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

      # calc weighted sums
      pump_rated_flow_total += rated_flow_m_3_per_s
      pump_motor_eff_weighted_sum += pump_motor_eff * rated_flow_m_3_per_s
      pump_motor_bhp_weighted_sum += pump_motor_bhp * rated_flow_m_3_per_s
    end

    # calc weghted averages
    pump_motor_eff_weighted_average = pump_rated_flow_total > 0.0 ? pump_motor_eff_weighted_sum / pump_rated_flow_total : 0.0
    pump_motor_bhp_weighted_average = pump_rated_flow_total > 0.0 ? pump_motor_bhp_weighted_sum / pump_rated_flow_total : 0.0
    
    return applicable_pumps, pump_rated_flow_total, pump_motor_eff_weighted_average, pump_motor_bhp_weighted_average
  end

  # Determine and set type of part load control type for heating and chilled
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
      runner.registerError("could not find rated pump power consumption, cannot determine w per gpm correctly.")
      return false
    end

    # Get nominal nameplate HP
    pump_nominal_hp = pump_rated_power_w * pump.motorEfficiency / 745.7

    # Assign peformance curves
    control_type = pump_variable_speed_get_control_type(runner, model, pump, plant_loop_type, pump_nominal_hp, debug_verbose)

    if debug_verbose
      runner.registerInfo("### control_type = #{control_type}")
    end

    # Set pump part load performance curve coefficients
    pump_variable_speed_set_control_type(runner, pump, control_type, debug_verbose) if control_type

    return true
  end

  # Determine type of pump part load control type
  # modified version from https://github.com/NREL/openstudio-standards/blob/412de97737369c3ee642237a83c8e5a6b1ab14be/lib/openstudio-standards/prototypes/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.PumpVariableSpeed.rb#L11-L142
  def pump_variable_speed_get_control_type(runner, model, pump, plant_loop_type, pump_nominal_hp, debug_verbose)
    # Sizing factor to take into account that pumps
    # are typically sized to handle a ~10% pressure
    # increase and ~10% flow increase.
    design_sizing_factor = 1.25

    # Get climate zone
    #climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)
    climate_zone = pump.plantLoop.get.model.getClimateZones.getClimateZone(0)
    climate_zone = "#{climate_zone.value}"

    # Get nameplate hp threshold:
    # The thresholds below represent the nameplate
    # hp one level lower than the threshold in the
    # code. Motor size from table in section 10 are
    # used as reference.
    case plant_loop_type
      when 'Heating'
        case climate_zone
          when 'ASHRAE 169-2006-7A',
               'ASHRAE 169-2006-7B',
               'ASHRAE 169-2006-8A',
               'ASHRAE 169-2006-8B',
               'ASHRAE 169-2013-7A',
               'ASHRAE 169-2013-7B',
               'ASHRAE 169-2013-8A',
               'ASHRAE 169-2013-8B'
            threshold = 3
          when 'ASHRAE 169-2006-3C',
               'ASHRAE 169-2006-5A',
               'ASHRAE 169-2006-5C',
               'ASHRAE 169-2006-6A',
               'ASHRAE 169-2006-6B',
               'ASHRAE 169-2013-3C',
               'ASHRAE 169-2013-5A',
               'ASHRAE 169-2013-5C',
               'ASHRAE 169-2013-6A',
               'ASHRAE 169-2013-6B'
            threshold = 5
          when 'ASHRAE 169-2006-4A',
               'ASHRAE 169-2006-4C',
               'ASHRAE 169-2006-5B',
               'ASHRAE 169-2013-4A',
               'ASHRAE 169-2013-4C',
               'ASHRAE 169-2013-5B'
            threshold = 7.5
          when 'ASHRAE 169-2006-4B',
               'ASHRAE 169-2013-4B'
            threshold = 10
          when 'ASHRAE 169-2006-2A',
               'ASHRAE 169-2006-2B',
               'ASHRAE 169-2006-3A',
               'ASHRAE 169-2006-3B',
               'ASHRAE 169-2013-2A',
               'ASHRAE 169-2013-2B',
               'ASHRAE 169-2013-3A',
               'ASHRAE 169-2013-3B'
            threshold = 20
          when 'ASHRAE 169-2006-1B',
               'ASHRAE 169-2013-1B'
            threshold = 75
          when 'ASHRAE 169-2006-0A',
               'ASHRAE 169-2006-0B',
               'ASHRAE 169-2006-1A',
               'ASHRAE 169-2013-0A',
               'ASHRAE 169-2013-0B',
               'ASHRAE 169-2013-1A'
            threshold = 150
          else
            runner.registerError("Pump flow control requirement missing for heating water pumps in climate zone: #{climate_zone}.")
        end
      when 'Cooling'
        case climate_zone
          when 'ASHRAE 169-2006-0A',
               'ASHRAE 169-2006-0B',
               'ASHRAE 169-2006-1A',
               'ASHRAE 169-2006-1B',
               'ASHRAE 169-2006-2B',
               'ASHRAE 169-2013-0A',
               'ASHRAE 169-2013-0B',
               'ASHRAE 169-2013-1A',
               'ASHRAE 169-2013-1B',
               'ASHRAE 169-2013-2B'
            threshold = 1.5
          when 'ASHRAE 169-2006-2A',
               'ASHRAE 169-2006-3B',
               'ASHRAE 169-2013-2A',
               'ASHRAE 169-2013-3B'
            threshold = 2
          when 'ASHRAE 169-2006-3A',
               'ASHRAE 169-2006-3C',
               'ASHRAE 169-2006-4A',
               'ASHRAE 169-2006-4B',
               'ASHRAE 169-2013-3A',
               'ASHRAE 169-2013-3C',
               'ASHRAE 169-2013-4A',
               'ASHRAE 169-2013-4B'
            threshold = 3
          when 'ASHRAE 169-2006-4C',
               'ASHRAE 169-2006-5A',
               'ASHRAE 169-2006-5B',
               'ASHRAE 169-2006-5C',
               'ASHRAE 169-2006-6A',
               'ASHRAE 169-2006-6B',
               'ASHRAE 169-2013-4C',
               'ASHRAE 169-2013-5A',
               'ASHRAE 169-2013-5B',
               'ASHRAE 169-2013-5C',
               'ASHRAE 169-2013-6A',
               'ASHRAE 169-2013-6B'
            threshold = 5
          when 'ASHRAE 169-2006-7A',
               'ASHRAE 169-2006-7B',
               'ASHRAE 169-2006-8A',
               'ASHRAE 169-2006-8B',
               'ASHRAE 169-2013-7A',
               'ASHRAE 169-2013-7B',
               'ASHRAE 169-2013-8A',
               'ASHRAE 169-2013-8B'
            threshold = 10
          else
            runner.registerError("Pump flow control requirement missing for chilled water pumps in climate zone: #{climate_zone}.")
        end
      else
        runner.registerError("No pump flow requirement for #{plant_loop_type} plant loops.")
        return false
    end

    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo("### os standards variable speed implementation")
      runner.registerInfo("### plant_loop_type = #{plant_loop_type}")
      runner.registerInfo("### climate_zone = #{climate_zone}")
      runner.registerInfo("### pump_nominal_hp = #{pump_nominal_hp}")
      runner.registerInfo("### design_sizing_factor = #{design_sizing_factor}")
      runner.registerInfo("### threshold = #{threshold}")
    end

    return 'VSD DP Reset' if pump_nominal_hp * design_sizing_factor > threshold

    # else
    return 'Riding Curve'
  end

  # Set the pump curve coefficients based on the specified control type.
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

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments) # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # read input arguments
    debug_verbose = runner.getBoolArgumentValue('debug_verbose', user_arguments)

    # build standard
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # ------------------------------------------------
    # get chiller specifications before upgrade
    # ------------------------------------------------
    applicable_chillers = model.getChillerElectricEIRs
    counts_chillers_acc, capacity_total_w_acc, cop_weighted_average_acc, counts_chillers_wcc, capacity_total_w_wcc, cop_weighted_average_wcc = chiller_specifications(applicable_chillers)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### chiller specs before upgrade')
      runner.registerInfo("### counts_chillers_acc = #{counts_chillers_acc}")
      runner.registerInfo("### capacity_total_w_acc= #{capacity_total_w_acc}")
      runner.registerInfo("### cop_weighted_average_acc = #{cop_weighted_average_acc}")
      runner.registerInfo("### counts_chillers_wcc = #{counts_chillers_wcc}")
      runner.registerInfo("### capacity_total_w_wcc = #{capacity_total_w_wcc}")
      runner.registerInfo("### cop_weighted_average_wcc = #{cop_weighted_average_wcc}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get pump specifications before upgrade
    # ------------------------------------------------
    applicable_pumps = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    applicable_pumps, pump_rated_flow_total_c, pump_motor_eff_weighted_average_c, pump_motor_bhp_weighted_average_c = pump_specifications(applicable_pumps, pumps_const_spd, std)
    applicable_pumps, pump_rated_flow_total_v, pump_motor_eff_weighted_average_v, pump_motor_bhp_weighted_average_v = pump_specifications(applicable_pumps, pumps_var_spd, std)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### pump (used for chillers) specs before upgrade')
      runner.registerInfo("### pump_rated_flow_total_c = #{pump_rated_flow_total_c.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_c = #{pump_motor_eff_weighted_average_c.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_c = #{pump_motor_bhp_weighted_average_c.round(6)}")
      runner.registerInfo("### pump_rated_flow_total_v = #{pump_rated_flow_total_v.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_v = #{pump_motor_eff_weighted_average_v.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_v = #{pump_motor_bhp_weighted_average_v.round(6)}")
      runner.registerInfo("### total count of applicable pumps = #{applicable_pumps.size}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # applicability
    # ------------------------------------------------
    if (counts_chillers_acc.size == 0) & (counts_chillers_wcc.size == 0)
      runner.registerAsNotApplicable('no chillers are found in the model.')
      return false
    end

    # ------------------------------------------------
    # report initial condition
    # ------------------------------------------------
    runner.registerInitialCondition("found #{counts_chillers_acc}/#{counts_chillers_wcc} air-cooled/water-cooled chillers with total capacity of #{capacity_total_w_acc.round(0)}/#{capacity_total_w_wcc.round(0)} W and capacity-weighted average COP of #{cop_weighted_average_acc.round(2)}/#{cop_weighted_average_wcc.round(2)}.")

    # ------------------------------------------------
    # replace chiller
    # ------------------------------------------------

    # ------------------------------------------------
    # replace pump
    # ------------------------------------------------
    applicable_pumps.each do |pump|
      pump_variable_speed_control_type(runner, model, pump, debug_verbose)
    end

    # ------------------------------------------------
    # get chiller specifications after upgrade
    # ------------------------------------------------
    upgraded_chillers = model.getChillerElectricEIRs
    counts_chillers_acc, capacity_total_w_acc, cop_weighted_average_acc, counts_chillers_wcc, capacity_total_w_wcc, cop_weighted_average_wcc = chiller_specifications(upgraded_chillers)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### chiller specs after upgrade')
      runner.registerInfo("### counts_chillers_acc = #{counts_chillers_acc}")
      runner.registerInfo("### capacity_total_w_acc= #{capacity_total_w_acc}")
      runner.registerInfo("### cop_weighted_average_acc = #{cop_weighted_average_acc}")
      runner.registerInfo("### counts_chillers_wcc = #{counts_chillers_wcc}")
      runner.registerInfo("### capacity_total_w_wcc = #{capacity_total_w_wcc}")
      runner.registerInfo("### cop_weighted_average_wcc = #{cop_weighted_average_wcc}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get pump specifications after upgrade
    # ------------------------------------------------
    dummy = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    _, pump_rated_flow_total_c, pump_motor_eff_weighted_average_c, pump_motor_bhp_weighted_average_c = pump_specifications(dummy, pumps_const_spd, std)
    _, pump_rated_flow_total_v, pump_motor_eff_weighted_average_v, pump_motor_bhp_weighted_average_v = pump_specifications(dummy, pumps_var_spd, std)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### pump (used for chillers) specs after upgrade')
      runner.registerInfo("### pump_rated_flow_total_c = #{pump_rated_flow_total_c.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_c = #{pump_motor_eff_weighted_average_c.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_c = #{pump_motor_bhp_weighted_average_c.round(6)}")
      runner.registerInfo("### pump_rated_flow_total_v = #{pump_rated_flow_total_v.round(6)}")
      runner.registerInfo("### pump_motor_eff_weighted_average_v = #{pump_motor_eff_weighted_average_v.round(2)}")
      runner.registerInfo("### pump_motor_bhp_weighted_average_v = #{pump_motor_bhp_weighted_average_v.round(6)}")
      runner.registerInfo("### total count of applicable pumps = #{applicable_pumps.size}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # report final condition
    # ------------------------------------------------
    runner.registerFinalCondition("found #{counts_chillers_acc}/#{counts_chillers_wcc} air-cooled/water-cooled chillers with total capacity of #{capacity_total_w_acc.round(0)}/#{capacity_total_w_wcc.round(0)} W and capacity-weighted average COP of #{cop_weighted_average_acc.round(2)}/#{cop_weighted_average_wcc.round(2)}.")

    return true
  end
end

# register the measure to be used by the application
UpgradeHvacChiller.new.registerWithApplication
