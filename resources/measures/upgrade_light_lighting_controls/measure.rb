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

require 'csv'
require 'openstudio-standards'

# require all .rb files in resources folder
Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }

# start the measure
class LightingControls < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    'lighting_controls'
  end

  # human readable description
  def description
    'This measure applies lighting controls (daylighting sensors, occupancy sensors) to spaces where they are not already present. '
  end

  # human readable description of modeling approach
  def modeler_description
    'This measure loops through space types in the model and applies daylighting controls and occupancy sensors where they are not already present. Daylighting sensors are added via the built-in energy plus daylighting objects, while occupancy sensors are applied via a percent LPD reduction by space type based on ASHRAE 90.1 Appendix Table G3.7.'
  end

  # define the arguments that the user will input
  def arguments(_model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # apply daylighting controls?
    apply_daylighting = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_daylighting', true)
    apply_daylighting.setDisplayName('Apply daylighting controls?')
    apply_daylighting.setDescription('')
    apply_daylighting.setDefaultValue(true)
    args << apply_daylighting

    # apply daylighting controls?
    apply_occupancy = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_occupancy', true)
    apply_occupancy.setDisplayName('Apply occupancy controls?')
    apply_occupancy.setDescription('')
    apply_occupancy.setDefaultValue(true)
    args << apply_occupancy

    args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(model), user_arguments)

    # get user arguments
    apply_daylighting = runner.getBoolArgumentValue('apply_daylighting', user_arguments)
    apply_occupancy = runner.getBoolArgumentValue('apply_occupancy', user_arguments)

    # Get additional properties of the model. Used to look up template of original construction, which informs which spaces should already have occupancy sensors by code.
    addtl_props = model.getBuilding.additionalProperties

    if addtl_props.getFeatureAsString('energy_code_in_force_during_original_building_construction').is_initialized
      template = addtl_props.getFeatureAsString('energy_code_in_force_during_original_building_construction').get
      runner.registerInfo("Energy code in force during original building construction is: #{template}.")
    else
      runner.registerError('Energy code could not be found. Measure will not be applied.')
    end

    # track how many spaces are receiving new daylighting sensors.
    num_spaces_to_get_daylighting_sensors = 0

    if apply_daylighting == true
      num_spaces_to_get_daylighting_sensors = model_add_daylighting_controls(runner, model, template, num_spaces_to_get_daylighting_sensors)
    else
      runner.registerInfo('User argument does not request daylighting controls, so none will be added.')
    end

    # track how many spaces are receiving new daylighting sensors.
    num_spaces_to_get_occupancy_sensors = 0

    if apply_occupancy == true
      # set list of spaces to skip for each code year
      # In these spaces, ASHRAE 90.1 already requires occuapancy sensors, therefore we will skip these zones when applying the LPD reduction so as to not overestimate savings.
      spaces_to_skip = []
      if ['ComStock 90.1-2004', 'ComStock 90.1-2007'].include?(template)
        spaces_to_skip = %w[Meeting StaffLounge Conference]
      elsif template == 'ComStock 90.1-2010'
        spaces_to_skip = %w[Auditorium Classroom ComputerRoom Restroom Meeting PublicRestroom StaffLounge
                            Storage Back_Space Conference DressingRoom Janitor LockerRoom CompRoomClassRm
                            OfficeSmall StockRoom]
      elsif template == 'ComStock 90.1-2013'
        spaces_to_skip = %w[Auditorium Classroom ComputerRoom Restroom Meeting PublicRestroom StaffLounge
                            Storage Back_Space Conference DressingRoom Janitor LockerRoom CompRoomClassRm
                            OfficeSmall StockRoom GuestLounge Banquet Lounge]
      elsif template == 'ComStock DEER 2011'
        spaces_to_skip = %w[Classroom ComputerRoom Meeting CompRoomClassRm OfficeSmall]
      elsif ['ComStock DEER 2014', 'ComStock DEER 2015', 'ComStock DEER 2017'].include?(template)
        spaces_to_skip = %w[Classroom ComputerRoom Meeting CompRoomClassRm OfficeSmall Restroom GuestLounge
                            PublicRestroom StaffLounge Storage LockerRoom Lounge]
      end

      # set location for csv lookup file
      occupancy_sensor_reduction_by_space_type = File.join(File.dirname(__FILE__), 'resources',
                                                           'occupancy_sensor_reduction_by_space_type.csv')

      model.getSpaceTypes.sort.each do |space_type|
        standard_space_type = space_type.standardsSpaceType.to_s

        lpd_reduction = 0
        found_match = false

        if spaces_to_skip.include?(standard_space_type)
          runner.registerInfo("Occupancy sensors already required by code in space type #{standard_space_type}. This space type will not be modidied.")
        else
          # Do csv lookup using standard_space_type name
          runner.registerInfo("stanard space type = #{standard_space_type}")
          CSV.foreach(occupancy_sensor_reduction_by_space_type, headers: true) do |row|
            if row['standard_space_type'] == standard_space_type
              lpd_reduction = row['lpd_reduction'].to_f
              runner.registerInfo("Interior lighting power reduction for space type #{space_type.name} = #{(lpd_reduction * 100).round(0)}%")
              found_match = true
              runner.registerInfo("found match = #{found_match}")
              break
            end
          end

          if lpd_reduction > 0
            # if the space has a non-zero % reduction, add to list of spaces recieving occupancy controls
            num_spaces_to_get_occupancy_sensors += 1
          end

          unless found_match
            runner.registerInfo("No LPD reduction specified for space type #{space_type.name}. Not adding occupancy sensors.")
          end

          space_type.lights.each do |light|
            next unless light.name.get.include?('General Lighting')

            lights_definition = light.lightsDefinition
            if lights_definition.wattsperSpaceFloorArea.is_initialized
              lpd_existing = lights_definition.wattsperSpaceFloorArea.get
              lpd_new = lpd_existing * (1 - lpd_reduction)

              lights_definition.setWattsperSpaceFloorArea(lpd_new)

              runner.registerInfo("Interior lighting power density for space type #{space_type.name} was reduced by #{(lpd_reduction * 100).round(0)}% from #{lpd_existing.round(2)} W/ft2 to #{lpd_new.round(2)} W/ft2 due to the addition of occupancy sensors.")
            else
              runner.registerWarning("Lighting power is specified using Lighting Level (W) or Lighting Level per Person (W/person) for space type: #{space_type.name}. Measure will not modify lights in this space type.")
            end
          end
        end
      end
    else
      runner.registerInfo('User argument does not request occupancy controls, so none will be added.')
    end

    if num_spaces_to_get_occupancy_sensors + num_spaces_to_get_daylighting_sensors == 0
      runner.registerAsNotApplicable("Neither daylighting sensors nor occupancy sensors were applicable to any spaces in the model. Measure is not applicable.")
    end

    runner.registerFinalCondition("Daylighting sensors were applied to #{num_spaces_to_get_daylighting_sensors} spaces and occupancy sensors were applied to #{num_spaces_to_get_occupancy_sensors} spaces in the model.")

    true
  end
end

# register the measure to be used by the application
LightingControls.new.registerWithApplication
