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

require 'openstudio-standards'

# start the measure
class ComStockSensitivityReports < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'ComStock_Sensitivity_Reports'
  end

  # human readable description
  def description
    return 'In order to train the surrogate model for ComStock, we need to have more summary information about the
            building in the output csv.  Characteristics like whole-bldg avg. U-value for walls, roofs, windows, etc,
            whole-bldg LPD and EPD, avg. htg. eff/clg COP.  Mainly things that are not direct inputs to the model, but
            that are a byproduct of the other inputs.  Also, the focus should be on things that are common across
            building types, as opposed to very building-type-specific characteristics.'
  end

  # human readable description of modeling approach
  def modeler_description
    return "WARNING: This measure puts in output variables with reporting frequency 'RunPeriod'.
            Make sure 'Run Simulation for Sizing Periods' is set to 'false' in 'OS:SimulationControl'."
  end

  # define the arguments that the user will input
  def arguments
    args = OpenStudio::Measure::OSArgumentVector.new
    # this measure does not require any user arguments, return an empty list
    return args
  end

  # define the outputs that the measure will create
  def outputs
    outs = OpenStudio::Measure::OSOutputVector.new
    # this measure does not produce machine readable outputs with registerValue, return an empty list
    return outs
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  # Warning: Do not change the name of this method to be snake_case. The method must be lowerCamelCase.
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return result
    end

    result = OpenStudio::IdfObjectVector.new

    # request zone variables for the run period
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Electric Equipment Electric Energy,RunPeriod;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone People Occupant Count,RunPeriod;').get

    # request service water heating use
    result << OpenStudio::IdfObject.load('Output:Variable,*,Water Use Connections Hot Water Volume,RunPeriod;').get

    # request coil and fan energy use for HVAC equipment
    result << OpenStudio::IdfObject.load('Output:Variable,*,Chiller COP,RunPeriod;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Chiller Evaporator Cooling Energy,RunPeriod;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Heating Coil Electric Energy,RunPeriod;').get # J
    result << OpenStudio::IdfObject.load('Output:Variable,*,Cooling Coil Electric Energy,RunPeriod;').get # J
    result << OpenStudio::IdfObject.load('Output:Variable,*,Heating Coil Heating Energy,RunPeriod;').get # J
    result << OpenStudio::IdfObject.load('Output:Variable,*,Cooling Coil Total Cooling Energy,RunPeriod;').get # J
    result << OpenStudio::IdfObject.load('Output:Variable,*,Air System Outdoor Air Flow Fraction,RunPeriod;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Air System Mixed Air Mass Flow Rate,RunPeriod;').get # kg/s

    #result << OpenStudio::IdfObject.load('Output:Variable,*,Fan Electric Energy,RunPeriod;').get # J
    #result << OpenStudio::IdfObject.load('Output:Variable,*,Humidifier Electric Energy,RunPeriod;').get # J
    #result << OpenStudio::IdfObject.load('Output:Variable,*,Evaporative Cooler Electric Energy,RunPeriod;').get # J
    #result << OpenStudio::IdfObject.load('Output:Variable,*,Baseboard Hot Water Energy,RunPeriod;').get # J
    #result << OpenStudio::IdfObject.load('Output:Variable,*,Baseboard Electric Energy,RunPeriod;').get # J

    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return false
    end

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    sql = runner.lastEnergyPlusSqlFile
    if sql.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sql = sql.get
    model.setSqlFile(sql)

    # get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
        end
      end
    end

    if ann_env_pd == false
      runner.registerError('Cannot find a weather runperiod. Make sure you ran an annual simulation, not just the design days.')
      return false
    end

    # build standard to access methods
    std = Standard.build('ComStock 90.1-2013')

    # calculate exterior surface properties
    # TODO may need to adjust for zone multipliers
    roof_absorptance_times_area = 0
    roof_ua_si = 0.0
    roof_area_m2 = 0.0
    exterior_wall_ua_si = 0.0
    exterior_wall_area_m2 = 0.0
    model.getSpaces.sort.each do |space|
      space.surfaces.each do |surface|
        next if surface.outsideBoundaryCondition != 'Outdoors'
        if surface.surfaceType.to_s == 'RoofCeiling'
          surface_absorptance = surface.exteriorVisibleAbsorptance.is_initialized ? surface.exteriorVisibleAbsorptance.get : 0.0
          surface_u_value_si = surface.uFactor.is_initialized ? surface.uFactor.get : 0.0
          surface_area_m2 = surface.netArea
          surface_ua_si = surface_u_value_si * surface_area_m2
          roof_absorptance_times_area += surface_absorptance * surface_area_m2
          roof_ua_si += surface_ua_si
          roof_area_m2 += surface_area_m2
        elsif surface.surfaceType.to_s == 'Wall'
          surface_u_value_si = surface.uFactor.is_initialized ? surface.uFactor.get : 0.0
          surface_area_m2 = surface.netArea
          surface_ua_si = surface_u_value_si * surface_area_m2
          exterior_wall_ua_si += surface_ua_si
          exterior_wall_area_m2 += surface_area_m2
        end
      end
    end

    # Average roof absorptance
    if roof_area_m2 > 0
      average_roof_absorptance = roof_absorptance_times_area / roof_area_m2
      runner.registerValue('com_report_average_roof_absorptance', average_roof_absorptance)
    else
      runner.registerWarning('Roof area is zero. Cannot calculate average absorptance.')
    end

    # Average roof U-value
    if roof_area_m2 > 0
      average_roof_u_value_si = roof_ua_si / roof_area_m2
      runner.registerValue('com_report_average_roof_u_value_si', average_roof_u_value_si)
    else
      runner.registerWarning('Roof area is zero. Cannot calculate average U-value.')
    end

    # Average wall U-value
    if exterior_wall_area_m2 > 0
      average_exterior_wall_u_value_si = exterior_wall_ua_si / exterior_wall_area_m2
      runner.registerValue('com_report_average_exterior_wall_u_value_si', average_exterior_wall_u_value_si)
    else
      runner.registerWarning('Exterior wall area is zero. Cannot calculate average U-value.')
    end

    # Average window area
    window_area_m2 = 0
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'EnvelopeSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Exterior Fenestration' AND RowName = 'Total or Average' AND ColumnName = 'Area of Multiplied Openings' AND Units = 'm2'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      window_area_m2 = val.get
      # runner.registerValue('com_report_window_area_m2', window_area_m2, 'm^2')
    else
      runner.registerWarning('Overall window area not available.')
    end

    # Average window U-value
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'EnvelopeSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Exterior Fenestration' AND RowName = 'Total or Average' AND ColumnName = 'Glass U-Factor' AND Units = 'W/m2-K'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      window_u_value_si = val.get
      runner.registerValue('com_report_window_u_value_si', window_u_value_si, 'W/m^2*K')
    else
      runner.registerWarning('Overall average window U-value not available.')
    end

    # Average window SHGC
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'EnvelopeSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Exterior Fenestration' AND RowName = 'Total or Average' AND ColumnName = 'Glass SHGC'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      window_shgc = val.get
      runner.registerValue('com_report_window_shgc', window_shgc)
    else
      runner.registerWarning('Overall average window SHGC not available.')
    end

    # Building window to wall ratio
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'InputVerificationandResultsSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Window-Wall Ratio' AND RowName = 'Gross Window-Wall Ratio' AND ColumnName = 'Total'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      wwr = val.get / 100.0
      runner.registerValue('com_report_wwr', wwr)
    else
      runner.registerWarning('Overall window to wall ratio not available.')
    end

    # Interior mass surface area
    internal_mass_area_m2 = 0.0
    total_space_area_m2 = 0.0
    model.getInternalMasss.each do |mass|
      space = mass.space.get
      space_area_m2 = space.floorArea
      num_people = space.numberOfPeople
      surface_area_m2 = mass.surfaceArea.is_initialized ? mass.surfaceArea.get : 0.0
      surface_area_per_floor_area_m2 = mass.surfaceAreaPerFloorArea.is_initialized ? mass.surfaceAreaPerFloorArea.get : 0.0
      surface_area_per_person_m2 = mass.surfaceAreaPerPerson.is_initialized ? mass.surfaceAreaPerPerson.get : 0.0
      internal_mass_area_m2 += surface_area_m2 + surface_area_per_floor_area_m2 * space_area_m2 + surface_area_per_person_m2 * num_people
      total_space_area_m2 += space_area_m2
    end
    internal_mass_area_ratio = total_space_area_m2 > 0.0 ? internal_mass_area_m2 / total_space_area_m2 : 0.0
    runner.registerValue('com_report_internal_mass_area_ratio', internal_mass_area_ratio)

    # Daylight control space fraction
    weighted_daylight_control_area_m2 = 0.0
    total_zone_area_m2 = 0.0
    model.getThermalZones.each do |zone|
      zone_area_m2 = zone.floorArea
      primary_fraction = zone.primaryDaylightingControl.is_initialized ? zone.fractionofZoneControlledbyPrimaryDaylightingControl : 0.0
      secondary_fraction = zone.secondaryDaylightingControl.is_initialized ? zone.fractionofZoneControlledbySecondaryDaylightingControl : 0.0
      total_fraction = (primary_fraction + secondary_fraction) > 1.0 ? 1.0 : (primary_fraction + secondary_fraction)
      weighted_daylight_control_area_m2 += total_fraction * zone_area_m2
      total_zone_area_m2 += zone_area_m2
    end
    daylight_control_fraction = total_zone_area_m2 > 0.0 ? weighted_daylight_control_area_m2 / total_zone_area_m2 : 0.0
    runner.registerValue('com_report_daylight_control_fraction', daylight_control_fraction)

    # Exterior lighting power
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'LightingSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Exterior Lighting' AND RowName = 'Exterior Lighting Total' AND ColumnName = 'Total Watts'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      exterior_lighting_power_w = sql.execAndReturnFirstDouble(var_val_query).get
      runner.registerValue('com_report_exterior_lighting_power_w', exterior_lighting_power_w, 'W')
    else
      runner.registerWarning('Total exterior lighting power not available.')
    end

    # Elevator energy use
    elevator_energy_use_gj = 0.0
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'EnergyMeters' AND RowName = 'Elevators:InteriorEquipment:Electricity' AND ColumnName = 'Electricity Annual Value' AND Units = 'GJ'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      elevator_energy_use_gj = val.get
    else
      runner.registerWarning('Annual elevator energy use not available.')
    end
    runner.registerValue('com_report_elevator_energy_use_gj', elevator_energy_use_gj, 'GJ')

    # Average interior lighting power density
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'LightingSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Interior Lighting' AND RowName = 'Interior Lighting Total' AND ColumnName = 'Lighting Power Density' AND Units = 'W/m2'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      interior_lighting_power_density_w_per_m2 = val.get
      runner.registerValue('com_report_interior_lighting_power_density_w_per_m2', interior_lighting_power_density_w_per_m2, 'W/m^2')
    else
      runner.registerWarning('Average interior lighting power density not available.')
    end

    # Average interior lighting equivalent full load hours
    interior_lighting_total_power_w = 0
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'LightingSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Interior Lighting' AND RowName = 'Interior Lighting Total' AND ColumnName = 'Total Power' AND Units = 'W'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      interior_lighting_total_power_w = val.get
      # runner.registerValue('com_report_interior_lighting_total_power_w', interior_lighting_total_power_w, 'W')
    else
      runner.registerWarning('Interior lighting power not available.')
    end

    interior_lighting_consumption_gj = 0
    var_val_query = "SELECT Value FROM TabularDataWithStrings WHERE ReportName = 'LightingSummary' AND ReportForString = 'Entire Facility' AND TableName = 'Interior Lighting' AND RowName = 'Interior Lighting Total' AND ColumnName = 'Consumption' AND Units = 'GJ'"
    val = sql.execAndReturnFirstDouble(var_val_query)
    if val.is_initialized
      interior_lighting_consumption_gj = val.get
      # runner.registerValue('com_report_interior_lighting_consumption_gj', interior_lighting_consumption_gj, 'GJ')
    else
      runner.registerWarning('Interior lighting consumption not available.')
    end

    if interior_lighting_total_power_w > 0
      interior_lighting_eflh = (interior_lighting_consumption_gj * 1e9) / (interior_lighting_total_power_w * 3600.0)
      runner.registerValue('com_report_interior_lighting_eflh', interior_lighting_eflh, 'hr')
    else
      runner.registerWarning('Interior lighting power is not available; cannot calculate equivalent full load hours.')
    end

    # Interior electric equipment calculations
    total_zone_electric_equipment_area_m2 = 0.0
    total_zone_electric_equipment_power_w = 0.0
    total_zone_electric_equipment_energy_gj = 0
    model.getThermalZones.sort.each do |zone|
      # get design plug load power
      zone_electric_equipment_power_w = 0.0
      floor_area_m2 = 0.0
      space_type = std.thermal_zone_majority_space_type(zone)
      if space_type.is_initialized
        space_type = space_type.get
        floor_area_m2 = zone.floorArea
        num_people = zone.numberOfPeople
        equip_w = space_type.getElectricEquipmentDesignLevel(floor_area_m2, num_people)
        equip_per_area_w = space_type.getElectricEquipmentPowerPerFloorArea(floor_area_m2, num_people) * floor_area_m2
        equip_per_person_w = num_people > 0.0 ? space_type.getElectricEquipmentPowerPerPerson(floor_area_m2, num_people) * num_people : 0.0
        zone_electric_equipment_power_w = equip_w + equip_per_area_w + equip_per_person_w
      else
        runner.registerWarning("Unable to determine majority space type for zone '#{zone.name}'.")
      end

      # skip zones with no plug loads; this will skip zones with equipment defined only at space instance level
      next if zone_electric_equipment_power_w == 0.0
      total_zone_electric_equipment_area_m2 += floor_area_m2
      total_zone_electric_equipment_power_w += zone_electric_equipment_power_w

      # get zone electric equipment energy (may include kitchen or elevator equipment)
      zone_electric_equipment_energy_gj = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Zone Electric Equipment Electric Energy' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{zone.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          zone_electric_equipment_energy_gj = val.get
        else
          runner.registerWarning("'Zone Electric Equipment Electric Energy' not available for zone '#{zone.name}'.")
        end
      else
        runner.registerWarning("'Zone Electric Equipment Electric Energy' not available for zone '#{zone.name}'.")
      end
      total_zone_electric_equipment_energy_gj += zone_electric_equipment_energy_gj
    end

    # Average plug load power density
    interior_electric_equipment_power_density_w_per_m2 = total_zone_electric_equipment_area_m2 > 0.0 ? total_zone_electric_equipment_power_w / total_zone_electric_equipment_area_m2 : 0.0
    runner.registerValue('com_report_interior_electric_equipment_power_density_w_per_m2', interior_electric_equipment_power_density_w_per_m2, 'W/m^2')

    # Average plug load equivalent full load hours (EPD*area*8760 / annual energy use)
    if total_zone_electric_equipment_power_w > 0
      interior_electric_equipment_eflh = (total_zone_electric_equipment_energy_gj * 1e9) / (total_zone_electric_equipment_power_w * 3600.0)
      runner.registerValue('com_report_interior_electric_equipment_eflh', interior_electric_equipment_eflh, 'hr')
    else
      runner.registerWarning('Interior electric equipment power is not available; cannot calculate equivalent full load hours.')
    end

    # Occupant calculations
    total_zone_occupant_area_m2 = 0.0
    total_zone_design_ppl = 0.0
    total_zone_ppl_count = 0
    model.getThermalZones.sort.each do |zone|
      total_zone_occupant_area_m2 += zone.floorArea
      total_zone_design_ppl += zone.numberOfPeople
      zone_ppl_count = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Zone People Occupant Count' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{zone.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          zone_ppl_count = val.get
        else
          runner.registerWarning("'Zone People Occupant Count' not available for zone '#{zone.name}'.")
        end
      else
        runner.registerWarning("'Zone People Occupant Count' not available for zone '#{zone.name}'.")
      end
      total_zone_ppl_count += zone_ppl_count
    end

    # Average occupant density
    occupant_density_ppl_per_m2 = total_zone_occupant_area_m2 > 0.0 ? total_zone_design_ppl / total_zone_occupant_area_m2 : 0.0
    runner.registerValue('com_report_occupant_density_ppl_per_m2', occupant_density_ppl_per_m2, '1/m^2')

    # Average occupant equivalent full load hours
    if total_zone_design_ppl > 0
      occupant_eflh = (total_zone_ppl_count / total_zone_design_ppl) * 8760.0
      runner.registerValue('com_report_occupant_eflh', occupant_eflh, 'hr')
    else
      runner.registerWarning('Zone occupancy is not available; cannot calculate equivalent full load hours.')
    end

    # Design outdoor air flow rate
    total_design_outdoor_air_flow_rate_m3_per_s = 0.0
    design_outdoor_air_flow_rate_area_m2 = 0.0
    model.getThermalZones.each do |zone|
      zone.spaces.each do |space|
        next unless space.designSpecificationOutdoorAir.is_initialized
        dsn_oa = space.designSpecificationOutdoorAir.get

        # get the space properties
        floor_area_m2 = space.floorArea
        number_of_people = space.numberOfPeople
        volume_m3 = space.volume

        # get outdoor air values
        oa_for_people = number_of_people * dsn_oa.outdoorAirFlowperPerson
        oa_for_floor_area = floor_area_m2 * dsn_oa.outdoorAirFlowperFloorArea
        oa_rate = dsn_oa.outdoorAirFlowRate
        oa_for_volume = volume_m3 * dsn_oa.outdoorAirFlowAirChangesperHour / 3600.0

        # determine total outdoor air
        if dsn_oa.outdoorAirMethod == 'Maximum'
          tot_oa_m3_per_s = [oa_for_people, oa_for_floor_area, oa_rate, oa_for_volume].max
        else
          tot_oa_m3_per_s = oa_for_people + oa_for_floor_area + oa_rate + oa_for_volume
        end

        total_design_outdoor_air_flow_rate_m3_per_s += tot_oa_m3_per_s
        design_outdoor_air_flow_rate_area_m2 += floor_area_m2
      end
    end
    design_outdoor_air_flow_rate_m3_per_m2s = design_outdoor_air_flow_rate_area_m2 > 0.0 ? total_design_outdoor_air_flow_rate_m3_per_s / design_outdoor_air_flow_rate_area_m2 : 0.0
    runner.registerValue('com_report_design_outdoor_air_flow_rate_m3_per_m2s', design_outdoor_air_flow_rate_m3_per_m2s, 'm/s')

    # Air system outdoor air flow fraction
    # Air system fan properties
    air_system_weighted_oa_frac = 0.0
    air_system_total_mass_flow_kg_s = 0.0
    air_system_weighted_fan_power_minimum_flow_fraction = 0.0
    air_system_weighted_fan_static_pressure = 0.0
    air_system_weighted_fan_efficiency = 0.0
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      # get Air System Outdoor Air Flow Fraction
      air_loop_oa_fraction = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Air System Outdoor Air Flow Fraction' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{air_loop_hvac.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          air_loop_oa_fraction = val.get
        else
          runner.registerWarning("'Air System Outdoor Air Flow Fraction' not available for air loop hvac '#{air_loop_hvac.name}'.")
        end
      else
        runner.registerWarning("'Air System Outdoor Air Flow Fraction' not available for air loop hvac '#{air_loop_hvac.name}'.")
      end

      # get Air System Mixed Air Mass Flow Rate
      air_loop_mass_flow_rate_kg_s = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Air System Mixed Air Mass Flow Rate' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{air_loop_hvac.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          air_loop_mass_flow_rate_kg_s = val.get
        else
          runner.registerWarning("'Air System Mixed Air Mass Flow Rate' not available for air loop hvac '#{air_loop_hvac.name}'.")
        end
      else
        runner.registerWarning("'Air System Mixed Air Mass Flow Rate' not available for air loop hvac '#{air_loop_hvac.name}'.")
      end

      fan_minimum_flow_frac = 0.0
      fan_static_pressure = 0.0
      fan_efficiency = 0.0
      supply_fan = air_loop_hvac.supplyFan
      if supply_fan.is_initialized
        supply_fan = supply_fan.get
        if supply_fan.to_FanOnOff.is_initialized
          supply_fan = supply_fan.to_FanOnOff.get
          fan_minimum_flow_frac = 1.0
          fan_static_pressure = supply_fan.pressureRise
          fan_efficiency = supply_fan.fanTotalEfficiency
        elsif supply_fan.to_FanConstantVolume.is_initialized
          supply_fan = supply_fan.to_FanConstantVolume.get
          fan_minimum_flow_frac = 1.0
          fan_static_pressure = supply_fan.pressureRise
          fan_efficiency = supply_fan.fanTotalEfficiency
        elsif supply_fan.to_FanVariableVolume.is_initialized
          supply_fan = supply_fan.to_FanVariableVolume.get
          fan_minimum_flow_frac = supply_fan.fanPowerMinimumFlowFraction
          fan_static_pressure = supply_fan.pressureRise
          fan_efficiency = supply_fan.fanTotalEfficiency
        else
           runner.registerWarning("Supply Fan type not recognized for air loop hvac '#{air_loop_hvac.name}'.")
        end
      else
        runner.registerWarning("Supply Fan not available for air loop hvac '#{air_loop_hvac.name}'.")
      end

      # add to weighted
      air_system_total_mass_flow_kg_s += air_loop_mass_flow_rate_kg_s
      air_system_weighted_oa_frac += air_loop_oa_fraction * air_loop_mass_flow_rate_kg_s
      air_system_weighted_fan_power_minimum_flow_fraction += fan_minimum_flow_frac * air_loop_mass_flow_rate_kg_s
      air_system_weighted_fan_static_pressure += fan_static_pressure * air_loop_mass_flow_rate_kg_s
      air_system_weighted_fan_efficiency += fan_efficiency * air_loop_mass_flow_rate_kg_s
    end
    average_outdoor_air_fraction = air_system_total_mass_flow_kg_s > 0.0 ? air_system_weighted_oa_frac / air_system_total_mass_flow_kg_s : 0.0
    runner.registerValue('com_report_average_outdoor_air_fraction', average_outdoor_air_fraction)
    air_system_fan_power_minimum_flow_fraction = air_system_total_mass_flow_kg_s > 0.0 ? air_system_weighted_fan_power_minimum_flow_fraction / air_system_total_mass_flow_kg_s : 0.0
    runner.registerValue('com_report_air_system_fan_power_minimum_flow_fraction', air_system_fan_power_minimum_flow_fraction)
    air_system_fan_static_pressure = air_system_total_mass_flow_kg_s > 0.0 ? air_system_weighted_fan_static_pressure / air_system_total_mass_flow_kg_s : 0.0
    runner.registerValue('com_report_air_system_fan_static_pressure', air_system_fan_static_pressure ,'Pa')
    air_system_fan_total_efficiency = air_system_total_mass_flow_kg_s > 0.0 ? air_system_weighted_fan_efficiency / air_system_total_mass_flow_kg_s : 0.0
    runner.registerValue('com_report_air_system_fan_total_efficiency', air_system_fan_total_efficiency)

    # Zone HVAC properties
    zone_hvac_fan_total_air_flow_m3_per_s = 0.0
    zone_hvac_weighted_fan_power_minimum_flow_fraction = 0.0
    zone_hvac_weighted_fan_static_pressure = 0.0
    zone_hvac_weighted_fan_efficiency = 0.0
    model.getZoneHVACComponents.each do |zone_hvac_component|
      # Convert this to the actual class type
      has_fan = true
      if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
      elsif zone_hvac_component.to_ZoneHVACUnitHeater.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACUnitHeater.get
      elsif zone_hvac_component.to_ZoneHVACUnitVentilator.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACUnitVentilator.get
      elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
      elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
      elsif zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
      elsif zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.is_initialized
        zone_hvac =  zone_hvac_component.to_ZoneHVACWaterToAirHeatPump.get
      elsif zone_hvac_component.to_ZoneHVACEnergyRecoveryVentilator.is_initialized
        zone_hvac = zone_hvac_component.to_ZoneHVACEnergyRecoveryVentilator.get
      elsif zone_hvac_component.to_ZoneHVACBaseboardConvectiveElectric.is_initialized
        zone_hvac = zone_hvac_component.to_ZoneHVACBaseboardConvectiveElectric.get
        has_fan = false
      elsif zone_hvac_component.to_ZoneHVACBaseboardConvectiveWater.is_initialized
        zone_hvac = zone_hvac_component.to_ZoneHVACBaseboardConvectiveWater.get
        has_fan = false
      elsif zone_hvac_component.to_ZoneHVACBaseboardRadiantConvectiveElectric.is_initialized
        zone_hvac = zone_hvac_component.to_ZoneHVACBaseboardRadiantConvectiveElectric.get
        has_fan = false
      elsif zone_hvac_component.to_ZoneHVACBaseboardRadiantConvectiveWater.is_initialized
        zone_hvac = zone_hvac_component.to_ZoneHVACBaseboardRadiantConvectiveWater.get
        has_fan = false
      else
        runner.registerWarning("Zone HVAC equipment '#{zone_hvac_component.name}' type is not supported in this reporting measure.")
        next
      end

      # Get fan properties
      if has_fan
        if zone_hvac.supplyAirFan.to_FanOnOff.is_initialized
          supply_fan = zone_hvac.supplyAirFan.to_FanOnOff.get
          fan_minimum_flow_frac = 1.0
          fan_static_pressure = supply_fan.pressureRise
          fan_efficiency = supply_fan.fanTotalEfficiency
        elsif zone_hvac.supplyAirFan.to_FanConstantVolume.is_initialized
          supply_fan = zone_hvac.supplyAirFan.to_FanConstantVolume.get
          fan_minimum_flow_frac = 1.0
          fan_static_pressure = supply_fan.pressureRise
          fan_efficiency = supply_fan.fanTotalEfficiency
        elsif zone_hvac.supplyAirFan.to_FanVariableVolume.is_initialized
          supply_fan = zone_hvac.supplyAirFan.to_FanVariableVolume.get
          fan_minimum_flow_frac = supply_fan.fanPowerMinimumFlowFraction
          fan_static_pressure = supply_fan.pressureRise
          fan_efficiency = supply_fan.fanTotalEfficiency
        end

        # Get the maximum flow rate through the fan
        if supply_fan.autosizedMaximumFlowRate.is_initialized
          max_air_flow_rate_m3_per_s = supply_fan.autosizedMaximumFlowRate.get
        elsif supply_fan.maximumFlowRate.is_initialized
          max_air_flow_rate_m3_per_s = supply_fan.maximumFlowRate.get
        else
          runner.registerWarning("Zone HVAC equipment '#{zone_hvac_component.name}' fan '#{supply_fan.name}' flow rate is not initialized.")
          next
        end

        zone_hvac_fan_total_air_flow_m3_per_s += max_air_flow_rate_m3_per_s
        zone_hvac_weighted_fan_power_minimum_flow_fraction += fan_minimum_flow_frac * max_air_flow_rate_m3_per_s
        zone_hvac_weighted_fan_static_pressure += fan_static_pressure * max_air_flow_rate_m3_per_s
        zone_hvac_weighted_fan_efficiency += fan_efficiency * max_air_flow_rate_m3_per_s
      end
    end
    zone_hvac_fan_power_minimum_flow_fraction = zone_hvac_fan_total_air_flow_m3_per_s > 0.0 ? zone_hvac_weighted_fan_power_minimum_flow_fraction / zone_hvac_fan_total_air_flow_m3_per_s : 0.0
    runner.registerValue('com_report_zone_hvac_fan_power_minimum_flow_fraction', zone_hvac_fan_power_minimum_flow_fraction)
    zone_hvac_fan_static_pressure = zone_hvac_fan_total_air_flow_m3_per_s > 0.0 ? zone_hvac_weighted_fan_static_pressure / zone_hvac_fan_total_air_flow_m3_per_s : 0.0
    runner.registerValue('com_report_zone_hvac_fan_static_pressure', zone_hvac_fan_static_pressure ,'Pa')
    zone_hvac_fan_total_efficiency = zone_hvac_fan_total_air_flow_m3_per_s > 0.0 ? zone_hvac_weighted_fan_efficiency / zone_hvac_fan_total_air_flow_m3_per_s : 0.0
    runner.registerValue('com_report_zone_hvac_fan_total_efficiency', zone_hvac_fan_total_efficiency)

    # calculate building heating and cooling
    building_heated_zone_area_m2 = 0.0
    building_cooled_zone_area_m2 = 0.0
    building_zone_area_m2 = 0.0
    model.getThermalZones.sort.each do |zone|
      building_zone_area_m2 += zone.floorArea
      building_heated_zone_area_m2 += zone.floorArea if std.thermal_zone_heated?(zone)
      building_cooled_zone_area_m2 += zone.floorArea if std.thermal_zone_cooled?(zone)
    end

    # Fraction of building heated
    building_fraction_heated = building_heated_zone_area_m2 / building_zone_area_m2
    runner.registerValue('com_report_building_fraction_heated', building_fraction_heated)

    # Fraction of building cooled
    building_fraction_cooled = building_cooled_zone_area_m2 / building_zone_area_m2
    runner.registerValue('com_report_building_fraction_cooled', building_fraction_cooled)

    # Derive building-wide area weighted averages for heating and cooling minimum and maximum thermostat schedule values
    weighted_thermostat_heating_min_c = 0.0
    weighted_thermostat_heating_max_c = 0.0
    weighted_thermostat_heating_area_m2 = 0.0
    weighted_thermostat_cooling_min_c = 0.0
    weighted_thermostat_cooling_max_c = 0.0
    weighted_thermostat_cooling_area_m2 = 0.0
    model.getThermalZones.each do |zone|
      next unless zone.thermostatSetpointDualSetpoint.is_initialized
      floor_area_m2 = zone.floorArea
      thermostat = zone.thermostatSetpointDualSetpoint.get
      if thermostat.heatingSetpointTemperatureSchedule.is_initialized
        thermostat_heating_schedule = thermostat.heatingSetpointTemperatureSchedule.get
        next unless thermostat_heating_schedule.to_ScheduleRuleset.is_initialized
        thermostat_heating_schedule = thermostat_heating_schedule.to_ScheduleRuleset.get
        heat_min_max = std.schedule_ruleset_annual_min_max_value(thermostat_heating_schedule)
        weighted_thermostat_heating_min_c += heat_min_max['min'] * floor_area_m2
        weighted_thermostat_heating_max_c += heat_min_max['max'] * floor_area_m2
        weighted_thermostat_heating_area_m2 += floor_area_m2
      end
      if thermostat.coolingSetpointTemperatureSchedule.is_initialized
        thermostat_cooling_schedule = thermostat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
        next unless thermostat_cooling_schedule.to_ScheduleRuleset.is_initialized
        thermostat_cooling_schedule = thermostat_cooling_schedule.to_ScheduleRuleset.get
        cool_min_max = std.schedule_ruleset_annual_min_max_value(thermostat_cooling_schedule)
        weighted_thermostat_cooling_min_c += cool_min_max['min'] * floor_area_m2
        weighted_thermostat_cooling_max_c += cool_min_max['max'] * floor_area_m2
        weighted_thermostat_cooling_area_m2 += floor_area_m2
      end
    end

    # Thermostat heating setpoint minimum and maximum
    if weighted_thermostat_heating_area_m2 > 0.0
      average_heating_setpoint_min_c =  weighted_thermostat_heating_min_c / weighted_thermostat_heating_area_m2
      average_heating_setpoint_max_c = weighted_thermostat_heating_max_c / weighted_thermostat_heating_area_m2
      runner.registerValue('com_report_average_heating_setpoint_min_c', average_heating_setpoint_min_c, 'C')
      runner.registerValue('com_report_average_heating_setpoint_max_c', average_heating_setpoint_max_c, 'C')
    end

    # Thermostat cooling setpoint minimum and maximum
    if weighted_thermostat_cooling_area_m2 > 0.0
      average_cooling_setpoint_min_c = weighted_thermostat_cooling_min_c / weighted_thermostat_cooling_area_m2
      average_cooling_setpoint_max_c = weighted_thermostat_cooling_max_c / weighted_thermostat_cooling_area_m2
      runner.registerValue('com_report_average_cooling_setpoint_min_c', average_cooling_setpoint_min_c, 'C')
      runner.registerValue('com_report_average_cooling_setpoint_max_c', average_cooling_setpoint_max_c, 'C')
    end

    # Design and annual average chiller efficiency
    chiller_total_load_j = 0.0
    chiller_load_weighted_cop = 0.0
    chiller_load_weighted_design_cop = 0.0
    model.getChillerElectricEIRs.each do |chiller|
      # get Chiller Evaporator Cooling Energy
      chiller_load_j = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Chiller Evaporator Cooling Energy' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{chiller.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          chiller_load_j = val.get
        else
          runner.registerWarning("'Chiller Evaporator Cooling Energy' not available for chiller '#{chiller.name}'.")
        end
      else
        runner.registerWarning("'Chiller Evaporator Cooling Energy' not available for chiller '#{chiller.name}'.")
      end

      # get chiller annual cop
      chiller_annual_cop = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Chiller COP' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{chiller.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          chiller_annual_cop = val.get
        else
          runner.registerWarning("'Annual Chiller COP' not available for chiller '#{chiller.name}'.")
        end
      else
        runner.registerWarning("'Annual Chiller COP' not available for chiller '#{chiller.name}'.")
      end

      # get chiller design cop
      chiller_design_cop = chiller.referenceCOP

      # add to weighted load cop
      chiller_total_load_j += chiller_load_j
      chiller_load_weighted_cop += chiller_load_j * chiller_annual_cop
      chiller_load_weighted_design_cop += chiller_load_j * chiller_design_cop
    end
    average_chiller_cop = chiller_total_load_j > 0.0 ? chiller_load_weighted_cop / chiller_total_load_j : 0.0
    runner.registerValue('com_report_average_chiller_cop', average_chiller_cop)
    design_chiller_cop = chiller_total_load_j > 0.0 ? chiller_load_weighted_design_cop / chiller_total_load_j : 0.0
    runner.registerValue('com_report_design_chiller_cop', design_chiller_cop)

    # Design and annual average DX cooling efficiency
    dx_cooling_total_load_j = 0.0
    dx_cooling_load_weighted_cop = 0.0
    dx_cooling_load_weighted_design_cop = 0.0
    dx_cooling_coils = []
    model.getCoilCoolingDXSingleSpeeds.each { |c| dx_cooling_coils << c }
    model.getCoilCoolingDXTwoSpeeds.each { |c| dx_cooling_coils << c }
    dx_cooling_coils.each do |coil|
      # get Cooling Coil Total Cooling Energy
      coil_cooling_energy_j = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Cooling Coil Total Cooling Energy' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{coil.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          coil_cooling_energy_j = val.get
        else
          runner.registerWarning("'Coil Cooling Total Cooling Energy' not available for DX coil '#{coil.name}'.")
        end
      else
        runner.registerWarning("'Coil Cooling Total Cooling Energy' not available for DX coil '#{coil.name}'.")
      end

      # get Cooling Coil Electric Energy
      coil_electric_energy_j = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Cooling Coil Electric Energy' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{coil.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          coil_electric_energy_j = val.get
        else
          runner.registerWarning("'Cooling Coil Electric Energy' not available for DX coil '#{coil.name}'.")
        end
      else
        runner.registerWarning("'Cooling Coil Electric Energy' not available for DX coil '#{coil.name}'.")
      end

      # get coil rated cop, or rated high speed cop if two speed
      if coil.to_CoilCoolingDXSingleSpeed.is_initialized
        coil = coil.to_CoilCoolingDXSingleSpeed.get
        if coil.ratedCOP.is_initialized
          coil_design_cop = coil.ratedCOP.get
        else
          coil_design_cop = 0.0
          runner.registerWarning("'Rated COP' not available for DX coil '#{coil.name}'.")
        end
      elsif coil.to_CoilCoolingDXTwoSpeed.is_initialized
        coil = coil.to_CoilCoolingDXTwoSpeed.get
        if coil.ratedHighSpeedCOP.is_initialized
          coil_design_cop = coil.ratedHighSpeedCOP.get
        else
          coil_design_cop = 0.0
          runner.registerWarning("'Rated High Speed COP' not available for DX coil '#{coil.name}'.")
        end
      end

      # add to weighted load cop
      coil_annual_cop = coil_cooling_energy_j > 0.0 ? coil_cooling_energy_j / coil_electric_energy_j : 0
      dx_cooling_total_load_j += coil_cooling_energy_j
      dx_cooling_load_weighted_cop += coil_cooling_energy_j * coil_annual_cop
      dx_cooling_load_weighted_design_cop += coil_cooling_energy_j * coil_design_cop
    end
    average_dx_cooling_cop = dx_cooling_total_load_j > 0.0 ? dx_cooling_load_weighted_cop / dx_cooling_total_load_j : 0.0
    runner.registerValue('com_report_average_dx_cooling_cop', average_dx_cooling_cop)
    design_dx_cooling_cop = dx_cooling_total_load_j > 0.0 ? dx_cooling_load_weighted_design_cop / dx_cooling_total_load_j : 0.0
    runner.registerValue('com_report_design_dx_cooling_cop', design_dx_cooling_cop)

    # Design and annual average DX heating efficiency
    dx_heating_total_load_j = 0.0
    dx_heating_load_weighted_cop = 0.0
    dx_heating_load_weighted_design_cop = 0.0
    model.getCoilHeatingDXSingleSpeeds.each do |coil|
      # get Heating Coil Heating Energy
      coil_heating_energy_j = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Heating Coil Heating Energy' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{coil.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          coil_heating_energy_j = val.get
        else
          runner.registerWarning("'Heating Coil Heating Energy' not available for DX coil '#{coil.name}'.")
        end
      else
        runner.registerWarning("'Heating Coil Heating Energy' not available for DX coil '#{coil.name}'.")
      end

      # get Heating Coil Electric Energy
      coil_electric_energy_j = 0.0
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Heating Coil Electric Energy' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{coil.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        val = sql.execAndReturnFirstDouble(var_val_query)
        if val.is_initialized
          coil_electric_energy_j = val.get
        else
          runner.registerWarning("'Heating Coil Electric Energy' not available for DX coil '#{coil.name}'.")
        end
      else
        runner.registerWarning("'Heating Coil Electric Energy' not available for DX coil '#{coil.name}'.")
      end

      # get coil rated cop
      coil_design_cop = coil.ratedCOP

      # add to weighted load cop
      coil_annual_cop = coil_heating_energy_j > 0.0 ? coil_heating_energy_j / coil_electric_energy_j : 0
      dx_heating_total_load_j += coil_heating_energy_j
      dx_heating_load_weighted_cop += coil_heating_energy_j * coil_annual_cop
      dx_heating_load_weighted_design_cop += coil_heating_energy_j * coil_design_cop
    end
    average_dx_heating_cop = dx_heating_total_load_j > 0.0 ? dx_heating_load_weighted_cop / dx_heating_total_load_j : 0.0
    runner.registerValue('com_report_average_dx_heating_cop', average_dx_heating_cop)
    design_dx_heating_cop = dx_heating_total_load_j > 0.0 ? dx_heating_load_weighted_design_cop / dx_heating_total_load_j : 0.0
    runner.registerValue('com_report_design_dx_heating_cop', design_dx_heating_cop)

    # Average boiler efficiency
    boiler_capacity_weighted_efficiency = 0.0
    boiler_total_capacity_w = 0.0
    model.getBoilerHotWaters.each do |boiler|
      capacity_w = 0.0
      if boiler.nominalCapacity.is_initialized
        capacity_w = boiler.nominalCapacity.get
      elsif boiler.autosizedNominalCapacity.is_initialized
        capacity_w = boiler.autosizedNominalCapacity.get
      else
        runner.registerWarning("Boiler capacity not available for boiler '#{boiler.name}'.")
      end
      boiler_total_capacity_w += capacity_w
      boiler_capacity_weighted_efficiency += capacity_w * boiler.nominalThermalEfficiency
    end
    average_boiler_efficiency = boiler_total_capacity_w > 0.0 ? boiler_capacity_weighted_efficiency / boiler_total_capacity_w : 0.0
    runner.registerValue('com_report_average_boiler_efficiency', average_boiler_efficiency)

    # Average gas coil efficiency
    gas_coil_capacity_weighted_efficiency = 0.0
    gas_coil_total_capacity_w = 0.0
    model.getCoilHeatingGass.each do |coil|
      capacity_w = 0.0
      if coil.nominalCapacity.is_initialized
        capacity_w = coil.nominalCapacity.get
      elsif coil.autosizedNominalCapacity.is_initialized
        capacity_w = coil.autosizedNominalCapacity.get
      else
        runner.registerWarning("Gas heating coil capacity not available for '#{coil.name}'.")
      end
      gas_coil_total_capacity_w += capacity_w
      gas_coil_capacity_weighted_efficiency += capacity_w * coil.gasBurnerEfficiency
    end
    average_gas_coil_efficiency = gas_coil_total_capacity_w > 0.0 ? gas_coil_capacity_weighted_efficiency / gas_coil_total_capacity_w : 0.0
    runner.registerValue('com_report_average_gas_coil_efficiency', average_gas_coil_efficiency)

    # Service water heating hot water use
    hot_water_volume_m3 = 0
    model.getWaterUseConnectionss.each do |water_use_connection|
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'Water Use Connections Hot Water Volume' AND ReportingFrequency = 'Run Period' AND KeyValue = '#{water_use_connection.name.get.to_s.upcase}'"
      var_data_id = sql.execAndReturnFirstDouble(var_data_id_query)
      if var_data_id.is_initialized
        var_val_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}'"
        hot_water_volume_m3 += sql.execAndReturnFirstDouble(var_val_query).get
      else
        runner.registerWarning("'Water Use Connections Hot Water Volume' not available for water use connection '#{water_use_connection.name}'.")
      end
    end
    runner.registerValue('com_report_hot_water_volume_m3', hot_water_volume_m3, 'm^3')

    # close the sql file
    sql.close

    return true
  end
end

# register the measure to be used by the application
ComStockSensitivityReports.new.registerWithApplication
