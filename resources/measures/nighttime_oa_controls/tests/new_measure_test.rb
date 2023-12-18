# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'

#puts NighttimeOAControls.methods.sort
#puts NighttimeOAControls.singleton_methods.sort
puts NighttimeOAControls.instance_methods.sort


class NewMeasureTest < Minitest::Test
  # def setup
  # end

  # def teardown
  # end
  def model_input_path(osm_name)
    # return models_for_tests.select { |x| set[:model] == osm_name }
    #return File.join(File.dirname(__FILE__), '../../../tests/models', osm_name)
	return File.join(File.dirname(__FILE__), '/models', osm_name)
  end
  
  def epw_input_path(epw_name)
    #runner.registerInfo("file name #{File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)}")
    #return File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
	return File.join(File.dirname(__FILE__), '/weather', epw_name)
  end
  
 def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    return model
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end
  
   def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end
  
 def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, model: nil)
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))

    # create run directory if it does not exist
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # remove prior runs if they exist
    if File.exist?(model_output_path(test_name))
      FileUtils.rm(model_output_path(test_name))
    end
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    # copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)
    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    if model.nil?
      model = load_model(new_osm_path)
    end

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'

    # Show the output
    show_output(result)

    # Save model
    model.save(model_output_path(test_name), true)

    if run_model && result_success
      puts "\nRUNNING MODEL..."

      std = Standard.build('90.1-2013')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # Check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # change back directory
    Dir.chdir(start_dir)

    return result
  end
  
  #test for a particula rbuilding type 
  def test_361_warehouse_pvav
   
   # this makes sure measure registers an na for non applicable model
    osm_name = '361_Warehouse_PVAV_2a_vent_mod_v2.osm'
    epw_name = 'TX_Port_Arthur_Jeffers_722410_16.epw'

    osm_path = model_input_path(osm_name)
	osm_path_output = model_output_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = NighttimeOAControls.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
	
	# Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
	#result = apply_measure_and_run(__method__, measure, osm_path, epw_path, run_model: true)
    assert_equal('Success', result.value.valueName)
	
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)
	
	#load model with measure applied 
	#model = load_model(osm_path_output)
	
    # loop through air loops
    unitary_system_count = 0
    li_unitary_systems = []
    non_unitary_system_count = 0
    li_non_unitary_systems = []
	print('test') 
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
	  puts("in loop")
      # skip systems that are residential, use evap coolers, or are DOAS
      next if NighttimeOAControls.air_loop_res?(air_loop_hvac)
      next if NighttimeOAControls.air_loop_evaporative_cooler?(air_loop_hvac)
      next if NighttimeOAControls.air_loop_doas?(air_loop_hvac)
      # skip data centers
      next if ['Data Center', 'DataCenter', 'data center', 'datacenter', 'DATACENTER', 'DATA CENTER'].any? { |word| (air_loop_hvac.name.get).include?(word) }
      # check unitary systems
      if NighttimeOAControls.air_loop_hvac_unitary_system?(air_loop_hvac)
        unitary_system_count += 1
        li_unitary_systems << air_loop_hvac
      else
        li_non_unitary_systems << air_loop_hvac
        non_unitary_system_count += 1
      end
    end
	
    li_non_unitary_systems.sort.each do |air_loop_hvac|

      # change night OA schedule to match hvac operation schedule for no night OA
      #case rtu_night_mode
      #when 'night_fancycle_novent'
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
       if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
             air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
             min_oa_sched = air_loop_oa_system.minimumOutdoorAirSchedule.get()
			 if min_oa_sched.to_ScheduleRuleset.is_initialized
			    puts('sched loop')
			    min_oa_sched = min_oa_sched.to_ScheduleRuleset.get
			    puts(min_oa_sched)
			end 
			if min_oa_sched.to_ScheduleConstant.is_initialized
			    puts('sched loop')
			    min_oa_sched = min_oa_sched.to_ScheduleConstant.get
			    puts(min_oa_sched)
			end 
       end 
      #end
	  
	  end 

    end
	
	def test_361_warehouse_pvav_post
	    osm_name = '361_Warehouse_PVAV_2a_vent_mod_v2.osm'
        epw_name = 'TX_Port_Arthur_Jeffers_722410_16.epw'
		osm_path_output = model_output_path(osm_name)
	    model = load_model("C://Users//aallen//Documents//GitHub//ComStock//resources//measures//nighttime_oa_controls//tests//output//test_361_warehouse_pvav_na//run//in.osm") 
		    unitary_system_count = 0
    li_unitary_systems = []
    non_unitary_system_count = 0
    li_non_unitary_systems = []
	print('test') 
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
	  puts("in loop")
      # skip systems that are residential, use evap coolers, or are DOAS
      next if NighttimeOAControls.air_loop_res?(air_loop_hvac)
      next if NighttimeOAControls.air_loop_evaporative_cooler?(air_loop_hvac)
      next if NighttimeOAControls.air_loop_doas?(air_loop_hvac)
      # skip data centers
      next if ['Data Center', 'DataCenter', 'data center', 'datacenter', 'DATACENTER', 'DATA CENTER'].any? { |word| (air_loop_hvac.name.get).include?(word) }
      # check unitary systems
      if NighttimeOAControls.air_loop_hvac_unitary_system?(air_loop_hvac)
        unitary_system_count += 1
        li_unitary_systems << air_loop_hvac
      else
        li_non_unitary_systems << air_loop_hvac
        non_unitary_system_count += 1
      end
    end
	
    li_non_unitary_systems.sort.each do |air_loop_hvac|

      # change night OA schedule to match hvac operation schedule for no night OA
      #case rtu_night_mode
      #when 'night_fancycle_novent'
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
       if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
             air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
             min_oa_sched = air_loop_oa_system.minimumOutdoorAirSchedule.get()
			 puts ('in simulated loop')
			 if min_oa_sched.to_ScheduleRuleset.is_initialized
			    puts('sched simulated loop')
			    min_oa_sched = min_oa_sched .to_ScheduleRuleset.get
			    puts(min_oa_sched)
			end 
			if min_oa_sched.to_ScheduleConstant.is_initialized
			    puts('sched simulated loop')
			    min_oa_sched = min_oa_sched.to_ScheduleConstant.get
			    puts(min_oa_sched)
			end 
       end 
      #end
	  
	  end 
		
	
	
	end 
	
	
end
