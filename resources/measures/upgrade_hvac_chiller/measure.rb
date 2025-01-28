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
      runner.registerInfo('### pump (used in chiller systems) specs before upgrade')
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
    

    # pump_variable_speed_control_type(pump)

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
    # report final condition
    # ------------------------------------------------
    runner.registerFinalCondition("found #{counts_chillers_acc}/#{counts_chillers_wcc} air-cooled/water-cooled chillers with total capacity of #{capacity_total_w_acc.round(0)}/#{capacity_total_w_wcc.round(0)} W and capacity-weighted average COP of #{cop_weighted_average_acc.round(2)}/#{cop_weighted_average_wcc.round(2)}.")

    return true
  end
end

# register the measure to be used by the application
UpgradeHvacChiller.new.registerWithApplication
