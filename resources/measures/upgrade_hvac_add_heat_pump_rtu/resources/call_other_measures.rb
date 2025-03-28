# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2020, Alliance for Sustainable Energy, LLC.
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

# pass relevant messages/results/variables to parent runner
def child_to_parent_runner_logging(runner_parent, measure_name, results_child, registered_var_list = [])
  # Log warnings/infos/errors
  results_child.warnings.each do |warning|
    runner_parent.registerWarning(warning.logMessage)
  end
  results_child.info.each do |info|
    runner_parent.registerInfo(info.logMessage)
  end
  results_child.errors.each do |error|
    runner_parent.registerError(error.logMessage)
  end

  # Check if the measure ran successfully
  case results_child.value.valueName
  when 'Success'
    runner_parent.registerInfo("Child measure (#{measure_name}) was applied successfully.")
    # Register values from child runner to parent runner
    unless registered_var_list.empty?
      registered_var_list.each do |registered_var|
        JSON.parse(results_child.to_s)['step_values'].each do |step_value|
          if step_value['name'].to_s == registered_var
            runner_parent.registerValue(registered_var, step_value['value'], step_value['units'])
          end
        end
      end
    end
  when 'NA'
    runner_parent.registerInfo("Child measure (#{measure_name}) was not applicable.")
  else
    runner_parent.registerError("Child measure (#{measure_name}) failed.")
    false
  end

  runner_parent
end

# create methods to call other measures for package runs
# putting this code in a resource file prevents issues with the OS app parsing
def call_roof(model, runner)
  roof_measure_path = File.join(__dir__, '../../upgrade_env_roof_insul_aedg/measure.rb')
  unless File.exist?(roof_measure_path)
    runner.registerError('Roof Insulation measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.')
    return false
  end
  require roof_measure_path

  roof_measure = EnvRoofInsulAedg.new
  runner_roof = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
  roof_measure.run(model, runner_roof, OpenStudio::Measure::OSArgumentMap.new)
  roof_result = runner_roof.result

  runner = child_to_parent_runner_logging(runner, roof_measure.name.to_s, roof_result, registered_var_list = ['env_roof_insul_roof_area_ft_2'])

  return roof_result, runner
end

def call_windows(model, runner)
  windows_measure_path = File.join(__dir__, '../../upgrade_env_new_aedg_windows/measure.rb')
  unless File.exist?(windows_measure_path)
    runner.registerError('New Windows measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.')
    return false
  end
  require windows_measure_path

  windows_measure = EnvNewAedgWindows.new
  runner_windows = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
  windows_measure.run(model, runner_windows, OpenStudio::Measure::OSArgumentMap.new)
  windows_result = runner_windows.result

  runner = child_to_parent_runner_logging(runner, windows_measure.name.to_s, windows_result, registered_var_list = ['env_secondary_window_fen_area_ft_2'])

  return windows_result, runner
end
