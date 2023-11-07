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

require 'date'

#start the measure
class FaultHvacEconomizerDamperStuck < OpenStudio::Ruleset::ModelUserScript
  #define the name that a user will see, this method may be deprecated as
  #the display name in PAT comes from the name field in measure.xml
  def name
    return "fault hvac economizer damper stuck"
  end
  
  def description
    return "TBD"
  end
  
  def modeler_description
    return "TBD"
  end
  
  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # make choice arguments for economizers
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
    
    # make a double argument for fault start month
    start_month = OpenStudio::Ruleset::OSArgument::makeIntegerArgument('start_month', false)
    start_month.setDisplayName('Month when faulted behavior starts.')
    start_month.setDefaultValue(1)  #default position 50% open
    args << start_month

    # make a double argument for fault start day
    start_day = OpenStudio::Ruleset::OSArgument::makeIntegerArgument('start_day', false)
    start_day.setDisplayName('Day of month when faulted behavior starts.')
    start_day.setDefaultValue(1)  #default position 50% open
    args << start_day

    # make a double argument for fault duration
    duration_days = OpenStudio::Ruleset::OSArgument::makeIntegerArgument('duration_days', false)
    duration_days.setDisplayName('Duration of faulted behavior in days.')
    duration_days.setDefaultValue(365)  #default position 50% open
    args << duration_days

    # make a double argument for the damper position
    damper_pos = OpenStudio::Ruleset::OSArgument::makeDoubleArgument('damper_pos', false)
    damper_pos.setDisplayName('The position of damper indicated between 0 and 1. Currently, only works for fully closed. Other values have implications.')
    damper_pos.setDefaultValue(0.0)  #default position 50% open
    args << damper_pos

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
    # puts("### obtain input arguments")
    # ----------------------------------------------------
    econ_choice = runner.getStringArgumentValue('econ_choice',user_arguments)
    damper_pos = runner.getDoubleArgumentValue('damper_pos',user_arguments)
    start_month = runner.getIntegerArgumentValue('start_month',user_arguments)
    start_day = runner.getIntegerArgumentValue('start_day',user_arguments)
    duration_days = runner.getIntegerArgumentValue('duration_days',user_arguments)
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)

    # ----------------------------------------------------
    # puts("### get fault end date")
    # ----------------------------------------------------
    date_start = Date.new(2019,start_month,start_day)
    start_doy = date_start.yday()
    date_end = date_start + duration_days
    start_doy = date_start.yday()
    end_doy = date_end.yday()
    # puts("--- fault start date = #{date_start} | #{start_doy} days from JAN 1st")
    # puts("--- duration = #{duration_days} days")
    # puts("--- fault end date = #{date_end} | #{end_doy} days from JAN 1st")
    
    # ----------------------------------------------------
    # puts("### check if the damper position is between 0 and 1")
    # ----------------------------------------------------
    if damper_pos < 0.0 || damper_pos > 1.0
      runner.registerError("Damper position must be between 0 and 1 and it is now #{damper_pos}!")
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
    if (damper_pos >= 0.0 || damper_pos <= 1.0)
    
      runner.registerInitialCondition("Fixing #{econ_choice} damper position to #{(damper_pos*100).round()}% open")
            
      # ----------------------------------------------------
      # puts("--- find the economizer to change")
      # ----------------------------------------------------

      # loop through air loops
      count_eco = 0
      selected_air_loops.each_with_index do |selected_air_loop, i|
        controlleroutdoorair = selected_air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
        if controlleroutdoorair.name.to_s.eql?(econ_choice) || econ_choice.eql?("all available economizer")

          runner.registerInfo("Modifying the economizer called #{controlleroutdoorair.name.to_s}")

          # ----------------------------------------------------
          # puts("--- create dummy min/max OA fraction schedules (meant for fault incidence) if there aren't any existing schedules")
          # ----------------------------------------------------
          if controlleroutdoorair.minimumFractionofOutdoorAirSchedule.empty?
            sch_fraction_oa_min = OpenStudio::Model::ScheduleConstant.new(model)
            sch_fraction_oa_min.setName("FRAC_OA_MIN_#{controlleroutdoorair.name.to_s}")
            sch_fraction_oa_min.setValue(0.0)
            # puts("*** new schedule created for minimum OA fraction")
          else
            sch_fraction_oa_min = controlleroutdoorair.minimumFractionofOutdoorAirSchedule.get
            # puts("*** found existing schedule for minimum OA fraction: #{sch_fraction_oa_min.name}")
          end
          if controlleroutdoorair.maximumFractionofOutdoorAirSchedule.empty?
            sch_fraction_oa_max = OpenStudio::Model::ScheduleConstant.new(model)
            sch_fraction_oa_max.setName("FRAC_OA_MAX_#{controlleroutdoorair.name.to_s}")
            sch_fraction_oa_max.setValue(1.0)
            # puts("*** new schedule created for maximum OA fraction")
          else
            sch_fraction_oa_max = controlleroutdoorair.maximumFractionofOutdoorAirSchedule.get
            # puts("*** found existing schedule for maximum OA fraction: #{sch_fraction_oa_min.name}")
          end
        
          # ----------------------------------------------------
          # puts("--- check economizer control type")
          # ----------------------------------------------------
          controltype = controlleroutdoorair.getEconomizerControlType
          if controltype.eql?('NoEconomizer')
            # puts("*** #{econ_choice} does not have an economizer. Skipping...")
            runner.registerAsNotApplicable("#{econ_choice} does not have an economizer. Skipping......")
            break
          else
            # puts("*** #{econ_choice} has an economizer. Moving on for fault implementation...")
          end

          # ----------------------------------------------------
          # puts("--- apply faulted schedules to min/max outdoor air fraction")
          # ----------------------------------------------------
          if (start_month == 1) && (start_day == 1) && (duration_days == 365)

            # puts("*** whole year selected for fault incidence")
            runner.registerInfo("whole year selected for fault incidence")

            #create a schedule that the economizer is fixed at the damper_pos for the entire simulation period
            faultschedule = OpenStudio::Model::ScheduleRuleset.new(model)
            faultschedule.setName("Damper Stuck Fault Schedule for #{econ_choice}")
            faultscheduledefault = faultschedule.defaultDaySchedule
            faultscheduledefault.clearValues
            faultscheduledefault.addValue(OpenStudio::Time.new(0,24,0,0), damper_pos)
            faultscheduledefault.setName("Default Damper Stuck Fault Default Schedule for #{econ_choice}")
            
            #set the faulted damper schedule
            controlleroutdoorair.setMinimumFractionofOutdoorAirSchedule(faultschedule)
            controlleroutdoorair.setMaximumFractionofOutdoorAirSchedule(faultschedule)

          else

            # puts("*** partial period selected for fault incidence")
            runner.registerInfo("partial period selected for fault incidence")

            # assign dummy schedule to controller:outdoorair
            controlleroutdoorair.setMinimumFractionofOutdoorAirSchedule(sch_fraction_oa_min)
            controlleroutdoorair.setMaximumFractionofOutdoorAirSchedule(sch_fraction_oa_max)

            # create EMS actuator object
            # puts("*** create EMS actuator for min outdoor air fraction")
            ema_actuator_frac_oa_min = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_fraction_oa_min,"Schedule:Constant","Schedule Value")
            ema_actuator_frac_oa_min.setName("sch_fraction_oa_min_#{i+1}")
            
            # create EMS actuator object
            # puts("*** create EMS actuator for max outdoor air fraction")
            ema_actuator_frac_oa_max = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_fraction_oa_max,"Schedule:Constant","Schedule Value")
            ema_actuator_frac_oa_max.setName("sch_fraction_oa_max_#{i+1}")
            
            # create new EnergyManagementSystem:Program object
            # puts("*** create EMS program")
            ems_program_sch_override = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
            ems_program_sch_override.setName("DamperStuckOverride")
            ems_program_sch_override.addLine("IF (DayOfYear >= #{start_doy}) && (DayOfYear < #{end_doy})")
            ems_program_sch_override.addLine("SET #{ema_actuator_frac_oa_min.name} = #{damper_pos}")
            ems_program_sch_override.addLine("SET #{ema_actuator_frac_oa_max.name} = #{damper_pos}")
            ems_program_sch_override.addLine("ELSE")
            ems_program_sch_override.addLine("SET #{ema_actuator_frac_oa_min.name} = 0.0")
            ems_program_sch_override.addLine("SET #{ema_actuator_frac_oa_max.name} = 1.0")
            ems_program_sch_override.addLine("ENDIF") 
            
            # create new EnergyManagementSystem:ProgramCallingManager object
            # puts("*** create EMS program calling manager")
            ems_program_calling_mngr = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
            ems_program_calling_mngr.setName("DamperStuckOverrideCallMngr")
            ems_program_calling_mngr.setCallingPoint("AfterPredictorBeforeHVACManagers")
            ems_program_calling_mngr.addProgram(ems_program_sch_override)
            
            # create OutputEnergyManagementSystem object
            # output_EMS = model.getOutputEnergyManagementSystem
            # output_EMS.setInternalVariableAvailabilityDictionaryReporting('internal_variable_availability_dictionary_reporting')
            # output_EMS.setEMSRuntimeLanguageDebugOutputLevel('ems_runtime_language_debug_output_level')
            # output_EMS.setActuatorAvailabilityDictionaryReporting('actuator_availability_dictionary_reporting')
            
            # create output variables for reporting on EMS actuated objects
            # puts("*** creating output variable from EMS: sch_fraction_oa_variable_min")
            sch_fraction_oa_variable_min = OpenStudio::Model::OutputVariable.new('Schedule Value', model)
            sch_fraction_oa_variable_min.setReportingFrequency('timestep')
            sch_name = sch_fraction_oa_min.name.to_s
            sch_fraction_oa_variable_min.setKeyValue(sch_name)
            sch_fraction_oa_variable_min.setVariableName('Schedule Value')

            # create output variables for reporting on EMS actuated objects
            # puts("*** creating output variable from EMS: sch_fraction_oa_variable_max")
            sch_fraction_oa_variable_max = OpenStudio::Model::OutputVariable.new('Schedule Value', model)
            sch_fraction_oa_variable_max.setReportingFrequency('timestep')
            sch_name = sch_fraction_oa_max.name.to_s
            sch_fraction_oa_variable_max.setKeyValue(sch_name)
            sch_fraction_oa_variable_max.setVariableName('Schedule Value')

          end
          count_eco+=1
        end
      end
    else
      runner.registerAsNotApplicable("#{name} is not running for #{econ_choice}. Skipping......")
    end

    # ----------------------------------------------------  
    # puts("### finalization")
    # ----------------------------------------------------  
    runner.registerFinalCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{doas_loops} are DOAS systems, and #{existing_economizer_loops} have existing economizers. From #{selected_air_loops.size} eligible economizers, #{count_eco} economizers are imposed with fault where damper is stuck at #{(damper_pos*100).round(0)}% open position. Fault imposed to the model starting from #{date_start} and lasted for #{duration_days} days.")
    
    return true
  end #end the run method
end #end the measure

#this allows the measure to be use by the application
FaultHvacEconomizerDamperStuck.new.registerWithApplication
