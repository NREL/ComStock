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

# dependencies
require 'openstudio-standards'

# start the measure
class HVACEconomizer < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVACEconomizer'
  end

  # human readable description
  def description
    return 'This measure enables air-side economizing in an air system if not already present.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure enables dry-bulb or enthalpy-based air-side economizing depending on climate zone in the controller outdoor air object.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # apply/not-apply measure
    apply_measure = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_measure', true)
    apply_measure.setDisplayName('Apply measure?')
    apply_measure.setDescription('')
    apply_measure.setDefaultValue(true)
    args << apply_measure

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # ----------------------------------------------------
    # puts("### use the built-in error checking ")
    # ----------------------------------------------------
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # ----------------------------------------------------
    # puts("### obtain user inputs")
    # ----------------------------------------------------
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)

    # # ----------------------------------------------------  
    # puts("### adding output variables (for debugging)")
    # # ----------------------------------------------------  
    # ov_eco_status = OpenStudio::Model::OutputVariable.new("debugging_ecostatus",model)
    # ov_eco_status.setKeyValue("*")
    # ov_eco_status.setReportingFrequency("timestep") 
    # ov_eco_status.setVariableName("Air System Outdoor Air Economizer Status")

    # ov_oa_fraction = OpenStudio::Model::OutputVariable.new("debugging_ov_oafraction",model)
    # ov_oa_fraction.setKeyValue("*")
    # ov_oa_fraction.setReportingFrequency("timestep") 
    # ov_oa_fraction.setVariableName("Air System Outdoor Air Flow Fraction")

    # ov_oa_mdot = OpenStudio::Model::OutputVariable.new("debugging_oamdot",model)
    # ov_oa_mdot.setKeyValue("*")
    # ov_oa_mdot.setReportingFrequency("timestep") 
    # ov_oa_mdot.setVariableName("Air System Outdoor Air Mass Flow Rate")

    # ov_oat = OpenStudio::Model::OutputVariable.new("debugging_oat",model)
    # ov_oat.setKeyValue("*")
    # ov_oat.setReportingFrequency("timestep") 
    # ov_oat.setVariableName("Site Outdoor Air Drybulb Temperature")

    # ov_coil_cooling = OpenStudio::Model::OutputVariable.new("debugging_cooling",model)
    # ov_coil_cooling.setKeyValue("*")
    # ov_coil_cooling.setReportingFrequency("timestep") 
    # ov_coil_cooling.setVariableName("Cooling Coil Total Cooling Rate")

    # ----------------------------------------------------
    # puts("### applicability")
    # ---------------------------------------------------- 
    # don't apply measure if specified in input
    if apply_measure == false
      runner.registerAsNotApplicable('Measure is not applied based on user input.')
      return true
    end
    no_outdoor_air_loops = 0
    doas_loops = 0
    existing_economizer_loops = 0
    selected_air_loops = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem
      if oa_system.is_initialized
        oa_system = oa_system.get
      else
        no_outdoor_air_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} does not have outdoor air and cannot economize.")
        next
      end

      sizing_system = air_loop_hvac.sizingSystem
      type_of_load = sizing_system.typeofLoadtoSizeOn
      if type_of_load == 'VentilationRequirement'
        doas_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} is a DOAS system and cannot economize.")
        next
      end

      oa_controller = oa_system.getControllerOutdoorAir
      economizer_type = oa_controller.getEconomizerControlType
      if economizer_type == 'NoEconomizer'
        runner.registerInfo("Air loop #{air_loop_hvac.name} does not have an existing economizer.  This measure will add an economizer.")
        selected_air_loops << air_loop_hvac
      else
        existing_economizer_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} has an existing #{economizer_type} economizer.")
      end
    end

    if selected_air_loops.size.zero?
      runner.registerAsNotApplicable('Model contains no air loops eligible for adding an outdoor air economizer.')
      return true
    end

    # ----------------------------------------------------
    # puts("### initialization")
    # ----------------------------------------------------
    runner.registerInitialCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{doas_loops} are DOAS systems, and #{existing_economizer_loops} have existing economizers, leaving #{selected_air_loops.size} eligible for an economizer.")

    # ----------------------------------------------------
    # puts("### implement economizers")
    # ----------------------------------------------------
    # build standard to access methods
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # get climate zone
    climate_zone = std.model_standards_climate_zone(model)
    runner.registerInfo("initial read of climate zone = #{climate_zone}")
    if climate_zone.empty?
      runner.registerError('Unable to determine climate zone for model. Cannot apply economizer without climate zone information.')
    end

    # check climate zone name validity
    # this happens to example model but maybe not during ComStock model creation?
    substring_count = climate_zone.scan(/ASHRAE 169-2013-/).length
    if substring_count > 1
      runner.registerInfo("climate zone name includes repeated substring of 'ASHRAE 169-2013-'")
      climate_zone = climate_zone.sub(/ASHRAE 169-2013-/, '')
      runner.registerInfo("revised climate zone name = #{climate_zone}")
    end

    # determine economizer type
    economizer_type = std.model_economizer_type(model, climate_zone)
    runner.registerInfo("economizer type for the climate zone = #{economizer_type}")

    # add economizer to selected airloops
    added_economizers = 0
    selected_air_loops.each do |air_loop_hvac|

      # get airLoopHVACOutdoorAirSystem
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      if oa_sys.is_initialized
        oa_sys = oa_sys.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but it has no OA system.")
        next
      end

      # get controller:outdoorair
      oa_control = oa_sys.getControllerOutdoorAir
      # puts("--- adding economizer to controller:outdoorair = #{oa_control.name}")

      # change/check settings: control type
      # puts("--- economizer control type before: #{oa_control.getEconomizerControlType}")
      if oa_control.getEconomizerControlType != economizer_type
        oa_control.setEconomizerControlType(economizer_type)
      end
      # puts("--- economizer control type new: #{oa_control.getEconomizerControlType}")

      # get economizer limits
      limits = std.air_loop_hvac_economizer_limits(air_loop_hvac, climate_zone) # in IP unit
      # puts("--- economizer limits [db max|enthal max|dewpoint max] for the climate zone = #{limits}")

      # implement limits for each control type
      case economizer_type
      when 'FixedDryBulb'
        if oa_control.getEconomizerMaximumLimitDryBulbTemperature.is_initialized
          puts("--- economizer limit for #{economizer_type} before: #{oa_control.getEconomizerMaximumLimitDryBulbTemperature.get}")
        end
        drybulb_limit_c = OpenStudio.convert(limits[0], 'F', 'C').get
        oa_control.resetEconomizerMaximumLimitDryBulbTemperature
        oa_control.setEconomizerMaximumLimitDryBulbTemperature(drybulb_limit_c)
        # puts("--- economizer limit for #{economizer_type} new: #{oa_control.getEconomizerMaximumLimitDryBulbTemperature.get}")
      when 'FixedEnthalpy'
        if oa_control.getEconomizerMaximumLimitEnthalpy.is_initialized
          puts("--- economizer limit for #{economizer_type} before: #{oa_control.getEconomizerMaximumLimitEnthalpy.get}")
        end
        enthalpy_limit_j_per_kg = OpenStudio.convert(limits[1], 'Btu/lb', 'J/kg').get
        oa_control.resetEconomizerMaximumLimitEnthalpy
        oa_control.setEconomizerMaximumLimitEnthalpy(enthalpy_limit_j_per_kg)
        # puts("--- economizer limit for #{economizer_type} new: #{oa_control.getEconomizerMaximumLimitEnthalpy.get}")
      when 'FixedDewPointAndDryBulb'
        if oa_control.getEconomizerMaximumLimitDewpointTemperature.is_initialized
          puts("--- economizer limit for #{economizer_type} before: #{oa_control.getEconomizerMaximumLimitDewpointTemperature.get}")
        end
        drybulb_limit_f = 75
        dewpoint_limit_f = 55
        drybulb_limit_c = OpenStudio.convert(drybulb_limit_f, 'F', 'C').get
        dewpoint_limit_c = OpenStudio.convert(dewpoint_limit_f, 'F', 'C').get
        oa_control.resetEconomizerMaximumLimitDryBulbTemperature
        oa_control.resetEconomizerMaximumLimitDewpointTemperature
        oa_control.setEconomizerMaximumLimitDryBulbTemperature(drybulb_limit_c)
        oa_control.setEconomizerMaximumLimitDewpointTemperature(dewpoint_limit_c)
        # puts("--- economizer limit (max db T) for #{economizer_type} new: #{oa_control.getEconomizerMaximumLimitDryBulbTemperature.get}")
        # puts("--- economizer limit (max dp T) for #{economizer_type} new: #{oa_control.getEconomizerMaximumLimitDewpointTemperature.get}")
      end

      # change/check settings: lockout type
      # puts("--- economizer lockout type before: #{oa_control.getLockoutType}")
      if oa_control.getLockoutType != "LockoutWithHeating"
        oa_control.setLockoutType("LockoutWithHeating") # integrated economizer
      end
      # puts("--- economizer lockout type new: #{oa_control.getLockoutType}")

      # calc statistics
      added_economizers += 1
    end

    # ----------------------------------------------------
    # puts("### report final condition")
    # ----------------------------------------------------
    # report final condition of model
    runner.registerFinalCondition("Added #{added_economizers} to the model.")

    return true
  end
end

# register the measure to be used by the application
HVACEconomizer.new.registerWithApplication
