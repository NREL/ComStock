# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'
require_relative '../../../../test/helpers/minitest_helper'

# require all .rb files in resources folder
Dir[File.dirname(__FILE__) + '../resources/*.rb'].each { |file| require file }

class DfThermostatControlLoadShiftTest < Minitest::Test
  # def setup
  # end

  # def teardown
  # end

  # return file paths to test models in test directory
  def models_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/models/*.osm'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  # return file paths to epw files in test directory
  def epws_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/weather/*.epw'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []

    # test: not applicable building type
    test_sets << {
      model: '361_Medium_Office_PSZ_HP',
      weather: 'CO_FortCollins_16',
      result: 'NA'
    }
    test_sets << {
      model: 'LargeOffice_VAV_chiller_boiler',
      weather: 'CO_FortCollins_16',
      result: 'Success'
    }
    test_sets << {
      model: 'LargeOffice_VAV_chiller_boiler_2',
      weather: 'CO_FortCollins_16',
      result: 'Success'
    }
    test_sets << {
      model: 'LargeOffice_VAV_district_chw_hw',
      weather: 'CO_FortCollins_16',
      result: 'NA'
    }

    return test_sets
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

  def model_input_path(osm_name)
    # return models_for_tests.select { |x| set[:model] == osm_name }
    return File.join(File.dirname(__FILE__), '../../../tests/models', osm_name)
  end

  def epw_input_path(epw_name)
    return File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
  end

  def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  # applies the measure and then runs the model
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false)
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
    model = load_model(new_osm_path)

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'

    # show the output
    show_output(result)

    # save model
    model.save(model_output_path(test_name), true)

    if run_model && result_success
      puts "\nRUNNING MODEL..."

      std = Standard.build('90.1-2013')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # change back directory
    Dir.chdir(start_dir)

    return result
  end

  def test_models
    test_name = 'test_models'
    puts "\n######\nTEST:#{test_name}\n######\n"

    models_to_test.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # create an instance of the measure
      measure = DfThermostatControlLoadShift.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      # set arguments:
      peak_len = arguments[0].clone
      assert(peak_len.setValue(4))
      argument_map['peak_len'] = peak_len

      # set arguments:
      prepeak_len = arguments[1].clone
      assert(prepeak_len.setValue(2))
      argument_map['prepeak_len'] = prepeak_len

      # set arguments:
      sp_adjustment = arguments[2].clone
      assert(sp_adjustment.setValue(2.0))
      argument_map['sp_adjustment'] = sp_adjustment

      # set arguments:
      num_timesteps_in_hr = arguments[3].clone
      assert(num_timesteps_in_hr.setValue(4))
      argument_map['num_timesteps_in_hr'] = num_timesteps_in_hr

      # set arguments:
      load_prediction_method = arguments[4].clone
      assert(load_prediction_method.setValue('part year bin sample'))#'bin sample''full baseline'
      argument_map['load_prediction_method'] = load_prediction_method

      # apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

      # check the measure result; result values will equal Success, Fail, or Not Applicable (NA)
      # also check the amount of warnings, info, and error messages
      # use if or case statements to change expected assertion depending on model characteristics
      assert(result.value.valueName == set[:result])

      # to check that something changed in the model, load the model and the check the objects match expected new value
      model = load_model(model_output_path(instance_test_name))

    end
  end

  # def dispatch_gen_create_binsamples_test
  #   oat_harcoded = []
  #   bins_hardcoded =
  #   selectdays_hardcoded =
  #   ns_hardcoded =

  #   puts("### ============================================================")
  #   puts("### Creating bins...")
  #   bins, selectdays, ns = create_binsamples(oat_harcoded)
  #   puts("--- bins = #{bins}")
  #   puts("--- selectdays = #{selectdays}")
  #   puts("--- ns = #{ns}")

  #   assert(bins == bins_hardcoded)
  #   assert(selectdays == selectdays_hardcoded)
  #   assert(ns == ns_hardcoded)
  # end

  # def dispatch_gen_run_samples_test(model)
  #   year_hardcoded =
  #   selectdays_hardcoded =
  #   num_timesteps_in_hr_hardcoded =
  #   y_seed_harcoded =

  #   puts("### ============================================================")
  #   puts("### Running simulation on samples...")
  #   y_seed = run_samples(model, year, selectdays, num_timesteps_in_hr)

  #   assert(y_seed == y_seed_hardcoded)
  # end

  # def test_dispatch_gen_small_run
  #   osm_name = '361_Medium_Office_PSZ_HP.osm'
  #   # osm_name = 'LargeOffice_VAV_chiller_boiler_2.osm'
  #   epw_name = 'CO_FortCollins_16.epw'
  #   osm_path = model_input_path(osm_name)
  #   epw_path = epw_input_path(epw_name)
  #   model = load_model(osm_path)

  #   oat_harcoded = []
  #   bins_hardcoded = {
  #     'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => Array(1..365), 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
  #   }
  #   selectdays_hardcoded = {
  #     'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [200], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
  #   }
  #   ns_hardcoded = 1
  #   year_hardcoded = 2018
  #   num_timesteps_in_hr_hardcoded = 4
  #   y_seed_harcoded = {
  #     'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
  #     'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
  #   }

  #   puts("============================================================")
  #   puts("### Reading weather file...")
  #   year, oat = read_epw(model, epw_path)
  #   puts("--- year = #{year}")
  #   puts("--- oat.size = #{oat.size}")

  #   puts("============================================================")
  #   puts("### Creating bins...")
  #   bins, selectdays, ns, max_doy = create_binsamples(oat)
  #   puts("--- bins = #{bins}")
  #   puts("--- selectdays = #{selectdays}")
  #   puts("--- ns = #{ns}")
  #   # assert(bins == bins_hardcoded)
  #   # assert(selectdays == selectdays_hardcoded)

  #   # puts("============================================================")
  #   # puts("### Running simulation on samples...")
  #   # y_seed = run_samples(model, year=year_hardcoded, selectdays=selectdays_hardcoded, num_timesteps_in_hr=num_timesteps_in_hr_hardcoded, epw_path=epw_path)
  #   # puts("--- y_seed = #{y_seed}")
  #   # # assert(y_seed == y_seed_harcoded)

  #   puts("============================================================")
  #   puts("### Running simulation on part year samples...")
  #   y_seed = run_part_year_samples(model, year=year_hardcoded, max_doy=max_doy, selectdays=selectdays_hardcoded, num_timesteps_in_hr=num_timesteps_in_hr_hardcoded, epw_path=epw_path)
  #   puts("--- y_seed = #{y_seed}")
  #   # assert(y_seed == y_seed_harcoded)

  #   puts("============================================================")
  #   puts("### Creating annual prediction...")
  #   annual_load = load_prediction_from_sample(y_seed, bins=bins_hardcoded)
  #   # puts("--- annual_load = #{annual_load}")
  #   puts("--- annual_load.class = #{annual_load.class}")
  #   puts("--- annual_load.size = #{annual_load.size}")

  #   puts("============================================================")
  #   puts("### Creating peak schedule...")
  #   peak_schedule = peak_schedule_generation(annual_load, peak_len=4, prepeak_len=2)
  #   # puts("--- peak_schedule = #{peak_schedule}")
  #   puts("--- peak_schedule.size = #{peak_schedule.size}")

  #   # assert()
  # end

end
