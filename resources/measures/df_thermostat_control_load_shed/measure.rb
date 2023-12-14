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

# require all .rb files in resources folder
Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }

require 'openstudio'
require 'date'
require 'openstudio-standards'

# start the measure
class DfThermostatControlLoadShed < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return "df thermostat control load shed"
  end

  # human readable description
  def description
    return "tbd"
  end

  # human readable description of modeling approach
  def modeler_description
    return "tbd"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    input_path = OpenStudio::Ruleset::OSArgument::makeStringArgument("input_path",true)
    input_path.setDisplayName("Path to weather file (epw)")
    input_path.setDefaultValue("C:/Users/jxiong/Documents/GitHub/ComStock/resources/measures/dispatch_schedule_generation/tests/in.epw")
    args << input_path

    peak_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('peak_len', true)
    peak_len.setDisplayName("Length of dispatch window (hour)")
    peak_len.setDefaultValue(4)
    args << peak_len

    rebound_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('rebound_len', true)
    rebound_len.setDisplayName("Length of rebound period after dispatch window (hour)")
    rebound_len.setDefaultValue(2)
    args << rebound_len

    output_path = OpenStudio::Ruleset::OSArgument::makeStringArgument("output_path",true)
    output_path.setDisplayName("Path to output data CSV. INCLUDE .CSV EXTENSION")
    output_path.setDefaultValue("../outputs/output.csv")
    args << output_path

    sample_num_timesteps_in_hr = OpenStudio::Measure::OSArgument.makeIntegerArgument('sample_num_timesteps_in_hr', true)
    sample_num_timesteps_in_hr.setDisplayName("Number/Count of timesteps in an hour for sample simulations")
    sample_num_timesteps_in_hr.setDefaultValue(4)
    args << sample_num_timesteps_in_hr

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    ############################################
    # use the built-in error checking
    ############################################
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    ############################################
    # assign the user inputs to variables
    ############################################
    weather_file = runner.getStringArgumentValue("input_path",user_arguments)
    peak_len = runner.getIntegerArgumentValue("peak_len",user_arguments)
    rebound_len = runner.getIntegerArgumentValue("rebound_len",user_arguments)
    output_path = runner.getStringArgumentValue("output_path",user_arguments)
    sample_num_timesteps_in_hr = runner.getIntegerArgumentValue("sample_num_timesteps_in_hr",user_arguments)

    ############################################
    # For bin-sample run
    ############################################
    puts("### ============================================================")
    puts("### Reading weather file...")
    year, oat = read_epw(weather_file)
    puts("--- year = #{year}")
    puts("--- oat = #{year}")
    puts("--- Weather file read!")

    puts("### ============================================================")
    puts("### Creating bins...")
    bins, selectdays, ns = create_binsamples(oat)
    puts("--- bins = #{bins}")
    puts("--- selectdays = #{selectdays}")
    puts("--- ns = #{ns}")

    puts("### ============================================================")
    puts("### Running simulation on samples...")
    y_seed = run_samples(model, year, selectdays)
    puts("--- y_seed = #{y_seed}")

    puts("### ============================================================")
    puts("### Creating annual prediction...")
    annual_load = load_prediction_from_sample(y_seed, bins)
    puts("--- annual_load = #{annual_load}")
    puts("--- annual_load.class = #{annual_load.class}")

    puts("### ============================================================")
    puts("### Creating peak schedule...")
    start_time = Time.now
    peak_schedule = peak_schedule_generation(annual_load, peak_len, rebound_len)
    end_time = Time.now
    puts("--- start_time = #{start_time}")
    puts("--- end_time = #{end_time}")
    puts("--- elapsed time = #{end_time - start_time} seconds")
    puts("--- peak_schedule = #{peak_schedule}")
    
    return true
  end
end

# register the measure to be used by the application
DfThermostatControlLoadShed.new.registerWithApplication
