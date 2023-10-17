# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2022, Alliance for Sustainable Energy, LLC.
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

# Measure distributed under NREL Copyright terms, see LICENSE.md file.

#start the measure
class FaultHvacEconomizerChangeoverTemperature < OpenStudio::Ruleset::ModelUserScript
  #define the name that a user will see, this method may be deprecated as
  #the display name in PAT comes from the name field in measure.xml
  def name
    return "fault hvac economizer changeover temperature"
  end
  
  def description
    return "This is a fault measure that changes normal changeover temperature setpoint of a fixed dry-bulb economizer to lower changeover temperature setpoint (10.88C)."
  end
  
  def modeler_description
    return "Finds Economizer with fixed dry-bulb control and replaces existing changeover temperature setpoint to the user-defined changeover temperature setpoint if the existing economizer's setpoint is higher than the user-defined setpoint."
  end
  
  #define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    #make choice arguments for economizers
    controlleroutdoorairs = model.getControllerOutdoorAirs
    chs = OpenStudio::StringVector.new
    chs << "all available economizer"
    controlleroutdoorairs.each do |controlleroutdoorair|
      chs << controlleroutdoorair.name.to_s
    end
    econ_choice = OpenStudio::Ruleset::OSArgument::makeChoiceArgument('econ_choice', chs, true)
    econ_choice.setDisplayName("Choice of economizers. If you want to impose the fault on all economizers, choose 'all available economizer'")
    econ_choice.setDefaultValue("all available economizer")
    args << econ_choice
	
    # define faulted changeover temperature setpoint
    changeovertemp = OpenStudio::Ruleset::OSArgument::makeDoubleArgument('changeovertemp', false)
    changeovertemp.setDisplayName("Changeover temperature of the economizer's fixed dry-bulb controller.")
    changeovertemp.setDefaultValue(10.88) # in degree celsius (51.6F)
    args << changeovertemp

    # apply/not-apply measure
    apply_measure = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_measure', true)
    apply_measure.setDisplayName('Apply measure?')
    apply_measure.setDescription('')
    apply_measure.setDefaultValue(true)
    args << apply_measure
	
    return args
  end #end the arguments method

  #define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)
    
    # ----------------------------------------------------
    # puts("### use the built-in error checking")
    # ----------------------------------------------------
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end
	
    # ----------------------------------------------------
    # puts("### obtain user inputs")
    # ----------------------------------------------------
    econ_choice = runner.getStringArgumentValue('econ_choice',user_arguments)
    changeovertemp = runner.getDoubleArgumentValue('changeovertemp',user_arguments)
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)
    
    # ----------------------------------------------------
    # puts("### check if changeover temperature setpoint is reasonable")
    # ----------------------------------------------------
    if changeovertemp < 4.44 || changeovertemp > 23.89
      runner.registerError("Changeover temperature must be between 4.44C and 23.89C and it is now #{changeovertemp}!")
      return false
    end

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
    # puts("### applicability check")
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

      is_unitary = false
      air_loop_hvac.supplyComponents.each do |sc|
        if sc.to_AirLoopHVACUnitarySystem.is_initialized
          is_unitary = true
        end
      end

      if is_unitary
        runner.registerInfo("Air loop #{air_loop_hvac.name} is a unitary system cannot economize.")
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
        runner.registerInfo("Air loop #{air_loop_hvac.name} does not have an existing economizer. This measure will skip this air loop.")
      elsif economizer_type != 'FixedDryBulb'
        runner.registerInfo("Air loop #{air_loop_hvac.name} has economizer with #{economizer_type} control instead of fixed dry-bulb control. This measure will skip this air loop.")
      else
        existing_economizer_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} has an applicable #{economizer_type} economizer. This measure will impose fault to the economizer in this air loop.")
        selected_air_loops << air_loop_hvac
      end
    end

    # ----------------------------------------------------
    # puts("### initialization")
    # ----------------------------------------------------
    # report initial condition of model
    runner.registerInitialCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{doas_loops} are DOAS systems, and #{existing_economizer_loops} have existing economizers. Leaving #{selected_air_loops.size} economizers applicable.")
    if selected_air_loops.size.zero?
      runner.registerAsNotApplicable('Model contains no air loops eligible for adding an outdoor air economizer.')
      return true
    end

    # ----------------------------------------------------    
    # puts("### apply fault only to applicable economizers")
    # ----------------------------------------------------
    count_eco = 0
    selected_air_loops.each do |selected_air_loop|
      controlleroutdoorair = selected_air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
      if controlleroutdoorair.name.to_s.eql?(econ_choice) || econ_choice.eql?("all available economizer")
        controltype = controlleroutdoorair.getEconomizerControlType
        # puts("--- checking for #{controlleroutdoorair.name}: applicable economizer available")
        runner.registerInfo("Found applicable economizer from controlleroutdoorair object: #{controlleroutdoorair.name}")
        changeovertemp_original = controlleroutdoorair.getEconomizerMaximumLimitDryBulbTemperature.to_f.round(3)
        # puts("--- checking for #{controlleroutdoorair.name}: changeover temperature of economizer (original) = #{changeovertemp_original}C")
        if changeovertemp_original > changeovertemp
          controlleroutdoorair.setEconomizerMaximumLimitDryBulbTemperature(changeovertemp)
          changeovertemp_faulted = controlleroutdoorair.getEconomizerMaximumLimitDryBulbTemperature.to_f.round(3)
          # puts("--- checking for #{controlleroutdoorair.name}: changeover temperature of economizer (shifted) = #{changeovertemp_faulted}C")
          count_eco+=1
        else
          # puts("--- checking for #{controlleroutdoorair.name}: changeover temperature already low (#{changeovertemp_original}C). Skipping...")
        end   
      end
    end

    # ----------------------------------------------------  
    # puts("### finalization")
    # ----------------------------------------------------  
    runner.registerFinalCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{doas_loops} are DOAS systems, and #{existing_economizer_loops} have existing economizers. From #{selected_air_loops.size} eligible economizers, #{count_eco} economizers are updated with changeover temperature setpoint of #{changeovertemp}C.")
    
    return true
  end #end the run method
end #end the measure

#this allows the measure to be use by the application
FaultHvacEconomizerChangeoverTemperature.new.registerWithApplication
