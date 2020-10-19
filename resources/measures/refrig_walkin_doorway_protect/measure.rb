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

# Strip curtains were modeled using the correspondent field in EnergyPlus.
# In order to model automatic door closers, the "door opening fraction" field was modified.
# The literature was consulted and some research was performed but no typical opening reduction factor was found to be associated to
# an automatic door closer. Therefore the value was set to half of the current default value,
# in order to account for the opening reduction given by the automatic door closer.

# start the measure
class RefrigWalkinDoorwayProtection < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'refrig_walkin_doorway_protect'
  end

  # human readable description
  def description
    return 'This measure adds strip curtains or automatic door closers or both to walkin cases'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure goeas through each walkin case and then through each zoneBoundaries. Foe each one, depending on the user inputs, it checks if setStockingDoorOpeningProtectionTypeFacingZone is set to strip curtains and
            it modifies the stocking door schedule to simulate the presence of an automatic door closer.'
  end

  # find the maximum profile value for a schedule
  def simple_schedule_value_adjust(schedule, double, modification_type = 'Multiplier')
    profiles = []
    default_profile = schedule.to_ScheduleRuleset.get
    default_profile = default_profile.defaultDaySchedule
    profiles << default_profile
    rules = schedule.to_ScheduleRuleset.get.scheduleRules
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

    return schedule
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    doorway = OpenStudio::StringVector.new
    doorway << 'Strip Curtain'
    doorway << 'Automatic Door Closer'
    doorway << 'Automatic Door Closer and Strip Curtain'
    doorway_protection_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('doorway_protection_type', doorway, true)
    doorway_protection_type.setDisplayName('Walkin Doorway Protection:')
    doorway_protection_type.setDefaultValue('Strip Curtain')
    args << doorway_protection_type

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if model.getRefrigerationWalkIns.empty?
      runner.registerAsNotApplicable('No refrigerated walkin case is present in the current model, the model will not be altered.')
      return false
    end

    # make choice argument for facade
    doorway_protection_type = runner.getStringArgumentValue('doorway_protection_type', user_arguments)

    changed_walkins = []
    changed_schedules = []
    model.getRefrigerationWalkIns.each do |walkin|
      walkin.zoneBoundaries.each do |zb|
        if doorway_protection_type == 'Automatic Door Closer'
          next unless zb.stockingDoorOpeningScheduleFacingZone.is_initialized
          door_schedule = zb.stockingDoorOpeningScheduleFacingZone.get
          changed_walkins << zb
          next if changed_schedules.include? door_schedule
          new_door_schedule = simple_schedule_value_adjust(door_schedule, 0.5, modification_type = 'Multiplier')
          zb.setStockingDoorOpeningScheduleFacingZone(new_door_schedule)
          changed_schedules << door_schedule
          runner.registerInfo("Walkin #{walkin.name} stocking door automatic closer has been added.")
        elsif doorway_protection_type == 'Strip Curtain'
          next if zb.stockingDoorOpeningProtectionTypeFacingZone == 'StripCurtain'
          zb.setStockingDoorOpeningProtectionTypeFacingZone('StripCurtain')
          runner.registerInfo("Walkin #{walkin.name} stocking door opening protection type has been changed with 'Strip Curtain'.")
          changed_walkins << zb
        else
          if zb.stockingDoorOpeningProtectionTypeFacingZone == 'StripCurtain'
            runner.registerInfo("Walkin #{walkin.name} already contains strip curtains.")
            if zb.stockingDoorOpeningScheduleFacingZone.is_initialized
              door_schedule = zb.stockingDoorOpeningScheduleFacingZone.get
              changed_walkins << zb
              runner.registerInfo("Walkin #{walkin.name} stocking door automatic closer has been added.")
              next if changed_schedules.include? door_schedule
              new_door_schedule = simple_schedule_value_adjust(door_schedule, 0.5, modification_type = 'Multiplier')
              zb.setStockingDoorOpeningScheduleFacingZone(new_door_schedule)
              changed_schedules << door_schedule
            else
              runner.registerInfo("It is not possible to install automated door closer in Walkin #{walkin.name}.")
            end
          else
            zb.setStockingDoorOpeningProtectionTypeFacingZone('StripCurtain')
            runner.registerInfo("Walkin #{walkin.name} stocking door opening protection type has been changed with 'Strip Curtain'.")
            changed_walkins << zb
            if zb.stockingDoorOpeningScheduleFacingZone.is_initialized
              door_schedule = zb.stockingDoorOpeningScheduleFacingZone.get
              runner.registerInfo("Walkin #{walkin.name} stocking door automatic closer has been added.")
              next if changed_schedules.include? door_schedule
              new_door_schedule = simple_schedule_value_adjust(door_schedule, 0.5, modification_type = 'Multiplier')
              zb.setStockingDoorOpeningScheduleFacingZone(new_door_schedule)
              changed_schedules << door_schedule
            else
              runner.registerInfo("It is not possible to install automated door closer in Walkin #{walkin.name}.")
            end
          end
        end
      end
    end

    if changed_walkins.empty?
      runner.registerAsNotApplicable('The refrigerated walkin cases in the current model are already equipped with strip curtains or automatic door closers ')
      return false
    end

    # reporting final condition of model
    runner.registerFinalCondition("#{changed_walkins.length} walkin cases have been upgraded with #{doorway_protection_type}")
    runner.registerValue('refrig_walkin_doorway_protect_changed_walkins', changed_walkins.length, '#')

    return true
  end
end

# register the measure to be used by the application
RefrigWalkinDoorwayProtection.new.registerWithApplication
