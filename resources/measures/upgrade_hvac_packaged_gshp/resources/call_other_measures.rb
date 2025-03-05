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

# create methods to call other measures for package runs
# putting this code in a resource file prevents issues with the OS app parsing
def call_dcv(model, runner)
    dcv_measure_path = File.join(__dir__, '../../upgrade_hvac_dcv/measure.rb')
    unless File.exist?(dcv_measure_path)
        runner.registerError("DCV measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.")
        return false
    end
    require dcv_measure_path

    dcv_measure = HVACDCV.new
    runner_dcv = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    dcv_measure.run(model, runner_dcv, OpenStudio::Measure::OSArgumentMap.new)
    dcv_result = runner_dcv.result
    
    # Check if the measure ran successfully
    if dcv_result.value.valueName == 'Success'
        runner.registerInfo('DCV measure was applied successfully.')
    elsif dcv_result.value.valueName == 'NA'
        runner.registerInfo('DCV measure was not applicable.')
    else
        runner.registerError('DCV measure failed.')
        return false
    end
end

def call_economizer(model, runner)
    econ_measure_path = File.join(__dir__, '../../upgrade_hvac_economizer/measure.rb')
    unless File.exist?(econ_measure_path)
        runner.registerError("Economizer measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.")
        return false
    end
    require econ_measure_path

    econ_measure = HVACEconomizer.new
    runner_econ = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    econ_measure.run(model, runner_econ, OpenStudio::Measure::OSArgumentMap.new)
    econ_result = runner_econ.result
    
    # Check if the measure ran successfully
    if econ_result.value.valueName == 'Success'
        runner.registerInfo('Economizer measure was applied successfully.')
    elsif econ_result.value.valueName == 'NA'
        runner.registerInfo('Economizer measure was not applicable.')
    else
        runner.registerError('Economizer measure failed.')
        return false
    end
end

def call_walls(model, runner)
    walls_measure_path = File.join(__dir__, '../../upgrade_env_exterior_wall_insulation/measure.rb')
    unless File.exist?(walls_measure_path)
        runner.registerError("Wall Insulation measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.")
        return false
    end
    require walls_measure_path

    walls_measure = ExteriorWallInsulation.new
    runner_walls = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    walls_measure.run(model, runner_walls, OpenStudio::Measure::OSArgumentMap.new)
    walls_result = runner_walls.result
    
    # Check if the measure ran successfully
    if walls_result.value.valueName == 'Success'
        runner.registerInfo('Wall Insulation measure was applied successfully.')
    elsif walls_result.value.valueName == 'NA'
        runner.registerInfo('Wall Insulation measure was not applicable.')
    else
        runner.registerError('Wall Insulation measure failed.')
        return false
    end
end

def call_roof(model, runner)
    roof_measure_path = File.join(__dir__, '../../upgrade_env_roof_insul_aedg/measure.rb')
    unless File.exist?(roof_measure_path)
        runner.registerError("Roof Insulation measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.")
        return false
    end
    require roof_measure_path

    roof_measure = EnvRoofInsulAedg.new
    runner_roof = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    roof_measure.run(model, runner_roof, OpenStudio::Measure::OSArgumentMap.new)
    roof_result = runner_roof.result
    
    # Check if the measure ran successfully
    if roof_result.value.valueName == 'Success'
        runner.registerInfo('Roof Insulation measure was applied successfully.')
    elsif roof_result.value.valueName == 'NA'
        runner.registerInfo('Roof Insulation measure was not applicable.')
    else
        runner.registerError('Roof Insulation measure failed.')
        return false
    end
end

def call_windows(model, runner)
    windows_measure_path = File.join(__dir__, '../../upgrade_env_new_aedg_windows/measure.rb')
    unless File.exist?(windows_measure_path)
        runner.registerError("New Windows measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.")
        return false
    end
    require windows_measure_path

    windows_measure = EnvNewAedgWindows.new
    runner_windows = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    windows_measure.run(model, runner_windows, OpenStudio::Measure::OSArgumentMap.new)
    windows_result = runner_windows.result
    
    # Check if the measure ran successfully
    if windows_result.value.valueName == 'Success'
        runner.registerInfo('New Windows measure was applied successfully.')
    elsif windows_result.value.valueName == 'NA'
        runner.registerInfo('New Windows measure was not applicable.')
    else
        runner.registerError('New Windows measure failed.')
        return false
    end
end

def call_lighting(model, runner)
    lighting_measure_path = File.join(__dir__, '../../upgrade_light_led/measure.rb')
    unless File.exist?(lighting_measure_path)
        runner.registerError("LED Lighting measure not found. Check that this measure exists in your file structure and modify the measure path if necessary.")
        return false
    end
    require lighting_measure_path

    lighting_measure = LightLED.new
    runner_lighting = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    lighting_arg_map = OpenStudio::Measure::OSArgumentMap.new
    puts("******arg map******* = #{lighting_arg_map}")

    lighting_measure.run(model, runner_lighting, lighting_arg_map)
    lighting_result = runner_lighting.result
    
    # Check if the measure ran successfully
    if lighting_result.value.valueName == 'Success'
        runner.registerInfo('LED Lighting measure was applied successfully.')
    elsif lighting_result.value.valueName == 'NA'
        runner.registerInfo('LED Lighting measure was not applicable.')
    else
        runner.registerError('LED Lighting measure failed.')
        return true
        exit
    end
end