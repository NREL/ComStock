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

# load OpenStudio measure libraries
require 'openstudio-standards'

# start the measure
class LightingControls < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Occupancy and Daylighting Controls'
  end

  # human readable description
  def description
    return 'Choose from occupancy or daylighting controls.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Daylighting controls will physically add in daylighting controls to spaces in the building, while occupancy control will reduce lighting schedules by 10%.'
  end

  # find the maximum profile value for a schedule
  # can increase/decrease by percentage or static value
  def simple_schedule_value_adjust(model, schedule, double, modification_type = 'Multiplier')
    # give option to clone or not

    # gather profiles
    profiles = []
    defaultProfile = schedule.to_ScheduleRuleset.get.defaultDaySchedule
    profiles << defaultProfile
    rules = schedule.scheduleRules
    rules.each do |rule|
      profiles << rule.daySchedule
    end

    # alter profiles
    profiles.each do |profile|
      times = profile.times
      i = 0
      profile.values.each do |value|
        if modification_type == 'Multiplier' || modification_type == 'Percentage' # percentage was used early on but Multiplier is preferable
          profile.addValue(times[i], value * double)
        end
        if modification_type == 'Sum' || modification_type == 'Value' # value was used early on but Sum is preferable
          profile.addValue(times[i], value + double)
        end
        i += 1
      end
    end

    result = schedule
    return result
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make choice argument for choice
    choices = OpenStudio::StringVector.new
    choices << 'Daylighting Controls'
    choices << 'Occupancy Controls'
    control_strategy = OpenStudio::Measure::OSArgument.makeChoiceArgument('control_strategy', choices, true)
    control_strategy.setDisplayName('Daylighting and Occupancy Control Strategy.')
    args << control_strategy

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    control_strategy = runner.getStringArgumentValue('control_strategy', user_arguments)
    apply_daylighting_controls = control_strategy.include?('Daylighting Controls') ? true : false
    apply_occupancy_controls = control_strategy.include?('Occupancy Controls') ? true : false

    # add daylighting controls
    if apply_daylighting_controls
      standard = Standard.build('ComStock 90.1-2013')
      runner.registerInitialCondition("The building started with #{model.getDaylightingControls.size} daylighting control objects.")
      runner.registerInfo('Adding dayligting controls to selected spaces in model as specified by ASHRAE 90.1-2013.')
      standard.model_add_daylighting_controls(model)
      runner.registerFinalCondition("The building finished with #{model.getDaylightingControls.size} daylighting control objects.")
    end

    # apply occupancy controls
    if apply_occupancy_controls
      # gather schedules to alter
      schedules = []
      multiplier_val = 0.9

      # loop through lights and plug loads that are used in the model to populate schedule hash
      model.getLightss.each do |light|
        # check if this instance is used in the model
        if light.spaceType.is_initialized
          next if light.spaceType.get.spaces.empty?
        end

        # find schedule
        if light.schedule.is_initialized && light.schedule.get.to_ScheduleRuleset.is_initialized
          schedules << light.schedule.get.to_ScheduleRuleset.get
        else
          runner.registerWarning("#{light.name} does not have a schedule or schedule is not a schedule ruleset assigned and could not be altered")
        end
      end

      runner.registerInfo("Adding occupancy controls to model by altering #{schedules.uniq.size} lighting schedules.")
      # loop through and alter schedules
      schedules.uniq.each do |sch|
        simple_schedule_value_adjust(model, sch, multiplier_val, 'Multiplier')
      end
      runner.registerFinalCondition("Occupancy controls were added by altering #{schedules.uniq.size} lighting schedules.")
    end

    # report final condition of model
    runner.registerValue('light_controls_control_strategy', control_strategy)
    return true
  end
end
LightingControls.new.registerWithApplication
