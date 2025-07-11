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

# start the measure
class AddBlindsToSelectedWindows < OpenStudio::Measure::ModelMeasure
  # define the name that the user will see
  def name
    return 'Add Blinds to Selected Windows'
  end

  def description
    return 'Add blinds to a fraction of windows in target space types'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    add_blinds = OpenStudio::Measure::OSArgument.makeBoolArgument('add_blinds', true)
    add_blinds.setDisplayName('Add blinds to the model?:')
    add_blinds.setDefaultValue(true)
    args << add_blinds

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    is_applicable = runner.getBoolArgumentValue('add_blinds', user_arguments)
    unless is_applicable
      runner.registerAsNotApplicable('add_blinds set to false; skipping measure.')
      return true
    end

    # get the space type blinds ratio from resource json file
    begin
      space_type_blinds_ratio_json = "#{File.dirname(__FILE__)}/resources/space_type_blinds_ratio.json"
      space_type_blinds_ratio = JSON.parse(File.read(space_type_blinds_ratio_json))
    rescue LoadError
      runner.registerError('space_type_blinds_ratio.json file unavailable in resources folder')
      return false
    end

    # collect windows into a lookup hash
    windows = []
    standards_building_types = []
    model.getBuildingStorys.each do |floor|
      floor.spaces.each do |space|
        space.surfaces.each do |surface|
          surface.subSurfaces.each do |sub_surface|
            next unless sub_surface.subSurfaceType == 'FixedWindow' || sub_surface.subSurfaceType == 'OperableWindow'
            next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && sub_surface.surface.get.surfaceType == 'Wall'

            # get the absolute_azimuth for the surface so we can categorize it
            absolute_azimuth = OpenStudio.convert(sub_surface.azimuth, 'rad', 'deg').get + sub_surface.surface.get.space.get.directionofRelativeNorth + model.getBuilding.northAxis
            absolute_azimuth -= 360.0 until absolute_azimuth < 360.0
            if (absolute_azimuth >= 315.0) || (absolute_azimuth < 45.0)
              orientation = 'A-North'
            elsif (absolute_azimuth >= 45.0) && (absolute_azimuth < 135.0)
              orientation = 'B-East'
            elsif (absolute_azimuth >= 135.0) && (absolute_azimuth < 225.0)
              orientation = 'D-South'
            elsif (absolute_azimuth >= 225.0) && (absolute_azimuth < 315.0)
              orientation = 'C-West'
            end
            window = {
              window: sub_surface,
              standards_building_type: space.spaceType.get.standardsBuildingType.get,
              standards_space_type: space.spaceType.get.standardsSpaceType.get,
              orientation: orientation,
              story_height: floor.nominalZCoordinate.to_f,
              window_area: sub_surface.grossArea.to_f
            }

            # only add windows to hash if specified in the space_type_blinds_ratio
            next unless space_type_blinds_ratio.keys.include? window[:standards_building_type]
            next unless space_type_blinds_ratio[window[:standards_building_type]].keys.include? window[:standards_space_type]

            standards_building_types << window[:standards_building_type] unless standards_building_types.include? window[:standards_building_type]
            windows << window
          end
        end
      end
    end

    # guard clause to check if the measure is applicable
    if windows.empty?
      runner.registerAsNotApplicable('No windows are in a space with the selected standards space type.  No blinds added')
      return true
    end

    # create blind schedule
    blind_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
    blind_schedule.setName('Shading Control Schedule')
    blind_schedule.defaultDaySchedule.setName('Shading Control Schedule Default')
    blind_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1)
    blind_schedule.summerDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
    blind_schedule.winterDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)

    # create blind material
    shading_material = OpenStudio::Model::Blind.new(model)
    shading_control = OpenStudio::Model::ShadingControl.new(shading_material)
    shading_control.setShadingControlType('AlwaysOn')
    shading_control.setSchedule(blind_schedule)

    standards_building_types.each do |standards_building_type|
      space_type_blinds_ratio[standards_building_type].each do |space_type, ratio|
        # filter to windows matching the space type
        applicable_windows = windows.select { |h| h[:standards_space_type] == space_type }
        total_window_area = applicable_windows.inject(0) { |sum, h| sum + h[:window_area] }
        next unless total_window_area > 0

        # sort by orientation and then story height
        windows_sorted = applicable_windows.sort_by { |h| [h[:orientation], h[:story_height]] }.reverse
        windows_sorted.each { |h| puts "#{space_type} #{h[:window].name} #{h[:window_area]}" }
        puts "total window area: #{total_window_area}"
        target_blind_area = ratio * total_window_area
        installed_blind_area = 0
        windows_sorted.each do |h|
          next unless installed_blind_area <= target_blind_area

          window = h[:window]
          window.setShadingControl(shading_control)
          runner.registerInfo("A blind was added to window #{window.name}.")
          installed_blind_area += window.grossArea
        end
        runner.registerInfo("For standards space type #{space_type}, #{installed_blind_area.round} m^2 of blinds were added out of #{total_window_area.round} m^2 window area available. Fraction: #{(installed_blind_area / total_window_area).round(2)}.")
      end
    end

    return true
  end
end

# this allows the measure to be used by the application
AddBlindsToSelectedWindows.new.registerWithApplication
