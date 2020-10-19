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

# dependencies
require 'openstudio-standards'

# start the measure
class HVACVRFHP < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVACVRFHP'
  end

  # human readable description
  def description
    return 'This model replaces the existing HVAC system with a VRF + DOAS system.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This model replaces the existing HVAC system with a VRF + DOAS system.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # report initial condition of model
    runner.registerInitialCondition("The building started with #{model.getAirLoopHVACs.size} air loops and #{model.getPlantLoops.size} plant loops.")

    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    # determine climate zone for economizer type
    climate_zone = std.model_standards_climate_zone(model)
    if climate_zone.empty?
      runner.registerError('Unable to determine climate zone for model. Cannot add system without climate zone information.')
    else
      climate_zone = std.model_find_climate_zone_set(model, climate_zone)
      runner.registerInfo("Setting VRF system based on model climate zone #{climate_zone}")
    end

    # remove existing HVAC system
    std.model_remove_prm_hvac(model)

    # remove existing EMS code if present
    model.getEnergyManagementSystemActuators.each { |x| x.remove }
    model.getEnergyManagementSystemConstructionIndexVariables.each { |x| x.remove }
    model.getEnergyManagementSystemCurveOrTableIndexVariables.each { |x| x.remove }
    model.getEnergyManagementSystemGlobalVariables.each { |x| x.remove }
    model.getEnergyManagementSystemInternalVariables.each { |x| x.remove }
    model.getEnergyManagementSystemMeteredOutputVariables.each { |x| x.remove }
    model.getEnergyManagementSystemOutputVariables.each { |x| x.remove }
    model.getEnergyManagementSystemPrograms.each { |x| x.remove }
    model.getEnergyManagementSystemProgramCallingManagers.each { |x| x.remove }
    model.getEnergyManagementSystemSensors.each { |x| x.remove }
    model.getEnergyManagementSystemSubroutines.each { |x| x.remove }
    model.getEnergyManagementSystemTrendVariables.each { |x| x.remove }

    # add VRF system
    zones = model.getThermalZones
    heated_and_cooled_zones = zones.select { |zone| std.thermal_zone_heated?(zone) && std.thermal_zone_cooled?(zone) }
    cooled_only_zones = zones.select { |zone| !std.thermal_zone_heated?(zone) && std.thermal_zone_cooled?(zone) }
    heated_only_zones = zones.select { |zone| std.thermal_zone_heated?(zone) && !std.thermal_zone_cooled?(zone) }
    system_zones = heated_and_cooled_zones + cooled_only_zones + heated_only_zones
    std.model_add_hvac_system(model, 'DOAS', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones,
                              air_loop_heating_type: 'DX',
                              air_loop_cooling_type: 'DX')
    std.model_add_hvac_system(model, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones,
                              zone_equipment_ventilation: false)

    # sizing run
    # Set the heating and cooling sizing parameters
    std.model_apply_prm_sizing_parameters(model)

    # Perform a sizing run
    if std.model_run_sizing_run(model, "#{Dir.pwd}/SR1") == false
      runner.registerError('Sizing run did not succeed, cannot apply HVAC efficiencies.')
      log_messages_to_runner(runner, debug = true)
      return false
    end

    # Apply the HVAC efficiency standard
    std.model_apply_hvac_efficiency_standard(model, climate_zone)

    total_cooling_capacity_w = 0
    model.getAirConditionerVariableRefrigerantFlows.each do |vrf_system|
      if vrf_system.ratedTotalCoolingCapacity.is_initialized
        total_cooling_capacity_w += vrf_system.ratedTotalCoolingCapacity.get
      elsif vrf_system.autosizedRatedTotalCoolingCapacity.is_initialized
        total_cooling_capacity_w += vrf_system.autosizedRatedTotalCoolingCapacity.get
      else
        runner.registerWarning("For #{vrf_system.name} capacity is not available, total cooling capacity of vrf system will be incorrect when applying standard.")
      end
    end

    # report final condition of model
    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000
    runner.registerValue('hvac_vrf_hp_cooling_load_in_tons', total_cooling_capacity_tons)
    runner.registerFinalCondition("Added VRF system to model serving #{system_zones.size} zones with #{total_cooling_capacity_tons.round(1)} tons of total cooling capacity.")

    return true
  end
end

# register the measure to be used by the application
HVACVRFHP.new.registerWithApplication
