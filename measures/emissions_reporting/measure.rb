# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2021, Alliance for Sustainable Energy, LLC.
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

require 'csv'

# string underscore helper
# from https://stackoverflow.com/questions/1509915/converting-camel-case-to-underscore-case-in-ruby
class String
  def underscore
    gsub('::', '/')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr('-', '_')
      .downcase
  end
end

# start the measure
class EmissionsReporting < OpenStudio::Measure::ReportingMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Emissions Reporting'
  end

  # human readable description
  def description
    return 'This measure calculates annual and hourly CO2e emissions from a model.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure calculates the hourly CO2e emissions for a model given an electricity grid region and emissions scenario.  Hourly emissions data comes from the Cambium dataset.  Grid regions and emissions scenarios are detailed in the Cambium documentation.  The measure also calculates annual CO2e emissions from annual eGrid factors for comparison.'
  end

  def cambium_emissions_scenarios
    emissions_scenarios = [
      'AER_95DecarbBy2035',
      'AER_95DecarbBy2050',
      'AER_HighRECost',
      'AER_LowRECost',
      'AER_MidCase',
      'LRMER_95DecarbBy2035_15',
      'LRMER_95DecarbBy2035_30',
      'LRMER_95DecarbBy2035_15_2025start',
      'LRMER_95DecarbBy2035_25_2025start',
      'LRMER_95DecarbBy2050_15',
      'LRMER_95DecarbBy2050_30',
      'LRMER_HighRECost_15',
      'LRMER_HighRECost_30',
      'LRMER_LowRECost_15',
      'LRMER_LowRECost_30',
      'LRMER_LowRECost_15_2025start',
      'LRMER_LowRECost_25_2025start',
      'LRMER_MidCase_15',
      'LRMER_MidCase_30',
      'LRMER_MidCase_15_2025start',
      'LRMER_MidCase_25_2025start'
    ]
    return emissions_scenarios
  end

  def grid_regions
    grid_regions = [
      'AZNMc',
      'AKGD',
      'AKMS',
      'CAMXc',
      'ERCTc',
      'FRCCc',
      'HIMS',
      'HIOA',
      'MROEc',
      'MROWc',
      'NEWEc',
      'NWPPc',
      'NYSTc',
      'RFCEc',
      'RFCMc',
      'RFCWc',
      'RMPAc',
      'SPNOc',
      'SPSOc',
      'SRMVc',
      'SRMWc',
      'SRSOc',
      'SRTVc',
      'SRVCc'
    ]
    return grid_regions
  end

  def grid_states
    grid_states = [
      'AK',
      'AL',
      'AR',
      'AZ',
      'CA',
      'CO',
      'CT',
      'DC',
      'DE',
      'FL',
      'GA',
      'HI',
      'IA',
      'ID',
      'IL',
      'IN',
      'KS',
      'KY',
      'LA',
      'MA',
      'MD',
      'ME',
      'MI',
      'MN',
      'MO',
      'MS',
      'MT',
      'NC',
      'ND',
      'NE',
      'NH',
      'NJ',
      'NM',
      'NV',
      'NY',
      'OH',
      'OK',
      'OR',
      'PA',
      'PR',
      'RI',
      'SC',
      'SD',
      'TN',
      'TX',
      'UT',
      'VA',
      'VT',
      'WA',
      'WI',
      'WV',
      'WY'
    ]
    return grid_states
  end

  def resources(model)
    resources = [
      'Electricity',
      'Propane'
      # 'DistrictHeating',
      # 'DistrictCooling'
    ]

    # Handle fuel output variables that changed in EnergyPlus version 9.4 (Openstudio version >= 3.1)
    if model.version > OpenStudio::VersionString.new('3.0.1')
      resources << 'NaturalGas'
      resources << 'FuelOilNo2'
    else
      resources << 'Gas'
      resources << 'FuelOil#2'
    end

    return resources
  end

  def enduses
    enduses = [
      'Heating',
      'InteriorLights',
      'ExteriorLights',
      'InteriorEquipment',
      # 'ExteriorEquipment',
      'Refrigeration',
      'WaterSystems'
    ]
    return enduses
  end

  def hvac_uses
    hvac_uses = [
      'Heating',
      'Cooling',
      'Fans',
      'Pumps',
      'HeatRejection',
      'Humidification',
      'HeatRecovery'
    ]
    return hvac_uses
  end

  def seasons
    return {
      'winter' => [-1e9, 55],
      'summer' => [70, 1e9],
      'shoulder' => [55, 70]
    }
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for the grid region
    grid_region_chs = OpenStudio::StringVector.new
    grid_regions.each { |grid_region| grid_region_chs << grid_region }
    grid_region_chs << 'Lookup from model'
    grid_region = OpenStudio::Measure::OSArgument.makeChoiceArgument('grid_region', grid_region_chs, true)
    grid_region.setDisplayName('Grid Region')
    grid_region.setDescription('Cambium electric grid region, or eGrid region for Alaska and Hawaii')
    grid_region.setDefaultValue('Lookup from model')
    args << grid_region

    # make an argument for the grid states
    grid_states_chs = OpenStudio::StringVector.new
    grid_states.each { |grid_state| grid_states_chs << grid_state }
    grid_states_chs << 'Lookup from model'
    grid_state = OpenStudio::Measure::OSArgument.makeChoiceArgument('grid_state', grid_states_chs, true)
    grid_state.setDisplayName('U.S. State')
    grid_state.setDefaultValue('Lookup from model')
    args << grid_state

    # emissions scenarios
    scenario_chs = OpenStudio::StringVector.new
    cambium_emissions_scenarios.each { |scenario| scenario_chs << scenario }
    scenario_chs << 'All'

    # make an argument for the emissions scenario
    emissions_scenario = OpenStudio::Measure::OSArgument.makeChoiceArgument('emissions_scenario', scenario_chs, true)
    emissions_scenario.setDisplayName('Emissions Scenario')
    emissions_scenario.setDescription('Cambium emissions scenario to use for hourly emissions calculation')
    emissions_scenario.setDefaultValue('All')
    args << emissions_scenario

    return args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  # Warning: Do not change the name of this method to be snake_case. The method must be lowerCamelCase.
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return result
    end

    # Get model
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model in energyPlusOutputRequests, cannot request outputs for emissions data.')
      return result
    end
    model = model.get

    resources = resources(model)
    resources.each do |resource|
      # only request timeseries for electricity
      if resource.include?('Electricity')
        frequency = 'Hourly'
      else
        frequency = 'RunPeriod'
      end

      # add facility meters
      result << OpenStudio::IdfObject.load("Output:Meter,#{resource}:Facility,#{frequency};").get

      # add enduse meters
      enduses.each do |enduse|
        # lights, refrigeration only use electricity
        next if (enduse.include?('Lights') || enduse.include?('Refrigeration')) && resource != 'Electricity'

        result << OpenStudio::IdfObject.load("Output:Meter,#{enduse}:#{resource},#{frequency};").get
      end

      # custom meters for hvac
      total_hvac_string = "Meter:Custom,TotalHVAC:#{resource},#{resource},"

      hvac_uses.each_with_index do |use, i|
        if hvac_uses.size == i + 1
          total_hvac_string << ",#{use}:#{resource};"
        else
          total_hvac_string << ",#{use}:#{resource},"
        end
      end

      cooling_string = "Meter:Custom,CoolingHVAC:#{resource},#{resource},,Cooling:#{resource},,HeatRejection:#{resource};"

      result << OpenStudio::IdfObject.load(total_hvac_string).get
      result << OpenStudio::IdfObject.load(cooling_string).get
      result << OpenStudio::IdfObject.load("Output:Meter,TotalHVAC:#{resource},#{frequency};").get
      result << OpenStudio::IdfObject.load("Output:Meter,CoolingHVAC:#{resource},#{frequency};").get
    end

    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return false
    end

    grid_region = runner.getStringArgumentValue('grid_region', user_arguments)
    grid_state = runner.getStringArgumentValue('grid_state', user_arguments)
    emissions_scenario = runner.getStringArgumentValue('emissions_scenario', user_arguments)

    # Define run directory location
    run_dir_typical = File.absolute_path(File.join(Dir.pwd, 'run'))
    run_dir_comstock = File.absolute_path(File.join(Dir.pwd, '..'))
    if File.exist?(run_dir_typical)
      run_dir = run_dir_typical
      runner.registerInfo("run directory: #{run_dir}")
    elsif File.exist?(run_dir_comstock)
      run_dir = run_dir_comstock
      runner.registerInfo("run directory: #{run_dir}")
    else
      runner.registerError('Could not find directory with EnergyPlus output, cannont extract timeseries results')
      return false
    end

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    sqlFile = runner.lastEnergyPlusSqlFile
    if sqlFile.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sqlFile = sqlFile.get
    model.setSqlFile(sqlFile)

    ann_env_pd = nil
    sqlFile.availableEnvPeriods.each do |env_pd|
      env_type = sqlFile.environmentType(env_pd)
      if env_type.is_initialized && (env_type.get == (OpenStudio::EnvironmentType.new('WeatherRunPeriod')))
        ann_env_pd = env_pd
      end
    end
    if ann_env_pd == false
      runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
      return false
    end

    # Handle fuel output variables that changed in EnergyPlus version 9.4 (Openstudio version >= 3.1)
    fuel_oil = 'FuelOil#2'
    gas = 'Gas'
    if model.version > OpenStudio::VersionString.new('3.0.1')
      fuel_oil = 'FuelOilNo2'
      gas = 'NaturalGas'
    end

    # unit conversion factors
    j_to_kbtu = OpenStudio.convert(1.0, 'J', 'kBtu').get
    j_to_kwh = OpenStudio.convert(1.0, 'J', 'kWh').get
    j_to_mwh = OpenStudio.convert(1.0, 'J', 'MWh').get
    lbm_to_kg = OpenStudio.convert(1.0, 'lb_m', 'kg').get

    # fossil fuel emission factors
    # natural gas emissions factors
    # from: https://openstudio-hpxml.readthedocs.io/en/latest/workflow_inputs.html#default-values
    natural_gas_emissions_factor_co2e_lb_per_mmbtu = 147.3
    natural_gas_emissions_factor_co2e_kg_per_kbtu = natural_gas_emissions_factor_co2e_lb_per_mmbtu * (1 / 1000.0) * lbm_to_kg

    # fuel oil emissions factors
    # from: https://openstudio-hpxml.readthedocs.io/en/latest/workflow_inputs.html#default-values
    fuel_oil_emissions_factor_co2e_lb_per_mmbtu = 195.9
    fuel_oil_emissions_factor_co2e_kg_per_kbtu = fuel_oil_emissions_factor_co2e_lb_per_mmbtu * (1 / 1000.0) * lbm_to_kg

    # propane emissions factors
    # from: https://openstudio-hpxml.readthedocs.io/en/latest/workflow_inputs.html#default-values
    propane_emissions_factor_co2e_lb_per_mmbtu = 177.8
    propane_emissions_factor_co2e_kg_per_kbtu = propane_emissions_factor_co2e_lb_per_mmbtu * (1 / 1000.0) * lbm_to_kg

    # set cambium and egrid regions
    if grid_region == 'Lookup from model'
      grid_region = model.getBuilding.additionalProperties.getFeatureAsString('grid_region')
      unless grid_region.is_initialized
        runner.registerError('Unable to find grid region in model building additional properties')
        return false
      end
      grid_region = grid_region.get
      runner.registerInfo("Using grid region #{grid_region} from model building additional properties.")
    end

    if ['AKMS', 'AKGD', 'HIMS', 'HIOA'].include? grid_region
      cambium_grid_region = nil
      egrid_region = grid_region
      runner.registerWarning("Grid region '#{grid_region}' is not available in Cambium.  Using eGrid factors only for electricty related emissions.")
    else
      cambium_grid_region = grid_region
      egrid_region = grid_region.chop
    end

    # set egrid state
    if grid_state == 'Lookup from model'
      model_state = model.getWeatherFile.stateProvinceRegion

      if model_state == ''
        runner.registerError('Unable to find state in model WeatherFile object. The model may not have a weather file set.')
        return false
      end

      if grid_states.include? model_state
        egrid_state = model_state
        runner.registerInfo("Using state '#{egrid_state}' from model.")
      else
        runner.registerError("State '#{model_state}' is not a valid eGRID state.")
        return false
      end
    else
      egrid_state = grid_state
      runner.registerInfo("Using state '#{egrid_state}' from user inputs.")
    end

    env_period_ix_query = "SELECT EnvironmentPeriodIndex FROM EnvironmentPeriods WHERE EnvironmentName='#{ann_env_pd}'"
    env_period_ix = sqlFile.execAndReturnFirstInt(env_period_ix_query).get
    # get hourly temperature values
    temperature_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex IN (SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableType='Avg' AND VariableName IN ('Site Outdoor Air Drybulb Temperature') AND ReportingFrequency='Hourly' AND VariableUnits='C') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    temperatures = sqlFile.execAndReturnVectorOfDouble(temperature_query).get
    if temperatures.empty?
      runner.registerError('Unable to get hourly temperature from the model. Cannot calculate seasonal emissions.')
      return false
    end
    hourly_temperature_F = temperatures.map do |val|
      OpenStudio.convert(val, 'C', 'F').get
    end

    # get hourly electricity values
    electricity_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableType='Sum' AND VariableName='Electricity:Facility' AND ReportingFrequency='Hourly' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    electricity_values = sqlFile.execAndReturnVectorOfDouble(electricity_query).get
    if electricity_values.empty?
      runner.registerError('Unable to get hourly timeseries facility electricity use from the model.  Cannot calculate emissions.')
      return false
    end

    hourly_electricity_mwh = electricity_values.map { |val| (val * j_to_mwh) }

    # get end-use electricity values
    electricity_enduse_results = {}
    enduses.push(['TotalHVAC', 'CoolingHVAC']).flatten.each do |enduse|
      electricity_enduse_results["#{enduse}_mwh"] = []
      electricity_enduse_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex from ReportMeterDataDictionary WHERE VariableType='Sum' AND upper(VariableName)='#{enduse.upcase}:ELECTRICITY' AND ReportingFrequency='Hourly' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
      electricity_enduse_values = sqlFile.execAndReturnVectorOfDouble(electricity_enduse_query).get
      if electricity_enduse_values.empty?
        runner.registerWarning("Unable to get hourly timeseries #{enduse} electricity use from the model. Cannot calculate results")
        electricity_enduse_results["#{enduse}_mwh"] << 0
      end
      electricity_enduse_values.each { |val| electricity_enduse_results["#{enduse}_mwh"] << (val * j_to_mwh) }
    end

    # get run period natural gas values
    annual_natural_gas_emissions_co2e_kg = 0
    natural_gas_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableType='Sum' AND VariableName='#{gas}:Facility' AND ReportingFrequency='Run Period' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    puts natural_gas_query
    natural_gas_values = sqlFile.execAndReturnVectorOfDouble(natural_gas_query).get
    if natural_gas_values.empty?
      runner.registerWarning('Unable to get hourly timeseries facility natural gas use from the model, the model may not use gas.  Cannot calculate emissions.')
    else
      annual_natural_gas_emissions_co2e_kg = natural_gas_values.map { |v| v * j_to_kbtu * natural_gas_emissions_factor_co2e_kg_per_kbtu }.sum
    end
    runner.registerInfo("Annual hourly natural gas emissions (kg CO2e): #{annual_natural_gas_emissions_co2e_kg.round(2)}")
    runner.registerValue('annual_natural_gas_ghg_emissions_kg', annual_natural_gas_emissions_co2e_kg)

    # get run period fuel oil values
    annual_fuel_oil_emissions_co2e_kg = 0
    fuel_oil_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableType='Sum' AND VariableName='#{fuel_oil}:Facility' AND ReportingFrequency='Run Period' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    fuel_oil_values = sqlFile.execAndReturnVectorOfDouble(fuel_oil_query).get
    if fuel_oil_values.empty?
      runner.registerWarning('Unable to get hourly timeseries facility fuel oil use from the model, the model may not use fuel oil.  Cannot calculate emissions.')
    else
      annual_fuel_oil_emissions_co2e_kg = fuel_oil_values.map { |v| v * j_to_kbtu * fuel_oil_emissions_factor_co2e_kg_per_kbtu }.sum
    end
    runner.registerInfo("Annual hourly fuel oil emissions (kg CO2e): #{annual_fuel_oil_emissions_co2e_kg.round(2)}")
    runner.registerValue('annual_fuel_oil_ghg_emissions_kg', annual_fuel_oil_emissions_co2e_kg)

    # get run period propane values
    annual_propane_emissions_co2e_kg = 0
    propane_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableType='Sum' AND VariableName='Propane:Facility' AND ReportingFrequency='Run Period' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    propane_values = sqlFile.execAndReturnVectorOfDouble(propane_query).get
    if propane_values.empty?
      runner.registerWarning('Unable to get hourly timeseries facility propane use from the model, the model may not use propane.  Cannot calculate emissions.')
    else
      annual_propane_emissions_co2e_kg = propane_values.map { |val| val * j_to_kbtu * propane_emissions_factor_co2e_kg_per_kbtu }.sum
    end
    runner.registerInfo("Annual hourly propane emissions (kg CO2e): #{annual_propane_emissions_co2e_kg.round(2)}")
    runner.registerValue('annual_propane_ghg_emissions_kg', annual_propane_emissions_co2e_kg)

    # fuel end-use emissions
    enduses.push('TotalHVAC').each do |enduse|
      next if enduse.include?('Lights') || enduse.include?('Refrigeration')

      # get run period natural gas end-use values
      gas_enduse_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex from ReportMeterDataDictionary WHERE VariableType='Sum' AND upper(VariableName)='#{enduse.upcase}:#{gas.upcase}' AND ReportingFrequency='Run Period' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
      gas_enduse_values = sqlFile.execAndReturnVectorOfDouble(gas_enduse_query).get
      if gas_enduse_values.empty?
        runner.registerWarning("Unable to find annual #{enduse} natural gas use from the model, the model may not use gas for this end-use. Cannot calculate end-use emissions for this fuel.")
        total_enduse_gas_emissions_co2e_kg = 0
      else
        total_enduse_gas_emissions_co2e_kg = gas_enduse_values.map { |val| val * j_to_kbtu * natural_gas_emissions_factor_co2e_kg_per_kbtu }.sum
      end
      runner.registerInfo("Annual total natural gas #{enduse} emissions (kg CO2e): #{total_enduse_gas_emissions_co2e_kg.round(2)}")
      runner.registerValue("annual_#{enduse.underscore}_natural_gas_ghg_emissions_kg", total_enduse_gas_emissions_co2e_kg)

      # get run period propane end-use values
      propane_enduse_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableType='Sum' AND upper(VariableName)='#{enduse.upcase}:PROPANE' AND ReportingFrequency='Run Period' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
      propane_enduse_values = sqlFile.execAndReturnVectorOfDouble(propane_enduse_query).get
      if propane_enduse_values.empty?
        runner.registerWarning("Unable to find annual #{enduse} propane from the model, the model may not use propane for this end-use. Cannot calculate end-use emissions for this fuel.")
        total_enduse_propane_emissions_co2e_kg = 0
      else
        total_enduse_propane_emissions_co2e_kg = propane_enduse_values.map { |val| val * j_to_kbtu * propane_emissions_factor_co2e_kg_per_kbtu }.sum
      end
      runner.registerInfo("Annual total propane #{enduse} emissions (kg CO2e): #{total_enduse_propane_emissions_co2e_kg.round(2)}.")
      runner.registerValue("annual_#{enduse.underscore}_propane_ghg_emissions_kg", total_enduse_propane_emissions_co2e_kg)

      # get run period fuel oil end-use values
      fuel_oil_enduse_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableType='Sum' AND upper(VariableName)='#{enduse.upcase}:#{fuel_oil.upcase}' AND ReportingFrequency='Run Period' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
      fuel_oil_enduse_values = sqlFile.execAndReturnVectorOfDouble(fuel_oil_enduse_query).get
      if fuel_oil_enduse_values.empty?
        runner.registerWarning("Unable to find annual #{enduse} fuel oil from the model, the model may not use propane for this end-use. Cannot calculate end-use emissions for this fuel.")
        total_enduse_fuel_oil_emissions_co2e_kg = 0
      else
        total_enduse_fuel_oil_emissions_co2e_kg = fuel_oil_enduse_values.map { |val| val * j_to_kbtu * fuel_oil_emissions_factor_co2e_kg_per_kbtu }.sum
      end
      runner.registerInfo("Annual total fuel oil #{enduse} emissions (kg CO2e): #{total_enduse_fuel_oil_emissions_co2e_kg.round(2)}.")
      runner.registerValue("annual_#{enduse.underscore}_fuel_oil_ghg_emissions_kg", total_enduse_fuel_oil_emissions_co2e_kg)
    end

    # calculate eGRID subregion emissions
    egrid_subregion_emissions_factors_csv = "#{File.dirname(__FILE__)}/resources/egrid/egrid_subregion_emissions_factors.csv"
    if !File.file?(egrid_subregion_emissions_factors_csv)
      runner.registerError("Unable to find file: #{egrid_subregion_emissions_factors_csv}")
      return false
    end
    egrid_subregion_lkp = CSV.table(egrid_subregion_emissions_factors_csv)
    egrid_subregion_hsh = egrid_subregion_lkp.map(&:to_hash)
    egrid_subregion_hsh = egrid_subregion_hsh.select { |r| (r[:subregion] == egrid_region) }
    if egrid_subregion_hsh.empty?
      runner.registerError("Unable to find eGRID data for subregion: #{egrid_region}")
      return false
    end
    [2018, 2019, 2020, 2021].each do |year|
      egrid_co2e_lb_per_mwh = egrid_subregion_hsh[0][:"#{year}"]
      egrid_co2e_kg_per_mwh = egrid_co2e_lb_per_mwh * lbm_to_kg
      runner.registerInfo("eGRID #{year} emissions factor for '#{egrid_region}' is #{egrid_co2e_kg_per_mwh.round(2)} CO2e kg per MWh")
      annual_egrid_emissions_co2e_kg = hourly_electricity_mwh.inject(:+) * egrid_co2e_kg_per_mwh
      runner.registerInfo("Annual eGRID #{year} subregion emissions CO2e kg: #{annual_egrid_emissions_co2e_kg.round(2)}")
      runner.registerValue("annual_electricity_ghg_emissions_egrid_#{year}_subregion_kg", annual_egrid_emissions_co2e_kg)

      # electricity end-uses
      electricity_enduse_results.each do |enduse_key, enduse_array|
        enduse_name = enduse_key.gsub('_mwh', '')
        annual_egrid_enduse_emissions_co2e_kg = enduse_array.sum * egrid_co2e_kg_per_mwh
        runner.registerInfo("Annual eGRID #{year} subregion #{enduse_name} emissions CO2e kg: #{annual_egrid_enduse_emissions_co2e_kg.round(2)}")
        runner.registerValue("annual_#{enduse_name}_electricity_ghg_emissions_egrid_#{year}_subregion_kg", annual_egrid_enduse_emissions_co2e_kg)
      end

      # seasonal for 2021
      if year == 2021
        seasonal_daily_vals_egrid = { 'winter' => [], 'summer' => [], 'shoulder' => [] }
        hourly_electricity_mwh.each_slice(24).with_index do |mwhs, i|
          temps = hourly_temperature_F[(24 * i)...((24 * i) + 24)]
          avg_temp = temps.inject { |sum, el| sum + el }.to_f / temps.size
          seasons.each do |season, temperature_range|
            if (avg_temp > temperature_range[0]) && (avg_temp < temperature_range[1]) # day is in this season
              seasonal_daily_vals_egrid[season] << (mwhs.sum * egrid_co2e_kg_per_mwh)
            end
          end
        end
        seasonal_daily_vals_egrid.each do |season, daily_vals|
          seasonal_daily_egrid_emissions_co2e_kg = daily_vals.sum.to_f / daily_vals.size
          runner.registerInfo("Season #{season} daily average eGRID #{year} subregion emissions CO2e kg: #{seasonal_daily_egrid_emissions_co2e_kg.round(2)}")
          runner.registerValue("#{season}_daily_average_electricity_ghg_emissions_egrid_#{year}_subregion_kg", seasonal_daily_egrid_emissions_co2e_kg)
        end
      end
    end

    # calculate eGRID state emissions
    egrid_state_emissions_factors_csv = "#{File.dirname(__FILE__)}/resources/egrid/egrid_state_emissions_factors.csv"
    if !File.file?(egrid_state_emissions_factors_csv)
      runner.registerError("Unable to find file: #{egrid_state_emissions_factors_csv}")
      return false
    end
    egrid_state_lkp = CSV.table(egrid_state_emissions_factors_csv)
    egrid_state_hsh = egrid_state_lkp.map(&:to_hash)
    egrid_state_hsh = egrid_state_hsh.select { |r| (r[:state] == egrid_state) }
    if egrid_state_hsh.empty?
      runner.registerError("Unable to find eGRID data for state: #{egrid_state}")
      return false
    end
    [2018, 2019, 2020, 2021].each do |year|
      egrid_co2e_lb_per_mwh = egrid_state_hsh[0][:"#{year}"]
      egrid_co2e_kg_per_mwh = egrid_co2e_lb_per_mwh * lbm_to_kg
      runner.registerInfo("eGRID #{year} emissions factor for '#{egrid_state}' is #{egrid_co2e_kg_per_mwh.round(2)} CO2e kg per MWh")
      annual_egrid_emissions_co2e_kg = hourly_electricity_mwh.inject(:+) * egrid_co2e_kg_per_mwh
      runner.registerInfo("Annual eGRID #{year} state emissions CO2e kg: #{annual_egrid_emissions_co2e_kg.round(2)}")
      runner.registerValue("annual_electricity_ghg_emissions_egrid_#{year}_state_kg", annual_egrid_emissions_co2e_kg)

      # electricity end-uses
      electricity_enduse_results.each do |enduse_key, enduse_array|
        enduse_name = enduse_key.gsub('_mwh', '')
        annual_egrid_enduse_emissions_co2e_kg = enduse_array.sum * egrid_co2e_kg_per_mwh
        runner.registerInfo("Annual eGRID #{year} subregion #{enduse_name} emissions CO2e kg: #{annual_egrid_enduse_emissions_co2e_kg.round(2)}")
        runner.registerValue("annual_#{enduse_name}_electricity_ghg_emissions_egrid_#{year}_state_kg", annual_egrid_enduse_emissions_co2e_kg)
      end

      # seasonal for 2021
      if year == 2021
        seasonal_daily_vals_egrid = { 'winter' => [], 'summer' => [], 'shoulder' => [] }
        hourly_electricity_mwh.each_slice(24).with_index do |mwhs, i|
          temps = hourly_temperature_F[(24 * i)...((24 * i) + 24)]
          avg_temp = temps.inject { |sum, el| sum + el }.to_f / temps.size
          seasons.each do |season, temperature_range|
            if (avg_temp > temperature_range[0]) && (avg_temp < temperature_range[1]) # day is in this season
              seasonal_daily_vals_egrid[season] << (mwhs.sum * egrid_co2e_kg_per_mwh)
            end
          end
        end
        seasonal_daily_vals_egrid.each do |season, daily_vals|
          seasonal_daily_egrid_emissions_co2e_kg = daily_vals.sum.to_f / daily_vals.size
          runner.registerInfo("Season #{season} daily average eGRID #{year} state emissions CO2e kg: #{seasonal_daily_egrid_emissions_co2e_kg.round(2)}")
          runner.registerValue("#{season}_daily_average_electricity_ghg_emissions_egrid_#{year}_state_kg", seasonal_daily_egrid_emissions_co2e_kg)
        end
      end
    end

    # guard clause if there is no cambium grid region
    return false if cambium_grid_region.nil?

    # get cambium scenario emissions factors lookup names
    emissions_scenario_lookups = []
    if emissions_scenario == 'All'
      cambium_emissions_scenarios.each { |scenario| emissions_scenario_lookups << scenario }
    else
      emissions_scenario_lookups << emissions_scenario
    end

    # get and calculate emissions emissions
    emissions_scenario_lookups.each do |scenario|
      # name correction for AER scenarios
      if scenario.include? 'AER'
        scenario_lookup = "#{scenario}_1"
      else
        scenario_lookup = scenario
      end

      # read factors from csv
      emissions_csv = "#{File.dirname(__FILE__)}/resources/cambium/#{scenario_lookup}/#{cambium_grid_region}.csv"
      if !File.file?(emissions_csv)
        runner.registerError("Unable to find file: #{emissions_csv}")
        return false
      end
      hourly_elec_factors_kg_per_mwh = CSV.read(emissions_csv, converters: :float).flatten

      # check that arrays are the same length and adjust for leap years if present
      unless hourly_electricity_mwh.size == hourly_elec_factors_kg_per_mwh.size
        if hourly_electricity_mwh.size == 8784
          # leap year, copy Feb 28 data for Feb 29
          hourly_elec_factors_kg_per_mwh = hourly_elec_factors_kg_per_mwh[0..1415] + hourly_elec_factors_kg_per_mwh[1392..1415] + hourly_elec_factors_kg_per_mwh[1416..8759]
        else
          runner.registerError('Unable to calculate emissions for run periods not of length 8760 or 8784')
          return false
        end
      end
      hourly_electricity_emissions_kg = hourly_electricity_mwh.zip(hourly_elec_factors_kg_per_mwh).map { |n, f| n * f }

      annual_electricity_emissions_co2e_kg = hourly_electricity_emissions_kg.inject(:+)
      runner.registerInfo("Annual hourly emissions for cambium scenario '#{scenario}' (kg CO2e): #{annual_electricity_emissions_co2e_kg.round(2)}")
      register_value_name = "annual_electricity_ghg_emissions_#{scenario}_kg"
      runner.registerValue(register_value_name.to_s, annual_electricity_emissions_co2e_kg)

      # end-use emissions
      electricity_enduse_results.each do |enduse_key, enduse_array|
        enduse_name = enduse_key.gsub('_mwh', '')
        # check that arrays are the same length and adjust for leap years if present
        unless (enduse_array.size == hourly_elec_factors_kg_per_mwh.size) || (enduse_array.size == 1)
          if enduse_array.size == 8784
            # leap year, copy Feb 28 data for Feb 29
            hourly_enduse_elec_factors_kg_per_mwh = enduse_array[0..1415] + enduse_array[1392..1415] + enduse_array[1416..8759]
          else
            runner.registerError('Unable to calculate end-use emissions for run periods not of length 8760 or 8784')
            return false
          end
        end
        if enduse_array.size == 1
          hourly_enduse_electricity_emissions_kg = [0]
        else
          hourly_enduse_electricity_emissions_kg = enduse_array.zip(hourly_elec_factors_kg_per_mwh).map { |n, f| n * f }
        end
        annual_enduse_electricity_emisssions_co2e_kg = hourly_enduse_electricity_emissions_kg.sum
        runner.registerInfo("Annual hourly #{enduse_name} emissions for cambium scenario '#{scenario} (kg CO2e): #{annual_enduse_electricity_emisssions_co2e_kg.round(2)}")
        runner.registerValue("annual_#{enduse_name}_electricity_ghg_emissions_#{scenario}_kg", annual_enduse_electricity_emisssions_co2e_kg)
      end

      # seasonal for two selectec scenarios
      if (scenario == 'LRMER_HighRECost_15') || (scenario == 'LRMER_LowRECost_15') || (scenario == 'LRMER_MidCase_15')
        seasonal_daily_vals = { 'winter' => [], 'summer' => [], 'shoulder' => [] }
        hourly_electricity_emissions_kg.each_slice(24).with_index do |co2es, i|
          temps = hourly_temperature_F[(24 * i)...((24 * i) + 24)]
          avg_temp = temps.inject { |sum, el| sum + el }.to_f / temps.size
          seasons.each do |season, temperature_range|
            if (avg_temp > temperature_range[0]) && (avg_temp < temperature_range[1]) # day is in this season
              seasonal_daily_vals[season] << co2es.sum
            end
          end
        end
        seasonal_daily_vals.each do |season, daily_vals|
          seasonal_daily_emissions_co2e_kg = daily_vals.sum.to_f / daily_vals.size
          runner.registerInfo("Season #{season} daily average emissions for cambium scenario '#{scenario}' (kg CO2e): #{seasonal_daily_emissions_co2e_kg.round(2)}")
          runner.registerValue("#{season}_daily_average_electricity_ghg_emissions_#{scenario}_kg", seasonal_daily_emissions_co2e_kg)
        end
      end
    end

    return true
  end
end

# this allows the measure to be use by the application
EmissionsReporting.new.registerWithApplication
