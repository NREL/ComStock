# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'erb'
require 'json'

require "#{File.dirname(__FILE__)}/resources/os_lib_reporting"
require "#{File.dirname(__FILE__)}/resources/os_lib_schedules"
require "#{File.dirname(__FILE__)}/resources/os_lib_helper_methods"

# start the measure
class OpenStudioResults < OpenStudio::Ruleset::ReportingUserScript
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    'OpenStudio Results'
  end

  # human readable description
  def description
    'This measure creates high level tables and charts pulling both from model inputs and EnergyPlus results. It has building level information as well as detail on space types, thermal zones, HVAC systems, envelope characteristics, and economics. Click the heading above a chart to view a table of the chart data.'
  end

  # human readable description of modeling approach
  def modeler_description
    'For the most part consumption data comes from the tabular EnergyPlus results, however there are a few requests added for time series results. Space type and loop details come from the OpenStudio model. The code for this is modular, making it easy to use as a template for your own custom reports. The structure of the report uses bootstrap, and the graphs use dimple js.'
  end

  def possible_sections
    result = []

    # methods for sections in order that they will appear in report

    result << 'building_summary_section'
    # still need to extend building summary
    # still need to populate site performance

    result << 'annual_overview_section'
    result << 'monthly_overview_section'
    result << 'utility_bills_rates_section'
    result << 'envelope_section_section'
    result << 'space_type_breakdown_section'
    result << 'space_type_details_section'

    result << 'interior_lighting_section'
    # consider binning to space types

    result << 'plug_loads_section'
    result << 'exterior_light_section'
    result << 'water_use_section'

    result << 'hvac_load_profile'
    # TODO: - turn on hvac_part_load_profile_table once I have data for it

    result << 'zone_condition_section'
    result << 'zone_summary_section'

    result << 'zone_equipment_detail_section' # TODO: - add in content from other measures
    # result << 'air_loop_summary_section' # TODO: - stub only
    result << 'air_loops_detail_section'
    # later - on all loop detail sections get hard-sized value

    # result << 'plant_loop_summary_section' # TODO: - stub only
    result << 'plant_loops_detail_section'
    result << 'outdoor_air_section'

    result << 'cost_summary_section'
    # find out how to get lifecycle cost with utility escalation
    # consider second cost table listing all lifecycle cost objects in OSM (since can't see in GUI)

    result << 'source_energy_section'

    # result << 'co2_and_other_emissions_section'
    # TODO: - add emissions factors object to our template model

    # result << 'typical_load_profiles_section' # TODO: - stub only
    result << 'schedules_overview_section'
    # TODO: - clean up code to gather schedule profiles so I don't have to grab every 15 minutes

    # see the method below in os_lib_reporting.rb to see a simple example of code to make a section of tables
    # result << 'template_section'

    # TODO: - some tables are so long on real models you loose header. Should we have scrolling within a table?
    # TODO: - maybe sorting as well if it doesn't slow process down too much

    result
  end

  # define the arguments that the user will input
  def arguments
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # populate arguments
    possible_sections.each do |method_name|
      # get display name
      arg = OpenStudio::Ruleset::OSArgument.makeBoolArgument(method_name, true)
      display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true)[:title]")
      arg.setDisplayName(display_name)
      arg.setDefaultValue(true)
      args << arg
    end

    args
  end # end the arguments method

  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # use the built-in error checking
    unless runner.validateUserArguments(arguments, user_arguments)
      return result
    end

    if runner.getBoolArgumentValue('hvac_load_profile', user_arguments)
      result << OpenStudio::IdfObject.load('Output:Variable,,Site Outdoor Air Drybulb Temperature,monthly;').get
    end

    if runner.getBoolArgumentValue('zone_condition_section', user_arguments)
      result << OpenStudio::IdfObject.load('Output:Variable,,Zone Air Temperature,hourly;').get
      result << OpenStudio::IdfObject.load('Output:Variable,,Zone Air Relative Humidity,hourly;').get
    end

    result
  end
  
  def outputs 
    result = OpenStudio::Measure::OSOutputVector.new
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('electricity_ip') # kWh
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('natural_gas_ip') # MBtu
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('additional_fuel_ip') # MBtu
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('district_cooling_heating_ip') # MBtu
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('district_cooling_cooling_ip') # MBtu
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('eui') # kBtu/ft^2
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('net_site_energy') # kBtu
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('annual_peak_electric_demand') # kW

    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('unmet_hours_during_occupied_cooling') # hr
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('unmet_hours_during_occupied_heating') # hr

    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('first_year_capital_cost') # $
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('annual_utility_cost') # $
    result << OpenStudio::Measure::OSOutput.makeDoubleOutput('total_lifecycle_cost') # $
    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # get sql, model, and web assets
    setup = OsLib_Reporting.setup(runner)
    unless setup
      return false
    end
    model = setup[:model]
    # workspace = setup[:workspace]
    sql_file = setup[:sqlFile]
    web_asset_path = setup[:web_asset_path]

    # assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments)
    unless args
      return false
    end

    # reporting final condition
    runner.registerInitialCondition('Gathering data from EnergyPlus SQL file and OSM model.')

    # create a array of sections to loop through in erb file
    @sections = []
    # check units of tabular E+ results
    column_units_query = "SELECT DISTINCT  units FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' and TableName='Building Area'"
    energy_plus_area_units = sql_file.execAndReturnVectorOfString(column_units_query)
    if energy_plus_area_units.is_initialized
      if energy_plus_area_units.get.size == 0
        runner.registerError("Can't find any contents in Building Area Table to get tabular units. Measure can't run")
        return false
      end
    else
      runner.registerError("Can't find Building Area to get tabular units. Measure can't run")
      return false
    end

    if energy_plus_area_units.get.first.to_s == "m2"

      # generate data for requested sections
      sections_made = 0
      possible_sections.each do |method_name|

        begin
          next unless args[method_name]
          section = false
          eval("section = OsLib_Reporting.#{method_name}(model,sql_file,runner,false)")
          display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true)[:title]")
          if section
            @sections << section
            sections_made += 1
            # look for emtpy tables and warn if skipped because returned empty
            section[:tables].each do |table|
              if not table
                runner.registerWarning("A table in #{display_name} section returned false and was skipped.")
                section[:messages] = ["One or more tables in #{display_name} section returned false and was skipped."]
              end
            end
          else
            runner.registerWarning("#{display_name} section returned false and was skipped.")
            section = {}
            section[:title] = "#{display_name}"
            section[:tables] = []
            section[:messages] = []
            section[:messages] << "#{display_name} section returned false and was skipped."
            @sections << section
          end
        rescue => e
          display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true)[:title]")
          if display_name == nil then display_name == method_name end
          runner.registerWarning("#{display_name} section failed and was skipped because: #{e}. Detail on error follows.")
          runner.registerWarning("#{e.backtrace.join("\n")}")

          # add in section heading with message if section fails
          section = {}
          section[:messages] = []
          section[:messages] << "#{display_name} section failed and was skipped because: #{e}. Detail on error follows."
          section[:messages] << ["#{e.backtrace.join("\n")}"]
          @sections << section

        end

      end

    else
      wrong_tabular_units_string = "IP units were provided, SI units were expected. Leave EnergyPlus tabular results in SI units to run this report."
      runner.registerWarning(wrong_tabular_units_string)
      section = {}
      section[:title] = "Tabular EnergyPlus results provided in wrong units."
      section[:tables] = []
      section[:messages] = []
      section[:messages] << wrong_tabular_units_string
      @sections << section
    end

    # read in template
    html_in_path = "#{File.dirname(__FILE__)}/resources/report.html.erb"
    if File.exist?(html_in_path)
      html_in_path = html_in_path
    else
      html_in_path = "#{File.dirname(__FILE__)}/report.html.erb"
    end
    html_in = ''
    File.open(html_in_path, 'r') do |file|
      html_in = file.read
    end

    # configure template with variable values
    renderer = ERB.new(html_in)
    html_out = renderer.result(binding)

    # write html file
    html_out_path = './report.html'
    File.open(html_out_path, 'w') do |file|
      file << html_out
      # make sure data is written to the disk one way or the other
      begin
        file.fsync
      rescue
        file.flush
      end
    end

    # adding additional runner.registerValues needed for project scripts in 2.x PAT
    # note: these are not in begin rescue like individual sections. Won't fail gracefully if any SQL query's can't be found

    # annual_peak_electric_demand
    annual_peak_electric_demand_k_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='DemandEndUseComponentsSummary' and ReportForString='Entire Facility' and TableName='End Uses' and RowName= 'Total End Uses' and ColumnName='Electricity' and Units='W'"
    annual_peak_electric_demand_kw = OpenStudio.convert(sql_file.execAndReturnFirstDouble(annual_peak_electric_demand_k_query).get, 'W', 'kW').get
    runner.registerValue('annual_peak_electric_demand',annual_peak_electric_demand_kw,'kW')

    # get base year for use in first_year_cap_cost
    baseYrString_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' and ReportForString='Entire Facility' and TableName='Life-Cycle Cost Parameters' and RowName= 'Base Date' and ColumnName= 'Value'"
    baseYrString = sql_file.execAndReturnFirstString(baseYrString_query).get
    # get first_year_cap_cost
    first_year_cap_cost_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' and ReportForString='Entire Facility' and TableName='Capital Cash Flow by Category (Without Escalation)' and RowName= '#{baseYrString}' and ColumnName= 'Total'"
    first_year_cap_cost = sql_file.execAndReturnFirstDouble(first_year_cap_cost_query).get
    runner.registerValue('first_year_capital_cost',first_year_cap_cost,'$')

    # annual_utility_cost
    annual_utility_cost = sql_file.annualTotalUtilityCost
    if annual_utility_cost.is_initialized
      runner.registerValue('annual_utility_cost',annual_utility_cost.get,'$')
    else
      runner.registerValue('annual_utility_cost',0.0,'$')
    end

    # total_lifecycle_cost
    total_lifecycle_cost_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' and ReportForString='Entire Facility' and TableName='Present Value by Year' and RowName= 'TOTAL' and ColumnName= 'Present Value of Costs'"
    runner.registerValue('total_lifecycle_cost',sql_file.execAndReturnFirstDouble(total_lifecycle_cost_query).get,'$')

    # closing the sql file
    sql_file.close

    # reporting final condition
    runner.registerFinalCondition("Generated report with #{sections_made} sections to #{html_out_path}.")

    true
  end # end the run method
end # end the measure

# this allows the measure to be use by the application
OpenStudioResults.new.registerWithApplication
