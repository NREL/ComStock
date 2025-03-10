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
  def self.chiller_specifications(chillers)
    # initialize variables
    cop_weighted_sum_acc = 0
    capacity_total_w_acc = 0
    counts_chillers_acc = 0
    cop_weighted_sum_wcc = 0
    capacity_total_w_wcc = 0
    counts_chillers_wcc = 0
    curve_summary = {}

    # loop through chillers and get specifications
    chillers.each do |chiller|
      condenser_type = chiller.condenserType

      # get performance specs
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

      # get curves
      cap_f_t = chiller.coolingCapacityFunctionOfTemperature
      eir_f_t = chiller.electricInputToCoolingOutputRatioFunctionOfTemperature
      eir_f_plr = chiller.electricInputToCoolingOutputRatioFunctionOfPLR
      curve_summary[chiller.name.to_s] = {}
      curve_summary[chiller.name.to_s]['cap_f_t'] = cap_f_t.name.to_s
      curve_summary[chiller.name.to_s]['eir_f_t'] = eir_f_t.name.to_s
      curve_summary[chiller.name.to_s]['eir_f_plr'] = eir_f_plr.name.to_s
    end
    cop_weighted_average_acc = capacity_total_w_acc > 0.0 ? cop_weighted_sum_acc / capacity_total_w_acc : 0.0
    cop_weighted_average_wcc = capacity_total_w_wcc > 0.0 ? cop_weighted_sum_wcc / capacity_total_w_wcc : 0.0

    [
      counts_chillers_acc,
      capacity_total_w_acc,
      cop_weighted_average_acc,
      counts_chillers_wcc,
      capacity_total_w_wcc,
      cop_weighted_average_wcc,
      curve_summary
    ]
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

      # get partload curve coefficients from variable speed pump
      if pump.to_PumpVariableSpeed.is_initialized
        pump_var_part_load_curve_coeff1_weighted_sum += pump.coefficient1ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
        pump_var_part_load_curve_coeff2_weighted_sum += pump.coefficient2ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
        pump_var_part_load_curve_coeff3_weighted_sum += pump.coefficient3ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
        pump_var_part_load_curve_coeff4_weighted_sum += pump.coefficient4ofthePartLoadPerformanceCurve * rated_flow_m_3_per_s
      end

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
    pump_var_part_load_curve_coeff1_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff1_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff2_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff2_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff3_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff3_weighted_sum / pump_rated_flow_total : 0.0
    pump_var_part_load_curve_coeff4_weighted_avg = pump_rated_flow_total > 0.0 ? pump_var_part_load_curve_coeff4_weighted_sum / pump_rated_flow_total : 0.0

    return applicable_pumps, pump_rated_flow_total, pump_motor_eff_weighted_average, pump_motor_bhp_weighted_average, pump_var_part_load_curve_coeff1_weighted_avg, pump_var_part_load_curve_coeff2_weighted_avg, pump_var_part_load_curve_coeff3_weighted_avg, pump_var_part_load_curve_coeff4_weighted_avg
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
  def model_add_curve(model, curve_name, copper_curve_data, std)
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
    control_type = pump_variable_speed_get_control_type(runner, model, pump, plant_loop_type, pump_nominal_hp, debug_verbose)

    if debug_verbose
      runner.registerInfo("### control_type = #{control_type}")
    end

    # Set pump part load performance curve coefficients
    pump_variable_speed_set_control_type(runner, pump, control_type, debug_verbose) if control_type

    return true
  end

  # TODO: revert this back to OS Std methods (if works)
  # Determine type of pump part load control type
  # note code_sections [90.1-2019_6.5.4.2]
  # modified version from https://github.com/NREL/openstudio-standards/blob/412de97737369c3ee642237a83c8e5a6b1ab14be/lib/openstudio-standards/prototypes/ashrae_90_1/ashrae_90_1_2019/ashrae_90_1_2019.PumpVariableSpeed.rb#L11-L142
  def pump_variable_speed_get_control_type(runner, model, pump, plant_loop_type, pump_nominal_hp, debug_verbose)
    # Sizing factor to take into account that pumps
    # are typically sized to handle a ~10% pressure
    # increase and ~10% flow increase.
    design_sizing_factor = 1.25

    # Get climate zone
    climate_zone = pump.plantLoop.get.model.getClimateZones.getClimateZone(0)
    climate_zone = climate_zone.value.to_s # this is the modified part compared to the original line

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
      runner.registerInfo('### os standards variable speed implementation')
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
    # get chiller specifications before upgrade
    # ------------------------------------------------
    applicable_chillers = model.getChillerElectricEIRs
    results_before = UpgradeHvacChiller.chiller_specifications(applicable_chillers)
    counts_chillers_acc_b = results_before[0]
    capacity_total_w_acc_b = results_before[1]
    cop_weighted_average_acc_b = results_before[2]
    counts_chillers_wcc_b = results_before[3]
    capacity_total_w_wcc_b = results_before[4]
    cop_weighted_average_wcc_b = results_before[5]
    curve_summary_b = results_before[6]
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### chiller specs before upgrade')
      runner.registerInfo("### counts_chillers_acc = #{counts_chillers_acc_b}")
      runner.registerInfo("### capacity_total_w_acc= #{capacity_total_w_acc_b}")
      runner.registerInfo("### cop_weighted_average_acc = #{cop_weighted_average_acc_b}")
      runner.registerInfo("### counts_chillers_wcc = #{counts_chillers_wcc_b}")
      runner.registerInfo("### capacity_total_w_wcc = #{capacity_total_w_wcc_b}")
      runner.registerInfo("### cop_weighted_average_wcc = #{cop_weighted_average_wcc_b}")
      runner.registerInfo("### curve_summary = #{curve_summary_b}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get pump specifications before upgrade
    # ------------------------------------------------
    applicable_pumps = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    applicable_pumps, pump_rated_flow_total_c, pump_motor_eff_weighted_average_c, pump_motor_bhp_weighted_average_c, = UpgradeHvacChiller.pump_specifications(applicable_pumps, pumps_const_spd, std)
    applicable_pumps, pump_rated_flow_total_v, pump_motor_eff_weighted_average_v, pump_motor_bhp_weighted_average_v, pump_var_part_load_curve_coeff1_weighted_avg, pump_var_part_load_curve_coeff2_weighted_avg, pump_var_part_load_curve_coeff3_weighted_avg, pump_var_part_load_curve_coeff4_weighted_avg = UpgradeHvacChiller.pump_specifications(applicable_pumps, pumps_var_spd, std)
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
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get control specifications before upgrade
    # ------------------------------------------------
    chw_oat_reset_enabled_before = UpgradeHvacChiller.control_specifications(model)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### control specs before upgrade')
      runner.registerInfo("### fraction of CHW OAT reset control = #{chw_oat_reset_enabled_before}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # applicability
    # ------------------------------------------------
    if (counts_chillers_acc_b.size == 0) & (counts_chillers_wcc_b.size == 0)
      runner.registerAsNotApplicable('no chillers are found in the model.')
      return false
    end

    # ------------------------------------------------
    # report initial condition
    # ------------------------------------------------
    runner.registerInitialCondition("found #{counts_chillers_acc_b}/#{counts_chillers_wcc_b} air-cooled/water-cooled chillers with total capacity of #{capacity_total_w_acc_b.round(0)}/#{capacity_total_w_wcc_b.round(0)} W and capacity-weighted average COP of #{cop_weighted_average_acc_b.round(2)}/#{cop_weighted_average_wcc_b.round(2)}.")

    # ------------------------------------------------
    # replace chiller
    # ------------------------------------------------

    # initialize os standards
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # loop through chillers
    applicable_chillers.each do |chiller|
      # get chiller condenser type
      chiller_condenser_type = chiller.condenserType

      # get chiller tonnage
      if chiller.referenceCapacity.is_initialized
        capacity_w = chiller.referenceCapacity.get
      elsif chiller.autosizedReferenceCapacity.is_initialized
        capacity_w = chiller.autosizedReferenceCapacity.get
      else
        runner.registerError("Chiller capacity not available for chiller '#{chiller.name}'.")
        return false
      end
      capacity_ton = OpenStudio.convert(capacity_w, 'ton', 'W').get

      # get performance curve data
      custom_data_json = ''
      cop_full_load = nil
      case chiller_condenser_type
      when 'AirCooled'
        # 150ton_screw_variablespd_acc, curve representing IPLV EER of 16.4
        path_data_curve = "#{File.dirname(__FILE__)}/resources/150ton_screw_variablespd_acc/results.json"
        custom_data_json = JSON.parse(File.read(path_data_curve))
        cop_full_load = 3.17 # equivalent to full load EER of 10.8
      when 'WaterCooled'
        if capacity_ton < 150
          # 100ton_centrifugal_variablespd_wcc, curve representing IPLV EER of 24.8
          path_data_curve = "#{File.dirname(__FILE__)}/resources/100ton_centrifugal_variablespd_wcc/results.json"
          custom_data_json = JSON.parse(File.read(path_data_curve))
        else
          # 1500ton_centrifugal_variablespd_wcc, curve representing IPLV EER of 24.8
          path_data_curve = "#{File.dirname(__FILE__)}/resources/1500ton_centrifugal_variablespd_wcc/results.json"
          custom_data_json = JSON.parse(File.read(path_data_curve))
        end
        cop_full_load = 6.83 # equivalent to full load EER of 23.3
      else
        runner.registerError("#{chiller_condenser_type} chiller not supported in this measure. exiting...")
        return false
      end
      if custom_data_json == ''
        runner.registerError('found empty performance map. exiting...')
        return false
      end

      # get curve objects
      curve_cap_f_t = model_add_curve(model, 'cap-f-t', custom_data_json, std)
      curve_eir_f_t = model_add_curve(model, 'eir-f-t', custom_data_json, std)
      curve_eir_f_plr = model_add_curve(model, 'eir-f-plr', custom_data_json, std)

      # report
      if debug_verbose
        runner.registerInfo('### ------------------------------------------------------')
        runner.registerInfo("### chiller name = #{chiller.name}")
        runner.registerInfo("### chiller_condenser_type = #{chiller_condenser_type}")
        runner.registerInfo("### capacity_ton = #{capacity_ton.round(0)}")
        runner.registerInfo("### capacity_w = #{capacity_w.round(0)}")
        runner.registerInfo("### curve_cap_f_t = #{curve_cap_f_t}")
        runner.registerInfo("### curve_eir_f_t = #{curve_eir_f_t}")
        runner.registerInfo("### curve_eir_f_plr = #{curve_eir_f_plr}")
        runner.registerInfo('### ------------------------------------------------------')
      end

      # assign curves
      chiller.setCoolingCapacityFunctionOfTemperature(curve_cap_f_t)
      chiller.setElectricInputToCoolingOutputRatioFunctionOfTemperature(curve_eir_f_t)
      chiller.setElectricInputToCoolingOutputRatioFunctionOfPLR(curve_eir_f_plr)

      # set reference COPs
      if cop_full_load > chiller.referenceCOP
        chiller.setReferenceCOP(cop_full_load)
      else
        runner.registerInfo("Existing chiller COP (#{chiller.referenceCOP.round(2)}) already higher/better than COP from measure (#{cop_full_load.round(2)}). So, not replacing COP..")
      end

      # set reference operating conditions
      # AHRI Standard 550/590 at an air on condenser temperature of 95F and a leaving chilled water temperature of 44F
      chiller.setReferenceLeavingChilledWaterTemperature(6.67) # 44F
      chiller.setReferenceEnteringCondenserFluidTemperature(35.0) # 95F
    end

    # ------------------------------------------------
    # replace variable pump based on ASHRAE 90.1-2019
    # ------------------------------------------------
    applicable_pumps.each do |pump|
      if pump.to_PumpVariableSpeed.is_initialized
        pump_variable_speed_control_type(runner, model, pump, debug_verbose)
      end
    end

    # ------------------------------------------------
    # control upgrades
    # ------------------------------------------------
    if chw_oat_reset || cw_oat_reset
      plant_loops = model.getPlantLoops
      plant_loops.each do |plant_loop|
        if chw_oat_reset
          std.plant_loop_enable_supply_water_temperature_reset(plant_loop)
        end
        if cw_oat_reset
          std.plant_loop_apply_prm_baseline_condenser_water_temperatures(plant_loop)
        end
      end
    end

    # ------------------------------------------------
    # get chiller specifications after upgrade
    # ------------------------------------------------
    upgraded_chillers = model.getChillerElectricEIRs
    results_after = UpgradeHvacChiller.chiller_specifications(upgraded_chillers)
    counts_chillers_acc_a = results_after[0]
    capacity_total_w_acc_a = results_after[1]
    cop_weighted_average_acc_a = results_after[2]
    counts_chillers_wcc_a = results_after[3]
    capacity_total_w_wcc_a = results_after[4]
    cop_weighted_average_wcc_a = results_after[5]
    curve_summary_a = results_after[6]
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### chiller specs after upgrade')
      runner.registerInfo("### counts_chillers_acc = #{counts_chillers_acc_a}")
      runner.registerInfo("### capacity_total_w_acc= #{capacity_total_w_acc_a}")
      runner.registerInfo("### cop_weighted_average_acc = #{cop_weighted_average_acc_a}")
      runner.registerInfo("### counts_chillers_wcc = #{counts_chillers_wcc_a}")
      runner.registerInfo("### capacity_total_w_wcc = #{capacity_total_w_wcc_a}")
      runner.registerInfo("### cop_weighted_average_wcc = #{cop_weighted_average_wcc_a}")
      runner.registerInfo("### curve_summary = #{curve_summary_a}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # get pump specifications after upgrade
    # ------------------------------------------------
    dummy = []
    pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    _, pump_rated_flow_total_c, pump_motor_eff_weighted_average_c, pump_motor_bhp_weighted_average_c, = UpgradeHvacChiller.pump_specifications(dummy, pumps_const_spd, std)
    _, pump_rated_flow_total_v, pump_motor_eff_weighted_average_v, pump_motor_bhp_weighted_average_v, pump_var_part_load_curve_coeff1_weighted_avg, pump_var_part_load_curve_coeff2_weighted_avg, pump_var_part_load_curve_coeff3_weighted_avg, pump_var_part_load_curve_coeff4_weighted_avg = UpgradeHvacChiller.pump_specifications(dummy, pumps_var_spd, std)
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
    chw_oat_reset_enabled_after = UpgradeHvacChiller.control_specifications(model)
    if debug_verbose
      runner.registerInfo('### ------------------------------------------------------')
      runner.registerInfo('### control specs after upgrade')
      runner.registerInfo("### fraction of CHW OAT reset control = #{chw_oat_reset_enabled_after}")
      runner.registerInfo('### ------------------------------------------------------')
    end

    # ------------------------------------------------
    # report final condition
    # ------------------------------------------------
    if counts_chillers_acc_b == 0
      msg_acc = 'No air-cooled chillers are upgraded in this building model.'
    else
      msg_acc = "Upgraded air-cooled chillers: count = #{counts_chillers_acc_b} -> #{counts_chillers_acc_a}\n\
Upgraded air-cooled chillers: total capacity = #{capacity_total_w_acc_b} W -> #{capacity_total_w_acc_a}\n\
Upgraded air-cooled chillers: full load COP = #{cop_weighted_average_acc_b} -> #{cop_weighted_average_acc_a}\n\
Upgraded air-cooled chillers: curves before upgrade = #{curve_summary_b}\n\
Upgraded air-cooled chillers: curves after upgrade = #{curve_summary_a}"
    end
    if counts_chillers_wcc_b == 0
      msg_wcc = 'No water-cooled chillers are upgraded in this building model.'
    else
      msg_wcc = "Upgraded water-cooled chillers: count = #{counts_chillers_wcc_b} -> #{counts_chillers_wcc_a}\n\
Upgraded water-cooled chillers: total capacity = #{capacity_total_w_wcc_b} W -> #{capacity_total_w_wcc_a}\n\
Upgraded water-cooled chillers: average weighted full load COP = #{cop_weighted_average_wcc_b} -> #{cop_weighted_average_wcc_a}\n\
Upgraded water-cooled chillers: curves before upgrade = #{curve_summary_b}\n\
Upgraded water-cooled chillers: curves after upgrade = #{curve_summary_a}"
    end
    msg_final_condition = "#{msg_acc}\n#{msg_wcc}"
    runner.registerFinalCondition(msg_final_condition)

    return true
  end
end

# register the measure to be used by the application
UpgradeHvacChiller.new.registerWithApplication
