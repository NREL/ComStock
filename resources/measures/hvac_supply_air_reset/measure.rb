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
# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# Dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'

# start the measure
class HVACSupplyAirTemperatureResetBasedOnOutdoorAirTemperature < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Supply Air Temperature Reset Based On Outdoor Air Temperature'
  end

  # human readable description
  def description
    return 'Some buildings use a constant supply-air (also referred to discharge-air) temperature set point of 55F. When a buildings supply fan system is operational, the supply-air temperature set point value should be automatically adjusting to internal/external conditions that will allow the supply fan to operate more efficiently. The simplest way to implement this strategy is to raise supply-air temperature when the outdoor air is cold and the building is less likely to need cooling.  Supplying this warmer air to the  terminals decreases the amount of reheat necessary at the terminal, saving heating energy.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'For each multi-zone system in the model, replace the scheduled supply-air temperature setpoint manager with an outdoor air reset setpoint manager.  When the outdoor temperature is above 75F, supply-air temperature is 55F.  When the outdoor temperature is below 45F, increase the supply-air temperature setpoint to 60F.  When the outdoor temperature is between 45F and 75F, vary the supply-air temperature between 55F and 60F.'
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

    # Loop through all CAV and VAV fans in the model
    fans = model.getFanConstantVolumes
    fans += model.getFanVariableVolumes
    mz_airloops = []
    airloops_already_some_type_reset = []
    airloops_sat_reset_added = []
    spaces_affected = []
    total_airflow_m3_s = 0

    fans.each do |fan|
      # Skip fans that are inside terminals
      next if fan.airLoopHVAC.empty?

      # Get the air loop
      air_loop = fan.airLoopHVAC.get

      # Skip single-zone air loops
      if air_loop.thermalZones.size <= 1
        runner.registerInfo("'#{air_loop.name}' is a single-zone system, SAT reset based on OAT not applicable.")
        next
      end

      # Record this as a multizone system
      mz_airloops << air_loop

      # Skip air loops that already have some type of SAT reset, (anything other than scheduled).
      unless air_loop.supplyOutletNode.setpointManagerScheduled.is_initialized
        runner.registerInfo("'#{air_loop.name}' already has some type of non-schedule-based SAT reset.")
        airloops_already_some_type_reset << air_loop
        next
      end

      # If at this point, SAT reset based on OAT should be applied
      airloops_sat_reset_added << air_loop

      # Register all the spaces on this airloop
      air_loop.thermalZones.each do |zone|
        zone.spaces.each do |space|
          spaces_affected << space.name.to_s
        end
      end

      # Add SAT reset based on OAT to this air loop
      lo_oat_f = 45
      lo_oat_c = OpenStudio.convert(lo_oat_f, 'F', 'C').get
      sa_temp_lo_oat_f = 60
      sa_temp_lo_oat_c = OpenStudio.convert(sa_temp_lo_oat_f, 'F', 'C').get
      hi_oat_f = 75
      hi_oat_c = OpenStudio.convert(hi_oat_f, 'F', 'C').get
      sa_temp_hi_oat_f = 55
      sa_temp_hi_oat_c = OpenStudio.convert(sa_temp_hi_oat_f, 'F', 'C').get
      sa_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
      sa_stpt_manager.setName("#{air_loop.name} SAT OAT reset setpoint")
      sa_stpt_manager.setSetpointatOutdoorLowTemperature(sa_temp_lo_oat_c)
      sa_stpt_manager.setOutdoorLowTemperature(lo_oat_c)
      sa_stpt_manager.setSetpointatOutdoorHighTemperature(sa_temp_hi_oat_c)
      sa_stpt_manager.setOutdoorHighTemperature(hi_oat_c)
      air_loop.supplyOutletNode.addSetpointManager(sa_stpt_manager)
      runner.registerInfo("Added SAT reset based on OAT to '#{air_loop.name}'.")

      # Calculate flow rate
      if air_loop.designSupplyAirFlowRate.is_initialized
        total_airflow_m3_s += air_loop.designSupplyAirFlowRate.get
      elsif air_loop.autosizedDesignSupplyAirFlowRate.is_initialized
        total_airflow_m3_s += air_loop.autosizedDesignSupplyAirFlowRate.get
      end
    end

    # Convert flow rate from m3/s to cfm
    total_airflow_cfm = OpenStudio.convert(total_airflow_m3_s, 'm^3/s', 'ft^3/min').get

    # If the model has no multizone air loops, flag as Not Applicable
    if mz_airloops.empty?
      runner.registerAsNotApplicable('Not Applicable - The model has no multizone air systems.')
      return true
    end

    # If all air loops already have SP reset, flag as Not Applicable
    if airloops_already_some_type_reset.size == mz_airloops.size
      runner.registerAsNotApplicable('Not Applicable - All multizone air systems in the model already have some type of non-schedule-based SAT reset.')
      return false
    end

    # Report the initial condition
    runner.registerInitialCondition("The model started with #{airloops_sat_reset_added.size} multi-zone air systems that did not have SAT resetw.")

    # Report the final condition
    airloops_sat_reset_added_names = []
    airloops_sat_reset_added.each do |air_loop|
      airloops_sat_reset_added_names << air_loop.name
    end

    runner.registerFinalCondition("SAT reset based on OAT control was added to #{airloops_sat_reset_added.size} air systems #{airloops_sat_reset_added_names.join(', ')}.  These air systems served spaces #{spaces_affected.join(', ')}.")
    runner.registerValue('hvac_supply_air_reset_cfm', total_airflow_cfm, 'cfm')

    return true
  end
end

# this allows the measure to be use by the application
HVACSupplyAirTemperatureResetBasedOnOutdoorAirTemperature.new.registerWithApplication
