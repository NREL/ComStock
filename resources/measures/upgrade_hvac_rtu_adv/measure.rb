# frozen_string_literal: true

# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/
require 'openstudio-standards'
require 'json'

# start the measure
class UpgradeHvacRtuAdv < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'upgrade_hvac_rtu_adv'
  end

  # human readable description
  def description
    return 'replaces exisiting RTUs with top-of-the-line RTUs in the current (as of 7/30/2025) market. Improvements are from increased rated efficiencies, off-rated performances, and part-load performances.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'The high-efficiency RTU measure is applicable to ComStock models with either gas furnace RTUs (“PSZ-AC with gas coil”) or electric resistance RTUs (“PSZ-AC with electric coil”). This analysis includes only products that meet or exceed current building energy codes while representing the highest-performing models available on the market today. If the building currently uses gas for space heating, the upgraded RTU will be equipped with a gas furnace. If the building uses electricity for space heating, the RTU will include electric resistance heating. Heat/Energy Recovery Ventilator (H/ERVs) is included in the RTUs for this study, and the implementation and modeling will follow the approach used in previous work. Demand Control Ventilation (DCV) is included in the RTUs for this study, and the implementation and modeling will follow the approach used in previous work.'
  end

  # define the arguments that the user will input
  def arguments(_model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # add heat recovery option
    hr = OpenStudio::Measure::OSArgument.makeBoolArgument('hr', true)
    hr.setDisplayName('Add Energy Recovery?')
    hr.setDefaultValue(false)
    args << hr

    # add dcv option
    dcv = OpenStudio::Measure::OSArgument.makeBoolArgument('dcv', true)
    dcv.setDisplayName('Add Demand Control Ventilation?')
    dcv.setDefaultValue(false)
    args << dcv

    # enable/disable debugging outputs
    debug_verbose = OpenStudio::Measure::OSArgument.makeBoolArgument('debug_verbose', true)
    debug_verbose.setDisplayName('Enable Debugging Outputs?')
    debug_verbose.setDefaultValue(false)
    args << debug_verbose

    args
  end

  # define the outputs that the measure will create
  def outputs
    # outs = OpenStudio::Measure::OSOutputVector.new
    output_names = []

    result = OpenStudio::Measure::OSOutputVector.new
    output_names.each do |output|
      result << OpenStudio::Measure::OSOutput.makeDoubleOutput(output)
    end

    result
  end

  # Returns true if the air loop is residential (no outdoor air system), false otherwise.
  def air_loop_res?(air_loop_hvac)
    is_res_system = true
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_OutdoorAirSystem'
        is_res_system = false
      end
    end
    is_res_system
  end

  # Returns true if the air loop contains an evaporative cooler, false otherwise.
  def air_loop_evaporative_cooler?(air_loop_hvac)
    is_evap = false
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial', 'OS_EvaporativeFluidCooler_SingleSpeed', 'OS_EvaporativeFluidCooler_TwoSpeed'
        is_evap = true
      end
    end
    is_evap
  end

  # Returns true if the air loop contains a unitary system, false otherwise.
  def air_loop_hvac_unitary_system?(air_loop_hvac)
    is_unitary_system = false
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        is_unitary_system = true
      end
    end
    is_unitary_system
  end

  # Returns combined performance curves from resources folder
  def combine_all_performance_curves
    combined_data = {
      'tables' => {
        'curves' => {
          'table' => []
        }
      }
    }

    Dir[File.join(File.dirname(__FILE__), 'resources', '*.json')].each do |file_path|
      json_data = JSON.parse(File.read(file_path))
      tables = json_data.dig('tables', 'curves', 'table')
      if tables.is_a?(Array)
        combined_data['tables']['curves']['table'].concat(tables)
      else
        raise "Unexpected JSON structure in #{file_path}"
      end
    end
    combined_data
  end

  # Loads a curve from JSON and adds it to the model if not already present.
  def model_add_curve(model, curve_name, standards_data_curve, std)
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
        # OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added curve: #{curve_name}")
        return curve
      end
    end

    # OpenStudio::logFree(OpenStudio::Info, "openstudio.prototype.addCurve", "Adding curve '#{curve_name}' to the model.")

    # Find curve data
    data = std.model_find_object(standards_data_curve['tables']['curves'], 'name' => curve_name)
    if data.nil?
      # OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Could not find a curve called '#{curve_name}' in the standards.")
      return nil
    end

    # Make the correct type of curve
    case data['form']
    when 'Linear'
      curve = OpenStudio::Model::CurveLinear.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2x(data['coeff_2'])
      curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
      curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
      if data['minimum_dependent_variable_output']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      end
      if data['maximum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      end
      curve
    when 'Cubic'
      curve = OpenStudio::Model::CurveCubic.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2x(data['coeff_2'])
      curve.setCoefficient3xPOW2(data['coeff_3'])
      curve.setCoefficient4xPOW3(data['coeff_4'])
      curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
      curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
      if data['minimum_dependent_variable_output']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      end
      if data['maximum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      end
      curve
    when 'Quadratic'
      curve = OpenStudio::Model::CurveQuadratic.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2x(data['coeff_2'])
      curve.setCoefficient3xPOW2(data['coeff_3'])
      curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
      curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
      if data['minimum_dependent_variable_output']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      end
      if data['maximum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      end
      curve
    when 'BiCubic'
      curve = OpenStudio::Model::CurveBicubic.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2x(data['coeff_2'])
      curve.setCoefficient3xPOW2(data['coeff_3'])
      curve.setCoefficient4y(data['coeff_4'])
      curve.setCoefficient5yPOW2(data['coeff_5'])
      curve.setCoefficient6xTIMESY(data['coeff_6'])
      curve.setCoefficient7xPOW3(data['coeff_7'])
      curve.setCoefficient8yPOW3(data['coeff_8'])
      curve.setCoefficient9xPOW2TIMESY(data['coeff_9'])
      curve.setCoefficient10xTIMESYPOW2(data['coeff_10'])
      curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
      curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
      curve.setMinimumValueofy(data['minimum_independent_variable_2']) if data['minimum_independent_variable_2']
      curve.setMaximumValueofy(data['maximum_independent_variable_2']) if data['maximum_independent_variable_2']
      if data['minimum_dependent_variable_output']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      end
      if data['maximum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      end
      curve
    when 'BiQuadratic'
      curve = OpenStudio::Model::CurveBiquadratic.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2x(data['coeff_2'])
      curve.setCoefficient3xPOW2(data['coeff_3'])
      curve.setCoefficient4y(data['coeff_4'])
      curve.setCoefficient5yPOW2(data['coeff_5'])
      curve.setCoefficient6xTIMESY(data['coeff_6'])
      curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
      curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
      curve.setMinimumValueofy(data['minimum_independent_variable_2']) if data['minimum_independent_variable_2']
      curve.setMaximumValueofy(data['maximum_independent_variable_2']) if data['maximum_independent_variable_2']
      if data['minimum_dependent_variable_output']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      end
      if data['maximum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      end
      curve
    when 'BiLinear'
      curve = OpenStudio::Model::CurveBiquadratic.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2x(data['coeff_2'])
      curve.setCoefficient4y(data['coeff_3'])
      curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
      curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
      curve.setMinimumValueofy(data['minimum_independent_variable_2']) if data['minimum_independent_variable_2']
      curve.setMaximumValueofy(data['maximum_independent_variable_2']) if data['maximum_independent_variable_2']
      if data['minimum_dependent_variable_output']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      end
      if data['maximum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      end
      curve
    when 'QuadLinear'
      curve = OpenStudio::Model::CurveQuadLinear.new(model)
      curve.setName(data['name'])
      curve.setCoefficient1Constant(data['coeff_1'])
      curve.setCoefficient2w(data['coeff_2'])
      curve.setCoefficient3x(data['coeff_3'])
      curve.setCoefficient4y(data['coeff_4'])
      curve.setCoefficient5z(data['coeff_5'])
      curve.setMinimumValueofw(data['minimum_independent_variable_w'])
      curve.setMaximumValueofw(data['maximum_independent_variable_w'])
      curve.setMinimumValueofx(data['minimum_independent_variable_x'])
      curve.setMaximumValueofx(data['maximum_independent_variable_x'])
      curve.setMinimumValueofy(data['minimum_independent_variable_y'])
      curve.setMaximumValueofy(data['maximum_independent_variable_y'])
      curve.setMinimumValueofz(data['minimum_independent_variable_z'])
      curve.setMaximumValueofz(data['maximum_independent_variable_z'])
      curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
      curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
      curve
    when 'MultiVariableLookupTable'
      num_ind_var = data['number_independent_variables'].to_i
      table = OpenStudio::Model::TableLookup.new(model)
      table.setName(data['name'])
      table.setNormalizationDivisor(data['normalization_reference'].to_f)
      table.setOutputUnitType(data['output_unit_type'])
      data_points = data.each.select { |key, _value| key.include? 'data_point' }
      data_points = data_points.sort_by { |item| item[1].split(',').map(&:to_f) } # sorting data in ascending order
      data_points.each do |_key, value|
        var_dep = value.split(',')[num_ind_var].to_f
        table.addOutputValue(var_dep)
      end
      num_ind_var.times do |i|
        table_indvar = OpenStudio::Model::TableIndependentVariable.new(model)
        table_indvar.setName(data['name'] + "_ind_#{i + 1}")
        table_indvar.setInterpolationMethod(data['interpolation_method'])
        table_indvar.setMinimumValue(data["minimum_independent_variable_#{i + 1}"].to_f)
        table_indvar.setMaximumValue(data["maximum_independent_variable_#{i + 1}"].to_f)
        table_indvar.setUnitType(data["input_unit_type_x#{i + 1}"].to_s)
        var_ind_unique = data_points.map { |_key, value| value.split(',')[i].to_f }.uniq
        var_ind_unique.each { |var_ind| table_indvar.addValue(var_ind) }
        table.addIndependentVariable(table_indvar)
      end
      table
    end
  end

  # Returns the curve object based on curve type, unit size, and operation stage.
  def get_curve_object(runner, type, reference_capacity, operation_stage, debug_verbose)
    curve_name = nil

    # determine prefix
    curve_name_prefix = nil
    if type.include?('fn_of_t')
      curve_name_prefix = 'lookup_'
    elsif type.include?('fn_of_ff')
      curve_name_prefix = 'poly_'
    end

    # determine dependent var
    curve_name_dep_var = nil
    if type.include?('capacity_')
      curve_name_dep_var = 'capacity'
    elsif type.include?('eir_')
      curve_name_dep_var = 'eir'
    end

    # determine operation stage
    curve_name_stage = nil
    case operation_stage
    when 1
      curve_name_stage = 'low'
    when 2
      curve_name_stage = 'med'
    when 3
      curve_name_stage = 'high'
    end

    # determine size category and create complete curve name
    curve_name_size = nil
    if reference_capacity < 39564.59445 # = 135 kBtu/hr
      curve_name_size = '0_11'
    elsif reference_capacity < 70337.0568 # = 240 kBtu/hr
      curve_name_size = '11_20'
    else
      curve_name_size = '20_9999'
    end

    # construct curve name
    curve_name = [curve_name_prefix, 'rtu_adv', curve_name_dep_var, curve_name_size, curve_name_stage].join('_')
    if debug_verbose
      runner.registerInfo('--- stage {} | reference_capacity_w = {} | curve = {}'.format(stage, reference_capacity, curve_name))
    end

    curve_name
  end

  # Returns the rated cooling COP for advanced RTU given the rated capacity (W).
  def get_rated_cop_cooling_adv(rated_capacity_w)
    intercept = nil
    coef_1 = nil
    min_cop = nil
    max_cop = nil
    if rated_capacity_w < 39564.59445 # = 135 kBtu/hr
      intercept = 4.26
      coef_1 = -0.0000027392
      min_cop = 4.15
      max_cop = 4.26
    elsif rated_capacity_w < 70337.0568 # = 240 kBtu/hr
      intercept = 4.24
      coef_1 = -0.0000057962
      min_cop = 3.83
      max_cop = 4.01
    else
      intercept = 3.68
      coef_1 = -1.6479e-07
      min_cop = 3.62
      max_cop = 3.67
    end
    rated_cop_cooling = intercept + (coef_1 * rated_capacity_w)
    rated_cop_cooling.clamp(min_cop, max_cop)
  end

  # Converts CFM/ton to m^3/s per W.
  def cfm_per_ton_to_m_3_per_sec_watts(cfm_per_ton)
    OpenStudio.convert(OpenStudio.convert(cfm_per_ton, 'cfm', 'm^3/s').get, 'W', 'ton').get
  end

  # Converts m^3/s per W to CFM/ton.
  def m_3_per_sec_watts_to_cfm_per_ton(m_3_per_sec_watts)
    OpenStudio.convert(OpenStudio.convert(m_3_per_sec_watts, 'm^3/s', 'cfm').get, 'ton', 'W').get
  end

  # Adjusts the rated COP based on reference CFM/ton and a flow modifier curve.
  def adjust_rated_cop_from_ref_cfm_per_ton(runner, airflow_sized_m_3_per_s, reference_cfm_per_ton, rated_capacity_w,
                                            original_rated_cop, eir_modifier_curve_flow)
    # get reference airflow
    airflow_reference_m_3_per_s = cfm_per_ton_to_m_3_per_sec_watts(reference_cfm_per_ton) * rated_capacity_w

    # get flow fraction
    flow_fraction = airflow_sized_m_3_per_s / airflow_reference_m_3_per_s

    # calculate modifiers
    modifier_eir = nil
    if eir_modifier_curve_flow.to_CurveBiquadratic.is_initialized
      modifier_eir = eir_modifier_curve_flow.evaluate(flow_fraction, 0)
    elsif eir_modifier_curve_flow.to_CurveCubic.is_initialized
      modifier_eir = eir_modifier_curve_flow.evaluate(flow_fraction)
    elsif eir_modifier_curve_flow.to_CurveQuadratic.is_initialized
      modifier_eir = eir_modifier_curve_flow.evaluate(flow_fraction)
    else
      runner.registerError("CurveBiquadratic|CurveQuadratic|CurveCubic are only supported at the moment for modifier_eir (function of flow fraction) calculation: eir_modifier_curve_flow = #{eir_modifier_curve_flow.name}")
    end

    # adjust rated COP (COP = 1 / EIR)
    original_rated_cop * (1.0 / modifier_eir)
  end

  # Returns tabular data from the SQL file for a given report/table/row/column.
  def get_tabular_data(runner, _model, sql, report_name, report_for_string, table_name, row_name, column_name)
    result = OpenStudio::OptionalDouble.new
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = '#{report_name}' AND ReportForString = '#{report_for_string}' AND TableName = '#{table_name}' AND RowName = '#{row_name}' AND ColumnName = '#{column_name}'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      result = OpenStudio::OptionalDouble.new(val.get)
    else
      runner.registerError("Cannot query: #{report_name} | #{report_for_string} | #{table_name} | #{row_name} | #{column_name}")
    end
    result
  end

  # Returns the dependent variable from a TableLookup object using bilinear interpolation for two inputs.
  def self.get_dep_var_from_lookup_table_with_interpolation(runner, lookup_table, input1, input2)
    if lookup_table.independentVariables.size == 2
      # Extract independent variable arrays
      ind_var_1 = lookup_table.independentVariables[0].values.to_a
      ind_var_2 = lookup_table.independentVariables[1].values.to_a
      dep_var = lookup_table.outputValues.to_a

      if ind_var_1.size * ind_var_2.size != dep_var.size
        runner.registerError("Table dimensions do not match output size for TableLookup object: #{lookup_table.name}")
        return false
      end

      # Clamp input1 to bounds
      if input1 < ind_var_1.first
        runner.registerWarning("input1 (#{input1}) below range, clamping to #{ind_var_1.first}")
        input1 = ind_var_1.first
      elsif input1 > ind_var_1.last
        runner.registerWarning("input1 (#{input1}) above range, clamping to #{ind_var_1.last}")
        input1 = ind_var_1.last
      end

      # Clamp input2 to bounds
      if input2 < ind_var_2.first
        runner.registerWarning("input2 (#{input2}) below range, clamping to #{ind_var_2.first}")
        input2 = ind_var_2.first
      elsif input2 > ind_var_2.last
        runner.registerWarning("input2 (#{input2}) above range, clamping to #{ind_var_2.last}")
        input2 = ind_var_2.last
      end

      # Find bounding indices for input1
      i1_upper = ind_var_1.index { |val| val >= input1 } || (ind_var_1.size - 1)
      i1_lower = [i1_upper - 1, 0].max

      # Find bounding indices for input2
      i2_upper = ind_var_2.index { |val| val >= input2 } || (ind_var_2.size - 1)
      i2_lower = [i2_upper - 1, 0].max

      x1 = ind_var_1[i1_lower]
      x2 = ind_var_1[i1_upper]
      y1 = ind_var_2[i2_lower]
      y2 = ind_var_2[i2_upper]

      # Get dependent variable values for bilinear interpolation
      v11 = dep_var[i1_lower * ind_var_2.size + i2_lower]  # (x1, y1)
      v12 = dep_var[i1_lower * ind_var_2.size + i2_upper]  # (x1, y2)
      v21 = dep_var[i1_upper * ind_var_2.size + i2_lower]  # (x2, y1)
      v22 = dep_var[i1_upper * ind_var_2.size + i2_upper]  # (x2, y2)

      # If exact match, return directly
      if input1 == x1 && input2 == y1
        return v11
      elsif input1 == x1 && input2 == y2
        return v12
      elsif input1 == x2 && input2 == y1
        return v21
      elsif input1 == x2 && input2 == y2
        return v22
      end

      # Handle edge cases where interpolation becomes linear
      dx = x2 - x1
      dy = y2 - y1
      return v11 if dx == 0 && dy == 0
      return v11 + (v21 - v11) * (input1 - x1) / dx if dy == 0
      return v11 + (v12 - v11) * (input2 - y1) / dy if dx == 0

      # Bilinear interpolation
      interpolated_value =
        v11 * (x2 - input1) * (y2 - input2) +
        v21 * (input1 - x1) * (y2 - input2) +
        v12 * (x2 - input1) * (input2 - y1) +
        v22 * (input1 - x1) * (input2 - y1)

      interpolated_value /= (x2 - x1) * (y2 - y1)

      interpolated_value
    else
      runner.registerError('TableLookup object does not have exactly two independent variables.')
      false
    end
  end

  #### End predefined functions

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # ---------------------------------------------------------
    # use the built-in error checking
    # ---------------------------------------------------------
    return false unless runner.validateUserArguments(arguments(model), user_arguments)

    # ---------------------------------------------------------
    # assign the user inputs to variables
    # ---------------------------------------------------------
    hr = runner.getBoolArgumentValue('hr', user_arguments)
    dcv = runner.getBoolArgumentValue('dcv', user_arguments)
    debug_verbose = runner.getBoolArgumentValue('debug_verbose', user_arguments)

    # build standard to use OS standards methods
    # ---------------------------------------------------------
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # ---------------------------------------------------------
    # get applicable psz hvac air loops
    # ---------------------------------------------------------
    selected_air_loops = []
    applicable_area_m2 = 0
    prim_ht_fuel_type = 'electric' # we assume electric unless we find a gas coil in any air loop
    is_sizing_run_needed = true
    unitary_sys = nil
    orig_airloop_heating_coil_map = {}
    model.getAirLoopHVACs.each do |air_loop_hvac|
      # skip units that are not single zone
      next if air_loop_hvac.thermalZones.length > 1

      # skip DOAS units; check sizing for all OA and for DOAS in name
      sizing_system = air_loop_hvac.sizingSystem
      if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating && (air_loop_res?(air_loop_hvac) == false) && (air_loop_hvac.name.to_s.include?('DOAS') || air_loop_hvac.name.to_s.include?('doas'))
        next
      end

      # skip if already heat pump RTU
      # loop throug air loop components to check for heat pump or water coils
      is_hp = false
      is_water_coil = false
      has_heating_coil = true
      air_loop_hvac.supplyComponents.each do |component|
        obj_type = component.iddObjectType.valueName.to_s
        # flag system if contains water coil; this will cause air loop to be skipped
        is_water_coil = true if ['Coil_Heating_Water', 'Coil_Cooling_Water'].any? { |word| obj_type.include?(word) }
        # flag gas heating as true if gas coil is found in any airloop
        prim_ht_fuel_type = 'gas' if ['Gas', 'GAS', 'gas'].any? { |word| obj_type.include?(word) }
        # check unitary systems for DX heating or water coils
        if obj_type == 'OS_AirLoopHVAC_UnitarySystem'
          unitary_sys = component.to_AirLoopHVACUnitarySystem.get

          # check if heating coil is DX or water-based; if so, flag the air loop to be skipped
          if unitary_sys.heatingCoil.is_initialized
            htg_coil = unitary_sys.heatingCoil.get.iddObjectType.valueName.to_s
            # check for DX heating coil
            if ['Heating_DX'].any? { |word| htg_coil.include?(word) }
              is_hp = true
            # check for water heating coil
            elsif ['Water'].any? { |word| htg_coil.include?(word) }
              is_water_coil = true
            # check for gas heating
            elsif ['Gas', 'GAS', 'gas'].any? { |word| htg_coil.include?(word) }
              prim_ht_fuel_type = 'gas'
            end
          else
            runner.registerWarning("No heating coil was found for air loop: #{air_loop_hvac.name} - this equipment will be skipped.")
            has_heating_coil = false
          end
          # check if cooling coil is water-based
          if unitary_sys.coolingCoil.is_initialized
            clg_coil = unitary_sys.coolingCoil.get.iddObjectType.valueName.to_s
            # skip unless coil is water based
            next unless ['Water'].any? { |word| clg_coil.include?(word) }

            is_water_coil = true
          end
        # flag as hp if air loop contains a heating dx coil
        elsif ['Heating_DX'].any? { |word| obj_type.include?(word) }
          is_hp = true
        end
      end
      # also skip based on string match, or if dx heating component existed
      if (is_hp == true) | (air_loop_hvac.name.to_s.include?('HP') || air_loop_hvac.name.to_s.include?('hp') || air_loop_hvac.name.to_s.include?('heat pump') || air_loop_hvac.name.to_s.include?('Heat Pump'))
        next
      end
      # skip data centers
      next if ['Data Center', 'DataCenter', 'data center', 'datacenter', 'DATACENTER', 'DATA CENTER'].any? do |word|
                air_loop_hvac.name.get.include?(word)
              end
      # skip kitchens
      next if ['Kitchen', 'KITCHEN', 'Kitchen'].any? { |word| air_loop_hvac.name.get.include?(word) }
      # skip VAV sysems
      next if ['VAV', 'PVAV'].any? { |word| air_loop_hvac.name.get.include?(word) }
      # skip if residential system
      next if air_loop_res?(air_loop_hvac)
      # skip if system has no outdoor air, also indication of residential system
      next unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      # skip if evaporative cooling systems
      next if air_loop_evaporative_cooler?(air_loop_hvac)
      # skip if water heating or cooled system
      next if is_water_coil == true
      # skip if space is not heated and cooled
      unless OpenstudioStandards::ThermalZone.thermal_zone_heated?(air_loop_hvac.thermalZones[0]) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(air_loop_hvac.thermalZones[0])
        next
      end
      # next if no heating coil
      next if has_heating_coil == false

      # add applicable air loop to list
      selected_air_loops << air_loop_hvac
      # add area served by air loop
      thermal_zone = air_loop_hvac.thermalZones[0]
      applicable_area_m2 += thermal_zone.floorArea * thermal_zone.multiplier

      ############# Determine if equipment has been hardsized to avoid sizing run
      oa_flow_m3_per_s = nil
      old_terminal_sa_flow_m3_per_s = nil
      orig_clg_coil_gross_cap = nil
      orig_clg_coil_rated_airflow_m_3_per_s = nil
      orig_htg_coil_gross_cap = nil

      # determine if sizing run is needed
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      end

      # get design supply air flow rate
      if air_loop_hvac.designSupplyAirFlowRate.is_initialized
        old_terminal_sa_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
      end

      # get previous cooling coil capacity
      orig_clg_coil = unitary_sys.coolingCoil.get
      if orig_clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
        orig_clg_coil = orig_clg_coil.to_CoilCoolingDXSingleSpeed.get
        # get either autosized or specified cooling capacityet
        if orig_clg_coil.ratedTotalCoolingCapacity.is_initialized
          orig_clg_coil_gross_cap = orig_clg_coil.ratedTotalCoolingCapacity.to_f
        end
        if orig_clg_coil.ratedAirFlowRate.is_initialized
          orig_clg_coil_rated_airflow_m_3_per_s = orig_clg_coil.ratedAirFlowRate.to_f
        end
      end

      # get original heating coil capacity
      orig_htg_coil = unitary_sys.heatingCoil.get
      # get coil object if electric resistance
      if orig_htg_coil.to_CoilHeatingElectric.is_initialized
        orig_htg_coil = orig_htg_coil.to_CoilHeatingElectric.get
      # get coil object if gas
      elsif orig_htg_coil.to_CoilHeatingGas.is_initialized
        orig_htg_coil = orig_htg_coil.to_CoilHeatingGas.get
      end
      # get either autosized or specified capacity
      orig_htg_coil_gross_cap = orig_htg_coil.nominalCapacity.to_f if orig_htg_coil.nominalCapacity.is_initialized

      # map heating coil with airloop name for sizing algorithm later
      orig_airloop_heating_coil_map[air_loop_hvac.name.to_s] = orig_htg_coil.name.to_s.upcase

      # only require sizing run if required attributes have not been hardsized.
      next if oa_flow_m3_per_s.nil?
      next if old_terminal_sa_flow_m3_per_s.nil?
      next if orig_clg_coil_gross_cap.nil?
      next if orig_htg_coil_gross_cap.nil?

      is_sizing_run_needed = false
    end

    # ---------------------------------------------------------
    # remove units with high OA fractions and night cycling
    # ---------------------------------------------------------
    # add systems with high outdoor air ratios to a list for non-applicability
    oa_ration_allowance = 0.55
    selected_air_loops.each do |air_loop_hvac|
      thermal_zone = air_loop_hvac.thermalZones[0]

      # get the min OA flow rate for calculating unit OA fraction
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      oa_flow_m3_per_s = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        runner.registerError("No outdoor air sizing information was found for #{controller_oa.name}, which is required for setting ERV wheel power consumption.")
        return false
      end

      # get design supply air flow rate
      old_terminal_sa_flow_m3_per_s = nil
      if air_loop_hvac.designSupplyAirFlowRate.is_initialized
        old_terminal_sa_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
      elsif air_loop_hvac.isDesignSupplyAirFlowRateAutosized
        old_terminal_sa_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
      else
        runner.registerError("No sizing data available for air loop #{air_loop_hvac.name} zone terminal box.")
      end

      # define minimum flow rate needed to maintain ventilation - add in max fraction if in model
      min_oa_flow_ratio = (oa_flow_m3_per_s / old_terminal_sa_flow_m3_per_s)

      # check to see if there is night cycling operation for unit
      night_cyc_sched_vals = []
      air_loop_hvac.supplyComponents.each do |component|
        # convert component to string name
        obj_type = component.iddObjectType.valueName.to_s
        # skip unless component is of relevant type
        next unless ['Unitary'].any? { |word| obj_type.include?(word) }

        unitary_sys = component.to_AirLoopHVACUnitarySystem.get
        # get supply fan operating schedule
        next unless unitary_sys.supplyAirFanOperatingModeSchedule.is_initialized

        sf_sched = unitary_sys.supplyAirFanOperatingModeSchedule.get
        if sf_sched.to_ScheduleRuleset.is_initialized
          sf_sched = sf_sched.to_ScheduleRuleset.get
        elsif sf_sched.to_ScheduleConstant.is_initialized
          sf_sched = sf_sched.to_ScheduleConstant.get
        end

        if sf_sched.to_ScheduleRuleset.is_initialized
          sf_sched_rules_ar = sf_sched.scheduleRules
          # loop through schedules in ruleset
          sf_sched_rules_ar.each do |sched_rule|
            sched_values = sched_rule.daySchedule.values
            # loop through schedule values and add to array
            sched_values.each do |value|
              night_cyc_sched_vals << value
            end
          end
        elsif sf_sched.to_ScheduleConstant.is_initialized
          value = sf_sched.value
          night_cyc_sched_vals << value
        end
      end

      # if supply operating schedule does not include a 0, the unit does not night cycle
      unit_night_cycles = night_cyc_sched_vals.include? [0, 0.0]

      # register as not applicable if OA limit exceeded and unit has night cycling schedules
      next unless (min_oa_flow_ratio > oa_ration_allowance) && (unit_night_cycles == true)

      runner.registerWarning("Air loop #{air_loop_hvac.name} has night cycling operations and an outdoor air ratio of #{min_oa_flow_ratio.round(2)} which exceeds the maximum allowable limit of #{oa_ration_allowance} (due to an EnergyPlus night cycling bug with multispeed coils) making this RTU not applicable at this time.")
      # remove air loop from applicable list
      selected_air_loops.delete(air_loop_hvac)
      applicable_area_m2 -= thermal_zone.floorArea * thermal_zone.multiplier
      # remove area served by air loop from applicability
    end

    # ---------------------------------------------------------
    # check if any air loops are applicable to measure
    # ---------------------------------------------------------
    if selected_air_loops.empty?
      runner.registerAsNotApplicable('No applicable air loops in model. No changes will be made.')
      return true
    end

    # ---------------------------------------------------------
    # get model conditioned square footage for reporting
    # ---------------------------------------------------------
    if model.building.get.conditionedFloorArea.empty?
      runner.registerWarning('model.building.get.conditionedFloorArea() is empty; applicable floor area fraction will not be reported.')
      # report initial condition of model
      condition = "The building has #{selected_air_loops.size} applicable air loops (out of the total #{model.getAirLoopHVACs.size} airloops in the model) that will be replaced with high-efficiency RTUs, serving #{applicable_area_m2.round(0)} m2 of floor area. The remaning airloops were determined to be not applicable."
      runner.registerInitialCondition(condition)
    else
      total_area_m2 = model.building.get.conditionedFloorArea.get
      # fraction of conditioned floorspace
      applicable_floorspace_frac = applicable_area_m2 / total_area_m2
      # report initial condition of model
      condition = "The building has #{selected_air_loops.size} applicable air loops that will be replaced with high-efficiency RTUs, representing #{(applicable_floorspace_frac * 100).round(2)}% of the building floor area. #{condition_initial_roof}. #{condition_initial_window}."
      runner.registerInitialCondition(condition)
    end

    # ---------------------------------------------------------
    # applicability checks for heat recovery; building type
    # ---------------------------------------------------------
    # building type not applicable to ERVs as part of this measure will receive no additional or modification of ERV systems
    # this is only relevant if the user selected to add ERVs
    # space type applicability is handled later in the code when looping through individual air loops
    building_types_to_exclude = ['RFF', 'RSD', 'QuickServiceRestaurant', 'FullServiceRestaurant']
    # determine building type applicability for ERV
    btype_erv_applicable = true
    building_types_to_exclude = building_types_to_exclude.map(&:downcase)
    # get Standards building type name and check against building type applicability list
    model_building_type = nil
    if model.getBuilding.standardsBuildingType.is_initialized
      model_building_type = model.getBuilding.standardsBuildingType.get
    else
      runner.registerError('Building type not found.')
      return true
    end
    # register applicability; this will be used in code section where ERV is added
    btype_erv_applicable = false if building_types_to_exclude.include?(model_building_type.downcase)
    # warn user if they selected to add ERV but building type is not applicable for ERV
    if (hr == true) && (btype_erv_applicable == false)
      runner.registerWarning("The user chose to include energy recovery in the high-efficiency RTUs, but the building type -#{model_building_type}- is not applicable for energy recovery. Energy recovery will not be added.")
    end

    # get climate full string and classification (i.e. "5A")
    climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)
    climate_zone_classification = climate_zone.split('-')[-1]

    # Get ER/HR type from climate zone
    _, _, doas_type =
      if ['1A', '2A', '3A', '4A', '5A', '6A', '7', '7A', '8', '8A'].include?(climate_zone_classification)
        [12.7778, 19.4444, 'ERV']
      else
        [15.5556, 19.4444, 'HRV']
      end

    # ---------------------------------------------------------
    # replace existing applicable air loops with new high-efficiency rtu air loops
    # ---------------------------------------------------------
    selected_air_loops.sort.each do |air_loop_hvac|
      # initialize variables before loop
      hvac_operation_sched = air_loop_hvac.availabilitySchedule
      unitary_availability_sched = 'tmp'
      control_zone = 'tmp'
      dehumid_type = 'tmp'
      supply_fan_op_sched = 'tmp'
      supply_fan_avail_sched = 'tmp'
      fan_tot_eff = 'tmp'
      fan_mot_eff = 'tmp'
      fan_static_pressure = 'tmp'
      orig_clg_coil_gross_cap = nil
      orig_htg_coil_gross_cap = nil

      # -------------------------------------------------------
      # delete existing system
      # -------------------------------------------------------
      equip_to_delete = []
      # for unitary systems
      if air_loop_hvac_unitary_system?(air_loop_hvac)

        # loop through each relevant component.
        # store information needed as variable
        # remove the existing equipment
        air_loop_hvac.supplyComponents.each do |component|
          # convert component to string name
          obj_type = component.iddObjectType.valueName.to_s
          # skip unless component is of relevant type
          next unless ['Fan', 'Unitary', 'Coil'].any? { |word| obj_type.include?(word) }

          # make list of equipment to delete
          equip_to_delete << component

          # get information specifically from unitary system object
          next unless ['Unitary'].any? do |word|
                        obj_type.include?(word)
                      end

          # get unitary system
          unitary_sys = component.to_AirLoopHVACUnitarySystem.get
          # get availability schedule
          unitary_availability_sched = unitary_sys.availabilitySchedule.get
          # get control zone
          control_zone = unitary_sys.controllingZoneorThermostatLocation.get
          # get dehumidification control type
          dehumid_type = unitary_sys.dehumidificationControlType
          # get supply fan operation schedule
          supply_fan_op_sched = unitary_sys.supplyAirFanOperatingModeSchedule.get
          # get supply fan availability schedule
          supply_fan = unitary_sys.supplyFan.get
          # convert supply fan to appropriate object to access methods
          if supply_fan.to_FanConstantVolume.is_initialized
            supply_fan = supply_fan.to_FanConstantVolume.get
          elsif supply_fan.to_FanOnOff.is_initialized
            supply_fan = supply_fan.to_FanOnOff.get
          elsif supply_fan.to_FanVariableVolume.is_initialized
            supply_fan = supply_fan.to_FanVariableVolume.get
          else
            runner.registerError("Supply fan type for #{air_loop_hvac.name} not supported.")
            return false
          end
          # get the availability schedule
          supply_fan_avail_sched = supply_fan.availabilitySchedule
          if supply_fan_avail_sched.to_ScheduleConstant.is_initialized
            supply_fan_avail_sched = supply_fan_avail_sched.to_ScheduleConstant.get
          elsif supply_fan_avail_sched.to_ScheduleRuleset.is_initialized
            supply_fan_avail_sched = supply_fan_avail_sched.to_ScheduleConstant.get
          else
            runner.registerError("Supply fan availability schedule type for #{supply_fan.name} not supported.")
            return false
          end
          # get supply fan motor efficiency
          fan_tot_eff = supply_fan.fanTotalEfficiency
          # get supply motor efficiency
          fan_mot_eff = supply_fan.motorEfficiency
          # get supply fan static pressure
          fan_static_pressure = supply_fan.pressureRise
          # get previous cooling coil capacity
          orig_clg_coil = unitary_sys.coolingCoil.get

          # check for single speed DX cooling coil
          if orig_clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
            orig_clg_coil = orig_clg_coil.to_CoilCoolingDXSingleSpeed.get
            # get either autosized or specified cooling capacity
            if orig_clg_coil.isRatedTotalCoolingCapacityAutosized == true
              orig_clg_coil_gross_cap = orig_clg_coil.autosizedRatedTotalCoolingCapacity.get
            elsif orig_clg_coil.ratedTotalCoolingCapacity.is_initialized
              orig_clg_coil_gross_cap = orig_clg_coil.ratedTotalCoolingCapacity.to_f
            else
              runner.registerError("Original cooling coil capacity for #{air_loop_hvac.name} not found. Either it was not directly specified, or sizing run data is not available.")
            end
          # check for two speed DX cooling coil
          elsif orig_clg_coil.to_CoilCoolingDXTwoSpeed.is_initialized
            orig_clg_coil = orig_clg_coil.to_CoilCoolingDXTwoSpeed.get
            if orig_clg_coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
              orig_clg_coil_gross_cap = orig_clg_coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
            elsif orig_clg_coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
              orig_clg_coil_gross_cap = orig_clg_coil.ratedHighSpeedTotalCoolingCapacity.get
            else
              runner.registerError("Original cooling coil capacity for #{air_loop_hvac.name} not found. Either it was not directly specified, or sizing run data is not available.")
            end
          else
            runner.registerError("Original cooling coil is of type #{orig_clg_coil.class} which is not currently supported by this measure.")
          end

          # get original heating coil capacity
          orig_htg_coil = unitary_sys.heatingCoil.get
          # get coil object if electric resistance
          if orig_htg_coil.to_CoilHeatingElectric.is_initialized
            orig_htg_coil = orig_htg_coil.to_CoilHeatingElectric.get
          # get coil object if gas
          elsif orig_htg_coil.to_CoilHeatingGas.is_initialized
            orig_htg_coil = orig_htg_coil.to_CoilHeatingGas.get
          else
            runner.registerError("Heating coil for #{air_loop_hvac.name} is of an unsupported type. This measure currently supports CoilHeatingElectric and CoilHeatingGas object types.")
          end
          # get either autosized or specified capacity
          if orig_htg_coil.isNominalCapacityAutosized == true
            orig_htg_coil_gross_cap = orig_htg_coil.autosizedNominalCapacity.get
          elsif orig_htg_coil.nominalCapacity.is_initialized
            orig_htg_coil_gross_cap = orig_htg_coil.nominalCapacity.to_f
          else
            runner.registerError("Original heating coil capacity for #{air_loop_hvac.name} not found. Either it was not directly specified, or sizing run data is not available.")
          end
        end

      # get non-unitary system objects.
      else
        # loop through components
        air_loop_hvac.supplyComponents.each do |component|
          # convert component to string name
          obj_type = component.iddObjectType.valueName.to_s
          # skip unless component is of relevant type
          next unless ['Fan', 'Unitary', 'Coil'].any? { |word| obj_type.include?(word) }

          # make list of equipment to delete
          equip_to_delete << component
          # check for fan
          next unless ['Fan'].any? { |word| obj_type.include?(word) }

          supply_fan = component
          if supply_fan.to_FanConstantVolume.is_initialized
            supply_fan = supply_fan.to_FanConstantVolume.get
          elsif supply_fan.to_FanOnOff.is_initialized
            supply_fan = supply_fan.to_FanOnOff.get
          elsif supply_fan.to_FanVariableVolume.is_initialized
            supply_fan = supply_fan.to_FanVariableVolume.get
          else
            runner.registerError("Supply fan type for #{air_loop_hvac.name} not supported.")
            return false
          end
          # get the availability schedule
          supply_fan_avail_sched = supply_fan.availabilitySchedule
          if supply_fan_avail_sched.to_ScheduleConstant.is_initialized
            supply_fan_avail_sched = supply_fan_avail_sched.to_ScheduleConstant.get
          elsif supply_fan_avail_sched.to_ScheduleRuleset.is_initialized
            supply_fan_avail_sched = supply_fan_avail_sched.to_ScheduleConstant.get
          else
            runner.registerError("Supply fan availability schedule type for #{supply_fan.name} not supported.")
            return false
          end
          # get supply fan motor efficiency
          fan_tot_eff = supply_fan.fanTotalEfficiency
          # get supply motor efficiency
          fan_mot_eff = supply_fan.motorEfficiency
          # get supply fan static pressure
          fan_static_pressure = supply_fan.pressureRise
          # set unitary supply fan operating schedule equal to system schedule for non-unitary systems
          supply_fan_op_sched = hvac_operation_sched
          # set dehumidification type
          dehumid_type = 'None'
          # set control zone to the thermal zone. This will be used in new unitary system object
          control_zone = air_loop_hvac.thermalZones[0]
          # set unitary availability schedule to be always on. This will be used in new unitary system object.
          unitary_availability_sched = model.alwaysOnDiscreteSchedule
        end
      end

      # delete equipment from original loop
      equip_to_delete.each(&:remove)

      # -------------------------------------------------------
      # Update others
      # -------------------------------------------------------
      # set always on schedule; this will be used in other object definitions
      always_on = model.alwaysOnDiscreteSchedule

      # get thermal zone
      thermal_zone = air_loop_hvac.thermalZones[0]

      # Get the min OA flow rate from the OA; this is used below
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      oa_flow_m3_per_s = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        runner.registerError("No outdoor air sizing information was found for #{controller_oa.name}, which is required for setting ERV wheel power consumption.")
        return false
      end

      # change sizing parameter to vav
      sizing = air_loop_hvac.sizingSystem
      sizing.setCentralCoolingCapacityControlMethod('VAV') # CC-TMP

      # replace any CV terminal box with no reheat VAV terminal box
      # get old terminal box
      if thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctConstantVolumeNoReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolNoReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVNoReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVNoReheat.get
      elsif thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized
        old_terminal = thermal_zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.get
      else
        runner.registerError("Terminal box type for air loop #{air_loop_hvac.name} not supported.")
        return false
      end

      # get design supply air flow rate
      old_terminal_sa_flow_m3_per_s = nil
      if air_loop_hvac.designSupplyAirFlowRate.is_initialized
        old_terminal_sa_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
      elsif air_loop_hvac.isDesignSupplyAirFlowRateAutosized
        old_terminal_sa_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
      else
        runner.registerError("No sizing data available for air loop #{air_loop_hvac.name} zone terminal box.")
      end

      # define minimum flow rate needed to maintain ventilation - add in max fraction if in model
      if controller_oa.maximumFractionofOutdoorAirSchedule.is_initialized
        controller_oa.resetMaximumFractionofOutdoorAirSchedule
      end
      min_oa_flow_ratio = (oa_flow_m3_per_s / old_terminal_sa_flow_m3_per_s)

      # remove old equipment
      old_terminal.remove
      air_loop_hvac.removeBranchForZone(thermal_zone)
      # define new terminal box
      new_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVHeatAndCoolNoReheat.new(model)
      # set name of terminal box and add
      new_terminal.setName("#{thermal_zone.name} VAV Terminal")
      air_loop_hvac.addBranchForZone(thermal_zone, new_terminal.to_StraightComponent)

      # -------------------------------------------------------
      # fan update
      # -------------------------------------------------------
      # add new fan
      new_fan = OpenStudio::Model::FanVariableVolume.new(model, always_on)
      new_fan.setAvailabilitySchedule(supply_fan_avail_sched)
      new_fan.setName("#{air_loop_hvac.name} VFD Fan")
      new_fan.setMotorEfficiency(fan_mot_eff) # from Daikin Rebel E+ file
      new_fan.setFanPowerMinimumFlowRateInputMethod('Fraction')
      std.fan_change_motor_efficiency(new_fan, fan_mot_eff)
      new_fan.setFanPowerCoefficient1(0.259905264) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient2(-1.569867715) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient3(4.819732387) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient4(-3.904544154) # from Daikin Rebel E+ file
      new_fan.setFanPowerCoefficient5(1.394774218) # from Daikin Rebel E+ file

      # set minimum flow rate to 0.40, or higher as needed to maintain outdoor air requirements
      min_flow = 0.40

      # determine minimum airflow ratio for sizing; 0.4 is used unless OA requires higher
      min_airflow_m3_per_s = nil
      current_min_oa_flow_ratio = oa_flow_m3_per_s / old_terminal_sa_flow_m3_per_s
      if current_min_oa_flow_ratio > min_flow
        min_airflow_ratio = current_min_oa_flow_ratio
        min_airflow_m3_per_s = min_airflow_ratio * old_terminal_sa_flow_m3_per_s
      else
        min_airflow_ratio = min_flow
        min_airflow_m3_per_s = min_airflow_ratio * old_terminal_sa_flow_m3_per_s
      end

      # set minimum fan power flow fraction to the higher of 0.40 or the min flow fraction
      if min_airflow_ratio > min_flow
        new_fan.setFanPowerMinimumFlowFraction(min_airflow_ratio)
      else
        new_fan.setFanPowerMinimumFlowFraction(min_flow)
      end
      new_fan.setPressureRise(fan_static_pressure) # set from origial fan power; 0.5in will be added later if adding HR

      # -------------------------------------------------------
      # create coils: cooling
      # -------------------------------------------------------
      # define variable speed cooling coil
      new_dx_cooling_coil = OpenStudio::Model::CoilCoolingDXVariableSpeed.new(model)
      new_dx_cooling_coil.setName("#{air_loop_hvac.name} Heat Pump Cooling Coil")
      new_dx_cooling_coil.setCondenserType('AirCooled')
      new_dx_cooling_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-25)
      new_dx_cooling_coil.setMaximumOutdoorDryBulbTemperatureforCrankcaseHeaterOperation(4.4)
      crankcase_heater_power = ((60 * (orig_clg_coil_gross_cap * 0.0002843451 / 10)**0.67)) # methods from "TECHNICAL SUPPORT DOCUMENT: ENERGY EFFICIENCY PROGRAM FOR CONSUMER PRODUCTS AND COMMERCIAL AND INDUSTRIAL EQUIPMENT AIR-COOLED COMMERCIAL UNITARY AIR CONDITIONERS AND COMMERCIAL UNITARY HEAT PUMPS"
      new_dx_cooling_coil.setCrankcaseHeaterCapacity(crankcase_heater_power)
      new_dx_cooling_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-25)
      new_dx_cooling_coil.setNominalTimeforCondensatetoBeginLeavingtheCoil(1000)
      new_dx_cooling_coil.setInitialMoistureEvaporationRateDividedbySteadyStateACLatentCapacity(1.5)
      new_dx_cooling_coil.setLatentCapacityTimeConstant(45)
      new_dx_cooling_coil.setEnergyPartLoadFractionCurve(cool_plf_fplr1)

      # define rated to lower stage ratios: low, medium, high stages
      stage_ratios = [0.333, 0.666, 1.0]

      # loop through stages
      stage_ratios.sort.each_with_index do |ratio, index|
        # convert index to stage number
        stage = index + 1

        # calculate reference capacity
        if stage == 3
          reference_capacity_w = orig_clg_coil_gross_cap
          reference_capacity_m_3_per_s = orig_clg_coil_rated_airflow_m_3_per_s
        else
          reference_capacity_w = orig_clg_coil_gross_cap * ratio
          reference_capacity_m_3_per_s = orig_clg_coil_rated_airflow_m_3_per_s * ratio
        end
        if debug_verbose
          runner.registerInfo('--- stage {} | reference_capacity_w = {}'.format(stage, reference_capacity_w))
          runner.registerInfo('--- stage {} | reference_capacity_m_3_per_s = {}'.format(stage, reference_capacity_m_3_per_s))
        end

        # add speed data for each stage
        dx_coil_speed_data = OpenStudio::Model::CoilCoolingDXVariableSpeedSpeedData.new(model)
        dx_coil_speed_data.setReferenceUnitGrossRatedTotalCoolingCapacity(reference_capacity_w)
        dx_coil_speed_data.setReferenceUnitRatedAirFlowRate(orig_clg_coil_rated_airflow_m_3_per_s)
        dx_coil_speed_data.setReferenceUnitGrossRatedSensibleHeatRatio(stage_gross_rated_sensible_heat_ratio_cooling[applied_stage])
        dx_coil_speed_data.setReferenceUnitGrossRatedCoolingCOP(get_rated_cop_cooling_adv(reference_capacity_w))
        dx_coil_speed_data.setRatedEvaporatorFanPowerPerVolumeFlowRate2017(773.3)
        dx_coil_speed_data.setTotalCoolingCapacityFunctionofTemperatureCurve(
          model_add_curve(
            model,
            get_curve_object(runner, 'capacity_fn_of_t', reference_capacity, stage, debug_verbose),
            combine_all_performance_curves,
            std
          )
        )
        dx_coil_speed_data.setTotalCoolingCapacityFunctionofAirFlowFractionCurve(
          model_add_curve(
            model,
            get_curve_object(runner, 'capacity_fn_of_ff', reference_capacity, stage, debug_verbose),
            combine_all_performance_curves,
            std
          )
        )
        dx_coil_speed_data.setEnergyInputRatioFunctionofTemperatureCurve(
          model_add_curve(
            model,
            get_curve_object(runner, 'eir_fn_of_t', reference_capacity, stage, debug_verbose),
            combine_all_performance_curves,
            std
          )
        )
        dx_coil_speed_data.setEnergyInputRatioFunctionofAirFlowFractionCurve(
          model_add_curve(
            model,
            get_curve_object(runner, 'eir_fn_of_ff', reference_capacity, stage, debug_verbose),
            combine_all_performance_curves,
            std
          )
        )

        # add speed data to variable speed coil object
        new_dx_cooling_coil.addSpeed(dx_coil_speed_data)
      end

      # -------------------------------------------------------
      # create coils: heating
      # -------------------------------------------------------

      # -------------------------------------------------------
      # create coils: backup heating
      # -------------------------------------------------------
      # add new supplemental heating coil
      new_backup_heating_coil = nil
      # define backup heat source TODO: set capacity to equal full heating capacity
      if (prim_ht_fuel_type == 'electric') || (backup_ht_fuel_scheme == 'electric_resistance_backup')
        new_backup_heating_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
        new_backup_heating_coil.setEfficiency(1.0)
        new_backup_heating_coil.setName("#{air_loop_hvac.name} electric resistance backup coil")
      else
        new_backup_heating_coil = OpenStudio::Model::CoilHeatingGas.new(model)
        new_backup_heating_coil.setGasBurnerEfficiency(0.80)
        new_backup_heating_coil.setName("#{air_loop_hvac.name} gas backup coil")
      end
      # set availability schedule
      new_backup_heating_coil.setAvailabilitySchedule(always_on)
      # set capacity of backup heat to meet full heating load
      new_backup_heating_coil.setNominalCapacity(orig_htg_coil_gross_cap)

      # -------------------------------------------------------
      # unitary system update
      # -------------------------------------------------------
      # add new unitary system object
      new_rtu = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      new_rtu.setName("#{air_loop_hvac.name} Unitary high-efficiency System")
      new_rtu.setSupplyFan(new_fan)
      new_rtu.setHeatingCoil(new_dx_heating_coil)
      new_rtu.setCoolingCoil(new_dx_cooling_coil)
      new_rtu.setSupplementalHeatingCoil(new_backup_heating_coil)
      new_rtu.addToNode(air_loop_hvac.supplyOutletNode)

      # set other features
      new_rtu.setControllingZoneorThermostatLocation(control_zone)
      new_rtu.setFanPlacement('DrawThrough')
      new_rtu.setAvailabilitySchedule(unitary_availability_sched)
      new_rtu.setDehumidificationControlType(dehumid_type)
      new_rtu.setSupplyAirFanOperatingModeSchedule(supply_fan_op_sched)
      new_rtu.setControlType('Load')
      new_rtu.setName("#{thermal_zone.name} RTU SZ-VAV high-efficiency")
      new_rtu.setMaximumSupplyAirTemperature(50)
      new_rtu.setDXHeatingCoilSizingRatio(1 + performance_oversizing_factor)

      # handle deprecated methods for OS Version 3.7.0
      if model.version < OpenStudio::VersionString.new('3.7.0')
        # set no load design flow rate
        new_rtu.resetSupplyAirFlowRateMethodWhenNoCoolingorHeatingisRequired
      end
      # set cooling design flow rate
      new_rtu.setSupplyAirFlowRateDuringCoolingOperation(stage_flows_cooling[num_cooling_stages])
      # set heating design flow rate
      new_rtu.setSupplyAirFlowRateDuringHeatingOperation(stage_flows_heating[num_heating_stages])
      # set no load design flow rate
      new_rtu.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(min_airflow_m3_per_s)

      # -------------------------------------------------------
      # DCV update
      # -------------------------------------------------------
      # add dcv to air loop if dcv flag is true
      if dcv == true
        oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
        controller_oa = oa_system.getControllerOutdoorAir
        controller_mv = controller_oa.controllerMechanicalVentilation
        controller_mv.setDemandControlledVentilation(true)
      end

      # -------------------------------------------------------
      # E/HRV update
      # -------------------------------------------------------
      # Energy recovery
      # check for ERV, and get components
      # ERV components will be removed and replaced if ERV flag was selected
      # If ERV flag was not selected, ERV equipment will remain in place as-is
      erv_components = []
      air_loop_hvac.oaComponents.each do |component|
        component_name = component.name.to_s
        next if component_name.include? 'Node'

        if component_name.include? 'ERV'
          erv_components << component
          erv_components = erv_components.uniq
        end
      end

      # add energy recovery if specified by user and if the building type is applicable
      next unless (hr == true) && (btype_erv_applicable == true)

      # check for space type applicability
      thermal_zone_names_to_exclude = ['Kitchen', 'kitchen', 'KITCHEN', 'Dining', 'dining', 'DINING']
      # skip air loops that serve non-applicable space types and warn user
      if thermal_zone_names_to_exclude.any? { |word| thermal_zone.name.to_s.include?(word) }
        runner.registerWarning("The user selected to add energy recovery to the HP-RTUs, but thermal zone #{thermal_zone.name} is a non-applicable space type for energy recovery. Any existing energy recovery will remain for consistancy, but no new energy recovery will be added.")
      else
        # remove existing ERV; these will be replaced with new ERV equipment
        erv_components.each(&:remove)
        # get oa system
        oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
        std.air_loop_hvac_apply_energy_recovery_ventilator(air_loop_hvac, climate_zone)
        # set heat exchanger efficiency levels
        # get outdoor airflow (which is used for sizing)
        oa_sys = oa_sys.get
        # get design outdoor air flow rate
        # this is used to estimate wheel "fan" power
        # loop through thermal zones
        oa_flow_m3_per_s = 0
        air_loop_hvac.thermalZones.each do |tz|
          space = tz.spaces[0]

          # get zone area
          fa = tz.floorArea * tz.multiplier

          # get zone volume
          vol = tz.airVolume * tz.multiplier

          # get zone design people
          num_people = tz.numberOfPeople * tz.multiplier

          next unless space.designSpecificationOutdoorAir.is_initialized

          dsn_spec_oa = space.designSpecificationOutdoorAir.get

          # add floor area component
          oa_area = dsn_spec_oa.outdoorAirFlowperFloorArea
          oa_flow_m3_per_s += oa_area * fa

          # add per person component
          oa_person = dsn_spec_oa.outdoorAirFlowperPerson
          oa_flow_m3_per_s += oa_person * num_people

          # add air change component
          oa_ach = dsn_spec_oa.outdoorAirFlowAirChangesperHour
          oa_flow_m3_per_s += (oa_ach * vol) / 60
        end

        oa_sys.oaComponents.each do |oa_comp|
          next unless oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized

          hx = oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.get
          # set controls
          hx.setSupplyAirOutletTemperatureControl(true)
          hx.setEconomizerLockout(true)
          hx.setFrostControlType('MinimumExhaustTemperature')
          hx.setThresholdTemperature(1.66667) # 35F, from E+ recommendation
          hx.setHeatExchangerType('Rotary') # rotary is used for fan power modulation when bypass is active. Only affects supply temp control with bypass.
          # add setpoint manager to control recovery
          # Add a setpoint manager OA pretreat to control the ERV
          spm_oa_pretreat = OpenStudio::Model::SetpointManagerOutdoorAirPretreat.new(air_loop_hvac.model)
          spm_oa_pretreat.setMinimumSetpointTemperature(-99.0)
          spm_oa_pretreat.setMaximumSetpointTemperature(99.0)
          spm_oa_pretreat.setMinimumSetpointHumidityRatio(0.00001)
          spm_oa_pretreat.setMaximumSetpointHumidityRatio(1.0)
          # Reference setpoint node and mixed air stream node are outlet node of the OA system
          mixed_air_node = oa_sys.mixedAirModelObject.get.to_Node.get
          spm_oa_pretreat.setReferenceSetpointNode(mixed_air_node)
          spm_oa_pretreat.setMixedAirStreamNode(mixed_air_node)
          # Outdoor air node is the outboard OA node of the OA system
          spm_oa_pretreat.setOutdoorAirStreamNode(oa_sys.outboardOANode.get)
          # Return air node is the inlet node of the OA system
          return_air_node = oa_sys.returnAirModelObject.get.to_Node.get
          spm_oa_pretreat.setReturnAirStreamNode(return_air_node)
          # Attach to the outlet of the HX
          hx_outlet = hx.primaryAirOutletModelObject.get.to_Node.get
          spm_oa_pretreat.addToNode(hx_outlet)

          # set parameters for ERV
          case doas_type
          when 'ERV'
            # set efficiencies; assumed 90% airflow returned to unit
            hx.setSensibleEffectivenessat100HeatingAirFlow(0.75 * 0.9)
            hx.setSensibleEffectivenessat75HeatingAirFlow(0.78 * 0.9)
            hx.setLatentEffectivenessat100HeatingAirFlow(0.61 * 0.9)
            hx.setLatentEffectivenessat75HeatingAirFlow(0.68 * 0.9)
            hx.setSensibleEffectivenessat100CoolingAirFlow(0.75 * 0.9)
            hx.setSensibleEffectivenessat75CoolingAirFlow(0.78 * 0.9)
            hx.setLatentEffectivenessat100CoolingAirFlow(0.55 * 0.9)
            hx.setLatentEffectivenessat75CoolingAirFlow(0.60 * 0.9)
          # set parameters for HRV
          when 'HRV'
            # set efficiencies; assumed 90% airflow returned to unit
            hx.setSensibleEffectivenessat100HeatingAirFlow(0.84 * 0.9)
            hx.setSensibleEffectivenessat75HeatingAirFlow(0.86 * 0.9)
            hx.setLatentEffectivenessat100HeatingAirFlow(0)
            hx.setLatentEffectivenessat75HeatingAirFlow(0)
            hx.setSensibleEffectivenessat100CoolingAirFlow(0.83 * 0.9)
            hx.setSensibleEffectivenessat75CoolingAirFlow(0.84 * 0.9)
            hx.setLatentEffectivenessat100CoolingAirFlow(0)
            hx.setLatentEffectivenessat75CoolingAirFlow(0)
          end

          # fan efficiency ranges from 40-60% (Energy Modeling Guide for Very High Efficiency DOAS Final Report)
          default_fan_efficiency = 0.55
          power = (oa_flow_m3_per_s * 174.188 / default_fan_efficiency) + ((oa_flow_m3_per_s * 0.9 * 124.42) / default_fan_efficiency)
          hx.setNominalElectricPower(power)
        end
      end
    end

    # report final condition of model
    condition_final_hprtu = "The building finished with high-efficiency RTUs replacing the HVAC equipment for #{selected_air_loops.size} air loops."
    condition_final = [condition_final_hprtu, condition_final_roof, condition_final_window].reject(&:empty?).join(' | ')
    runner.registerFinalCondition(condition_final)

    true
  end
end

# register the measure to be used by the application
UpgradeHvacRtuAdv.new.registerWithApplication
