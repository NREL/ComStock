# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'erb'
require 'json'
require 'openstudio-standards'

# start the measure
class LA100QAQC < OpenStudio::Measure::ReportingMeasure
  # require all .rb files in resources folder
  Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }

  # all QAQC checks should be in OsLib_QAQC module
  include OsLib_QAQC
  include OsLib_CreateResults
  include DEERVintages

  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return "LA100QAQC"
  end

  # human readable description
  def description
    return "This measure extracts key simulation results and performs basic model QAQC checks necessary for the LA100 Project."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Reads the model and sql file to pull out the necessary information and run the model checks.  The check results show up as Warning messages in the measure's output on the PAT run tab."
  end

  # define the arguments that the user will input
  def arguments(model=nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument to toggle QAQC
    run_qaqc = OpenStudio::Measure::OSArgument.makeBoolArgument('run_qaqc', true)
    run_qaqc.setDisplayName('Run QAQC?:')
    run_qaqc.setDescription('If set to true, will run this QAQC measure, adding in many substantial output variables.')
    run_qaqc.setDefaultValue(false)
    args << run_qaqc

    return args
  end # end the arguments method

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return result
    end

    # get the last model
    model = runner.lastOpenStudioModel
    if model.empty?
      puts 'Cannot find last model for output requests'
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    run_qaqc = runner.getBoolArgumentValue('run_qaqc', user_arguments)
    unless run_qaqc
      return result
    end

    # Request output variables for air loop and plant loop supply outlet nodes
    variable_names = ['System Node Temperature', 'System Node Standard Density Volume Flow Rate']
    reporting_frequency = 'Timestep'
    node_names = []
    model.getAirLoopHVACs.each do |air_loop|
      node_names << air_loop.supplyOutletNode.name.to_s
    end
    model.getPlantLoops.each do |plant_loop|
      node_names << plant_loop.supplyOutletNode.name.to_s
    end
    node_names.uniq!
    node_names.each do |node_name|
      variable_names.each do |variable_name|
        result << OpenStudio::IdfObject.load("Output:Variable,#{node_name},#{variable_name},#{reporting_frequency};").get
      end
    end

    # Request equipment part load ratios
    result << OpenStudio::IdfObject.load('Output:Variable,*,Boiler Part Load Ratio,Hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Chiller Part Load Ratio,Hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Cooling Tower Fan Electric Power,Hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Cooling Coil Total Cooling Rate,Hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Heating Coil Heating Rate,Hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Heating Coil Air Heating Rate,Hourly;').get

    # Request the terminal reheat coil and terminal cooling rates for every VAV reheat terminal.
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      # Reheat coil heating rate
      rht_coil = term.reheatCoil
      rht_coil_name = rht_coil.name.get.to_s.upcase
      case rht_coil.iddObjectType.valueName.to_s
      when 'OS_Coil_Heating_Electric', 'OS_Coil_Heating_Gas'
        result << OpenStudio::IdfObject.load("Output:Variable,#{rht_coil_name},Heating Coil Air Heating Rate,Hourly;").get
      when 'OS_Coil_Heating_Water'
        result << OpenStudio::IdfObject.load("Output:Variable,#{rht_coil_name},Heating Coil Heating Rate,Hourly;").get
      end
    end

    # Zone Air Terminal Sensible Heating Rate
    result << OpenStudio::IdfObject.load("Output:Variable,*,Zone Air Terminal Sensible Cooling Rate,Hourly;").get

    # ventilation flow rates
    result << OpenStudio::IdfObject.load("Output:Variable,*,Zone Mechanical Ventilation Standard Density Volume Flow Rate,#{reporting_frequency};").get

    # Request the day type to use in the peak demand window checks.
    result << OpenStudio::IdfObject.load('Output:Variable,*,Site Day Type Index,timestep;').get

    return result
  end

  # get feature string
  def get_bldg_feature_string(model, feature_name)
    feature_string = nil
    props = model.getBuilding.additionalProperties
    if props.getFeatureAsString(feature_name).is_initialized
      feature_string = props.getFeatureAsString(feature_name).get
    end
    return feature_string
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # make the runner a class variable
    @runner = runner

    # if true errors on QAQC sections will show full backtrace. Use for diagnostics
    @error_backtrace = true

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return false
    end

    run_qaqc = runner.getBoolArgumentValue('run_qaqc', user_arguments)
    unless run_qaqc
      return true
    end

    runner.registerInitialCondition('Starting QAQC report generation')

    # get sql, model, and web assets
    setup = OsLib_Reporting.setup(runner)
    unless setup
      return false
    end
    @model = setup[:model]
    # workspace = setup[:workspace]
    @sql = setup[:sqlFile]
    web_asset_path = setup[:web_asset_path]

    # vector to store the results and checks
    time_a = Time.new
    report_elems = OpenStudio::AttributeVector.new
    report_elems << create_results(skip_weekends = false,
                                   skip_holidays = false,
                                   start_mo = 'January',
                                   start_day = 1,
                                   start_hr = 1,
                                   end_mo = 'December',
                                   end_day = 31,
                                   end_hr = 24)
    time_b = Time.new
    delta_time = time_b.to_f - time_a.to_f
    runner.registerInfo("Gathering results: elapsed time #{delta_time.round(1)} seconds.")

    # utility name to to used by some qaqc checks
    @utility_name = 'LADWP'

    # get building type, different standards path if multifamily
    building_type = ''
    if @model.getBuilding.standardsBuildingType.is_initialized
      building_type = @model.getBuilding.standardsBuildingType.get
    end

    # get building template features
    runner.registerInfo("Getting building features.")
    hvac_system_type = get_bldg_feature_string(@model, 'hvac_system_type')
    target_envelope_standard = get_bldg_feature_string(@model, 'envelope_template')
    if target_envelope_standard.nil?
      runner.registerInfo("'set_envelope_template measure' did not have argument 'template' set; using DEER 2003")
      target_envelope_standard = 'DEER 2003'
    end

    # using lighting as the internal loads standard for comparison
    # @todo separate internal loads into lighting, equipment, and occupancy
    target_internal_loads_standard = get_bldg_feature_string(@model, 'interior_lighting_template')
    if target_internal_loads_standard.nil?
      runner.registerInfo("'set_interior_lighting_template measure' did not have argument 'template' set; using DEER 2003")
      target_internal_loads_standard = 'DEER 2003'
    end

    target_hvac_standard = get_bldg_feature_string(@model, 'hvac_template')
    if target_hvac_standard.nil?
      runner.registerInfo("'set_hvac_template measure' did not have argument 'template' set; using DEER 2003")
      target_hvac_standard = 'DEER 2003'
    end

    # create an attribute vector to hold the checks
    check_elems = OpenStudio::AttributeVector.new

    # call individual checks and add to vector

    # envelope checks
    runner.registerInfo("Comparing model envelope to defaults from #{target_envelope_standard}.")
    check_elems << check_envelope_conductance('Baseline', target_envelope_standard)

    # internal load checks
    runner.registerInfo("Comparing model internal loads to defaults from #{target_internal_loads_standard}.")
    check_elems << check_internal_loads('Baseline', target_internal_loads_standard)
    check_elems << check_internal_loads_schedules('Baseline', target_internal_loads_standard)
    check_elems << check_plenum_loads('General', target_internal_loads_standard)
    check_elems << check_occ_zones_conditioned('General', target_internal_loads_standard)
    check_elems << check_sch_coord('General', target_internal_loads_standard)

    # hvac system checks
    runner.registerInfo("Comparing model hvac to defaults from #{target_hvac_standard}.")
    check_elems << check_mech_sys_capacity('General', target_hvac_standard)
    check_elems << check_plant_cap('General', target_hvac_standard)
    check_elems << check_fan_power('General', target_hvac_standard)
    check_elems << check_pump_power('General', target_hvac_standard)
    check_elems << check_mech_sys_efficiency('Baseline', target_hvac_standard)
    check_elems << check_mech_sys_part_load_eff('General', target_hvac_standard)
    check_elems << check_supply_air_and_thermostat_temp_difference('Baseline', target_hvac_standard)
    check_elems << check_air_loop_temps('General')
    check_elems << check_plant_temps('General')
    check_elems << check_part_loads('General')
    check_elems << check_simultaneous_heating_and_cooling('General')

    # unmet hours by system type
    case hvac_system_type
    when 'No HVAC (Unconditioned)'
      runner.registerInfo("HVAC system type is '#{hvac_system_type}. Unmet hours expected.")
      check_elems << check_unmet_hours('General', target_hvac_standard, expect_clg_unmet_hrs: true, expect_htg_unmet_hrs: true)
    when 'Baseboard district hot water heat',
        'Baseboard electric heat',
        'Baseboard hot water heat',
        'Unit heaters',
        'Heat pump heat with no cooling',
        'Residential forced air',
        'Forced air furnace',
        'No Cooling with Electric Heat',
        'No Cooling with Gas Furnace'
      runner.registerInfo("HVAC system type is '#{hvac_system_type}. Checking for only heating unmet hours.")
      check_elems << check_unmet_hours('General', target_hvac_standard, expect_clg_unmet_hrs: true, expect_htg_unmet_hrs: false)
    when 'PTAC with no heat',
        'PSZ-AC with no heat',
        'Fan coil district chilled water with no heat',
        'Fan coil chiller with no heat',
        'Window AC with no heat',
        'Direct evap coolers',
        'Residential AC with no heat'
      runner.registerInfo("HVAC system type is '#{hvac_system_type}. Checking for only cooling unmet hours.")
      check_elems << check_unmet_hours('General', target_hvac_standard, expect_clg_unmet_hrs: false, expect_htg_unmet_hrs: true)
    else
      runner.registerInfo("HVAC system type is '#{hvac_system_type}. Checking for heating and cooling unmet hours.")
      check_elems << check_unmet_hours('General', target_hvac_standard, expect_clg_unmet_hrs: false, expect_htg_unmet_hrs: false)
    end

    # diagnostic scripts to implement
    # check_elems << check_geometry()
    # check_elems << check_coil_controllers()
    # check_elems << check_zone_outdoor_air()

    # diagnostic scripts unused
    # check_elems << check_la_weather_files()
    # check_elems << check_calibration()

    # add checks to report_elems
    report_elems << OpenStudio::Attribute.new('checks', check_elems)

    # create an extra layer of report.  the first level gets thrown away.
    top_level_elems = OpenStudio::AttributeVector.new
    top_level_elems << OpenStudio::Attribute.new('report', report_elems)

    # create the report
    result = OpenStudio::Attribute.new('summary_report', top_level_elems)
    result.saveToXml(OpenStudio::Path.new('report.xml'))

    # closing the sql file
    @sql.close

    # reporting final condition
    runner.registerFinalCondition('Finished generating report.xml.')

    # populate sections using attributes
    sections = OsLib_Reporting.sections_from_check_attributes(check_elems, runner)

    # generate html output
    OsLib_Reporting.gen_html("#{File.dirname(__FILE__)}report.html.erb", web_asset_path, sections, name)

    return true
  end # end the run method
end # end the measure

# this allows the measure to be use by the application
LA100QAQC.new.registerWithApplication
