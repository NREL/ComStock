# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
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

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'

require_relative '../measure.rb'
require 'minitest/autorun'

class ChangeBuildingLocation_Test < Minitest::Test
  def run_dir(test_name)
    # will make directory if it doesn't exist
    output_dir = File.expand_path('output', File.dirname(__FILE__))
    FileUtils.mkdir output_dir unless Dir.exist? output_dir

    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  # method to apply arguments, run measure, and assert results (only populate args hash with non-default argument values)
  def apply_measure_to_model(test_name, args, model_name = nil, result_value = 'Success', warnings_count = 0, info_count = nil, num_dsn_days = 3, soil_conductivity = 1.8)
    # create an instance of the measure
    measure = ChangeBuildingLocation.new

    # create an instance of a runner with OSW
    osw_path = OpenStudio::Path.new(File.dirname(__FILE__) + '/test.osw')
    osw = OpenStudio::WorkflowJSON.load(osw_path).get
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # get model
    if model_name.nil?
      # make an empty model
      model = OpenStudio::Model::Model.new
    else
      # load the test model
      translator = OpenStudio::OSVersion::VersionTranslator.new
      path = OpenStudio::Path.new(File.dirname(__FILE__) + '/' + model_name)
      model = translator.loadModel(path)
      assert(!model.empty?)
      model = model.get
    end

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args.key?(arg.name)
        assert(temp_arg_var.setValue(args[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # temporarily change directory to the run directory and run the measure (because of sizing run)
    start_dir = Dir.pwd
    begin
      unless Dir.exist?(run_dir(test_name))
        Dir.mkdir(run_dir(test_name))
      end
      Dir.chdir(run_dir(test_name))

      # run the measure
      measure.run(model, runner, argument_map)
      result = runner.result
    ensure
      Dir.chdir(start_dir)

      # delete sizing run dir
      FileUtils.rm_rf(run_dir(test_name))
    end

    # show the output
    puts "measure results for #{test_name}"
    show_output(result)

    # assert that it ran correctly
    if result_value.nil? then result_value = 'Success' end
    assert_equal(result_value, result.value.valueName)

    # check count of warning and info messages
    unless info_count.nil? then assert(result.info.size == info_count) end
    unless warnings_count.nil? then assert(result.warnings.size == warnings_count) end

    # if 'Fail' passed in make sure at least one error message (while not typical there may be more than one message)
    if result_value == 'Fail' then assert(result.errors.size >= 1) end

    # For tests expected to succeed, check for design days in the model
    if result.value.valueName == 'Success'
      assert_equal(num_dsn_days, model.getDesignDays.size, "Expected #{num_dsn_days} but found #{model.getDesignDays.size}.")
    end

    # For tests expected to succeed, check for soil conductivity value
    if result.value.valueName == 'Success'
      assert_equal(soil_conductivity, model.getBuilding.additionalProperties.getFeatureAsDouble('Soil Conductivity').to_f.round(1), "Expected soil conductivity #{soil_conductivity} but found #{model.getBuilding.additionalProperties.getFeatureAsDouble('Soil Conductivity')}.")
    end

    # save the model to test output directory
    output_file_path = OpenStudio::Path.new(File.dirname(__FILE__) + "/output/#{test_name}_test_output.osm")
    model.save(output_file_path, true)
  end

  def test_weather_file
    args = {}
    args['weather_file_name'] = 'USA_MA_Boston-Logan.Intl.AP.725090_TMY3.epw' # seems to search directory of OSW even with empty file_paths
    apply_measure_to_model(__method__.to_s.gsub('test_', ''), args, 'test.osm', nil, nil, nil)
  end

  def test_weather_file_WA_Renton
    args = {}
    args['weather_file_name'] = 'USA_WA_Renton.Muni.AP.727934_TMY3.epw' # seems to search directory of OSW even with empty file_paths
    args['set_year'] = 2012
    apply_measure_to_model(__method__.to_s.gsub('test_', ''), args, 'test.osm', nil, 2, nil, 0)
  end

  def test_multiyear_weather_file
    args = {}
    args['weather_file_name'] = 'multiyear.epw' # seems to search directory of OSW even with empty file_paths
    apply_measure_to_model(__method__.to_s.gsub('test_', ''), args, 'test.osm', nil, nil, nil)
  end

  def test_weather_file_bad
    args = {}
    args['weather_file_name'] = 'BadFileName.epw' # seems to search directory of OSW even with empty file_paths
    apply_measure_to_model(__method__.to_s.gsub('test_', ''), args, 'test.osm', 'Fail', nil, nil)
  end

  def weather_file_monthly_design_days
    args = {}
    args['weather_file_name'] = 'CA_LOS-ANGELES-IAP_722950S_12.epw' # seems to search directory of OSW even with empty file_paths
    apply_measure_to_model(__method__.to_s.gsub('test_', ''), args, 'test.osm', nil, nil, nil, 10)
  end

  def test_soil_conductivity
    args = {}
    args['weather_file_name'] = 'CA_LOS-ANGELES-IAP_722950S_12.epw'
	args['climate_zone'] = 'T24-CEC8'
	args['year'] = '2018'
	args['soil_conductivity'] = 1.8
    apply_measure_to_model(__method__.to_s.gsub('test_', ''), args, 'test.osm', nil, nil, nil, 14, 1.8)
  end
end
