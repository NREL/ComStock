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

# start the measure
class SetInteriorLightingTechnology < OpenStudio::Measure::ModelMeasure

  # human readable name
  def name
    return "set_interior_lighting_technology"
  end

  # human readable description
  def description
    return "This measure takes in lighting technology for different kinds of lighting and adds lighting to space types depending on the prototype lighting space type illuminance targets."
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure takes in lighting technology defined in lumens per watt for different kinds of lighting and adds lighting attached to OS:SpaceType objects depending on the horiztontal illumance target in lumens."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Lighting generations
    lighting_generations = [
      'gen1_t12_incandescent',
      'gen2_t8_halogen',
      'gen3_t5_cfl',
      'gen4_led',
      'gen5_led',
      'gen6_led',
      'gen7_led',
      'gen8_led'
    ]

    # Populate lighting generation options
    lighting_generation_chs = OpenStudio::StringVector.new
    lighting_generations.each do |lighting_generation|
      lighting_generation_chs << lighting_generation
    end

    # Make an argument for lighting generation
    lighting_generation = OpenStudio::Measure::OSArgument.makeChoiceArgument('lighting_generation', lighting_generation_chs, true)
    lighting_generation.setDisplayName('Lighting Generation')
    lighting_generation.setDescription('Lighting generation to determine efficiency level of interior lighting.')
    lighting_generation.setDefaultValue('gen4_led')
    args << lighting_generation

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user input lighting generation to a variable
    lighting_generation = runner.getStringArgumentValue('lighting_generation', user_arguments)

    # load lookup file and convert to hash table
    prototype_lighting_space_type_csv = "#{File.dirname(__FILE__)}/resources/prototype_lighting_space_type.csv"
    if not File.file?(prototype_lighting_space_type_csv)
      runner.registerError("Unable to find file: #{prototype_lighting_space_type_csv}")
      return nil
    end
    prototype_lighting_space_type_tbl = CSV.table(prototype_lighting_space_type_csv)
    prototype_lighting_space_type_hsh = prototype_lighting_space_type_tbl.map { |row| row.to_hash }

    # load lighting technology file and convert to hash table
    lighting_technology_csv = "#{File.dirname(__FILE__)}/resources/lighting_technology.csv"
    if not File.file?(lighting_technology_csv)
      runner.registerError("Unable to find file: #{lighting_technology_csv}")
      return nil
    end
    lighting_technology_tbl = CSV.table(lighting_technology_csv)
    lighting_technology_hsh = lighting_technology_tbl.map { |row| row.to_hash }

    # get lighting technology for the user-selected lighting generation
    lighting_technologies = lighting_technology_hsh.select { |r| (r[:lighting_generation] == lighting_generation) }
    if lighting_technologies.empty?
      runner.registerError("Unable to find lighting technologies for lighting generation '#{lighting_generation}'")
      return nil
    end

    # collectors for building lighting power and floor area
    building_lighting_floor_area = 0.0
    starting_building_lighting_power = 0.0
    ending_building_lighting_power = 0.0

    # model get standards space types
    model.getSpaceTypes.each do |space_type|
      # get space type area and volume
      space_type_floor_area = space_type.floorArea
      if space_type_floor_area.zero?
        runner.registerWarning("Space type #{space_type} floor area is zero.  Ignoring space type.")
        next
      end

      space_type_volume = 0.0
      space_type.spaces.each do |space|
        space_type_volume += space.volume
      end

      if space_type_volume.zero?
        runner.registerError("Volume for space type #{space_type.name} is zero.")
        return false
      elsif space_type_volume.nil?
        runner.registerError("Unable to determine volume for space type #{space_type.name}.")
        return false
      end

      # calculate average space_type height
      space_type_average_height_m = space_type_volume / space_type_floor_area
      space_type_average_height_ft = OpenStudio.convert(space_type_average_height_m, 'm', 'ft').get

      # get number of people for lighting calculations
      space_type_number_of_people = space_type.getNumberOfPeople(space_type_floor_area)

      # get initial conditions
      building_lighting_floor_area = building_lighting_floor_area + space_type_floor_area
      starting_space_type_lighting_power = space_type.getLightingPower(space_type_floor_area, space_type_number_of_people)
      starting_building_lighting_power += starting_space_type_lighting_power

      # remove existing lighting objects
      space_type.lights.sort.each { |light| light.remove }

      # remove existing lighting objects from spaces
      space_type.spaces.each do |space|
        space.lights.sort.each { |light| light.remove }
      end

      # get prototype lighting space type from the model
      has_prototype_lighting_space_type = space_type.additionalProperties.hasFeature('prototype_lighting_space_type')
      unless has_prototype_lighting_space_type
        runner.registerError("Space type '#{space_type.name}' does not have a prototype_lighting_space_type property assigned.  Cannot assign lighting.")
        break
      end
      prototype_lighting_space_type = space_type.additionalProperties.getFeatureAsString('prototype_lighting_space_type').to_s

      # get lighting properties for the prototype lighting space type
      row = prototype_lighting_space_type_hsh.select { |r| (r[:prototype_lighting_space_type] == prototype_lighting_space_type) }
      if row.empty?
        runner.registerError("Unable to find prototype lighting space type data for '#{prototype_lighting_space_type}'")
        break
      end
      prototype_lighting_space_type_properties = row[0]
      total_horizontal_illuminance = prototype_lighting_space_type_properties[:total_horizontal_illuminance_lumens_per_ft2].to_f
      rsdd = prototype_lighting_space_type_properties[:room_surface_dirt_depreciation].to_f
      general_lighting_fraction = prototype_lighting_space_type_properties[:general_lighting_fraction].to_f
      general_cu = prototype_lighting_space_type_properties[:general_lighting_coefficient_of_utilization].to_f
      task_lighting_fraction = prototype_lighting_space_type_properties[:task_lighting_fraction].to_f
      task_cu = prototype_lighting_space_type_properties[:task_lighting_coefficient_of_utilization].to_f
      supplemental_lighting_fraction = prototype_lighting_space_type_properties[:supplemental_lighting_fraction].to_f
      supplemental_cu = prototype_lighting_space_type_properties[:supplemental_lighting_coefficient_of_utilization].to_f
      wall_wash_lighting_fraction = prototype_lighting_space_type_properties[:wall_wash_lighting_fraction].to_f
      wall_wash_cu = prototype_lighting_space_type_properties[:wall_wash_lighting_coefficient_of_utilization].to_f

      # variable holder for lighting technology, default 'na'
      general_lighting_technology_name = 'na'
      task_lighting_technology_name = 'na'
      supplemental_lighting_technology_name = 'na'
      wall_wash_lighting_technology_name = 'na'

      # create new lighting objects based on the lighting technology generation
      # <lighting_type>_lpd_w_per_ft2 =
      # (total_horizontal_illuminance * <lighting_type>_lighting_fraction) / (rsdd * luminous_efficacy * llf * <lighting_type>_cu)

      # general lighting
      if general_lighting_fraction > 0
        matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'general')}
        matching_objects = matching_objects.reject { |r| space_type_average_height_ft.to_f.round(1) > r[:fixture_max_height_ft].to_f.round(1) }
        matching_objects = matching_objects.reject { |r| space_type_average_height_ft.to_f.round(1) <= r[:fixture_min_height_ft].to_f.round(1) }
        general_lighting_technology = matching_objects[0]
        luminous_efficacy = general_lighting_technology[:source_efficacy_lumens_per_watt].to_f
        llf = general_lighting_technology[:lighting_loss_factor].to_f

        # ignore depreciation terms (rsdd, llf) when setting installed lighting power
        general_lpd_w_per_ft2 = (total_horizontal_illuminance * general_lighting_fraction) / (luminous_efficacy * general_cu)
        general_lighting_technology_name = general_lighting_technology[:lighting_technology]

        # general lighting definition
        general_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        general_lights_definition.setName("#{space_type.name} General Lights Definition")
        general_lights_definition.setWattsperSpaceFloorArea(OpenStudio.convert(general_lpd_w_per_ft2, 'W/ft^2', 'W/m^2').get)
        general_lights_definition.setReturnAirFraction(general_lighting_technology[:return_air_fraction].to_f)
        general_lights_definition.setFractionRadiant(general_lighting_technology[:radiant_fraction].to_f)
        general_lights_definition.setFractionVisible(general_lighting_technology[:visible_fraction].to_f)
        general_lights_definition.additionalProperties.setFeature('lighting_technology', general_lighting_technology_name)
        general_lights_definition.additionalProperties.setFeature('lighting_system_type', 'general')
        
        # general lighting object
        general_lights = OpenStudio::Model::Lights.new(general_lights_definition)
        general_lights.setName("#{space_type.name} General Lighting")
        general_lights.setSpaceType(space_type)
      end

      # task lighting
      if task_lighting_fraction > 0
        matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'task')}
        task_lighting_technology = matching_objects[0]
        luminous_efficacy = task_lighting_technology[:source_efficacy_lumens_per_watt].to_f
        llf = task_lighting_technology[:lighting_loss_factor].to_f

        # ignore depreciation terms (rsdd, llf) when setting installed lighting power
        task_lpd_w_per_ft2 = (total_horizontal_illuminance * task_lighting_fraction) / (luminous_efficacy * task_cu)
        task_lighting_technology_name = task_lighting_technology[:lighting_technology]

        # task lighting definition
        task_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        task_lights_definition.setName("#{space_type.name} Task Lights Definition")
        task_lights_definition.setWattsperSpaceFloorArea(OpenStudio.convert(task_lpd_w_per_ft2, 'W/ft^2', 'W/m^2').get)
        task_lights_definition.setReturnAirFraction(task_lighting_technology[:return_air_fraction].to_f)
        task_lights_definition.setFractionRadiant(task_lighting_technology[:radiant_fraction].to_f)
        task_lights_definition.setFractionVisible(task_lighting_technology[:visible_fraction].to_f)
        task_lights_definition.additionalProperties.setFeature('lighting_technology', task_lighting_technology_name)
        task_lights_definition.additionalProperties.setFeature('lighting_system_type', 'task')
        
        # task lighting object
        task_lights = OpenStudio::Model::Lights.new(task_lights_definition)
        task_lights.setName("#{space_type.name} Task Lighting")
        task_lights.setSpaceType(space_type)
      end

      # supplemental lighting
      if supplemental_lighting_fraction > 0
        matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'supplemental')}
        supplemental_lighting_technology = matching_objects[0]
        luminous_efficacy = supplemental_lighting_technology[:source_efficacy_lumens_per_watt].to_f
        llf = supplemental_lighting_technology[:lighting_loss_factor].to_f

        # ignore depreciation terms (rsdd, llf) when setting installed lighting power
        supplemental_lpd_w_per_ft2 = (total_horizontal_illuminance * supplemental_lighting_fraction) / (luminous_efficacy * supplemental_cu)
        supplemental_lighting_technology_name = supplemental_lighting_technology[:lighting_technology]

        # supplemental lighting definition
        supplemental_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        supplemental_lights_definition.setName("#{space_type.name} Supplemental Lights Definition")
        supplemental_lights_definition.setWattsperSpaceFloorArea(OpenStudio.convert(supplemental_lpd_w_per_ft2, 'W/ft^2', 'W/m^2').get)
        supplemental_lights_definition.setReturnAirFraction(supplemental_lighting_technology[:return_air_fraction].to_f)
        supplemental_lights_definition.setFractionRadiant(supplemental_lighting_technology[:radiant_fraction].to_f)
        supplemental_lights_definition.setFractionVisible(supplemental_lighting_technology[:visible_fraction].to_f)
        supplemental_lights_definition.additionalProperties.setFeature('lighting_technology', supplemental_lighting_technology_name)
        supplemental_lights_definition.additionalProperties.setFeature('lighting_system_type', 'supplemental')
        
        # supplemental lighting object
        supplemental_lights = OpenStudio::Model::Lights.new(supplemental_lights_definition)
        supplemental_lights.setName("#{space_type.name} Supplemental Lighting")
        supplemental_lights.setSpaceType(space_type)
      end

      # wall wash lighting
      if wall_wash_lighting_fraction > 0
        matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'wall_wash')}
        wall_wash_lighting_technology = matching_objects[0]
        luminous_efficacy = wall_wash_lighting_technology[:source_efficacy_lumens_per_watt].to_f
        llf = wall_wash_lighting_technology[:lighting_loss_factor].to_f

        # ignore depreciation terms (rsdd, llf) when setting installed lighting power
        wall_wash_lpd_w_per_ft2 = (total_horizontal_illuminance * wall_wash_lighting_fraction) / (luminous_efficacy * wall_wash_cu)
        wall_wash_lighting_technology_name = wall_wash_lighting_technology[:lighting_technology]

        # wall wash lighting definition
        wall_wash_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        wall_wash_lights_definition.setName("#{space_type.name} Wall Wash Lights Definition")
        wall_wash_lights_definition.setWattsperSpaceFloorArea(OpenStudio.convert(wall_wash_lpd_w_per_ft2, 'W/ft^2', 'W/m^2').get)
        wall_wash_lights_definition.setReturnAirFraction(wall_wash_lighting_technology[:return_air_fraction].to_f)
        wall_wash_lights_definition.setFractionRadiant(wall_wash_lighting_technology[:radiant_fraction].to_f)
        wall_wash_lights_definition.setFractionVisible(wall_wash_lighting_technology[:visible_fraction].to_f)
        wall_wash_lights_definition.additionalProperties.setFeature('lighting_technology', wall_wash_lighting_technology_name)
        wall_wash_lights_definition.additionalProperties.setFeature('lighting_system_type', 'wall_wash')
        
        # wall wash lighting object
        wall_wash_lights = OpenStudio::Model::Lights.new(wall_wash_lights_definition)
        wall_wash_lights.setName("#{space_type.name} Wall Wash Lighting")
        wall_wash_lights.setSpaceType(space_type)
      end
      
      ending_space_type_lighting_power = space_type.getLightingPower(space_type_floor_area, space_type_number_of_people)
      ending_building_lighting_power += ending_space_type_lighting_power

      if space_type_floor_area > 0
        starting_space_type_lpd = OpenStudio.convert(starting_space_type_lighting_power / space_type_floor_area, 'W/m^2', 'W/ft^2').get
        ending_space_type_lpd = OpenStudio.convert(ending_space_type_lighting_power / space_type_floor_area, 'W/m^2', 'W/ft^2').get
      else
        starting_space_type_lpd = 'na - no area'
        ending_space_type_lpd = 'na - no area'
      end

      runner.registerInfo("Setting space type '#{space_type.name}' with prototype lighting space type '#{prototype_lighting_space_type}' to lighting generation '#{lighting_generation}', general '#{general_lighting_technology_name}', task '#{task_lighting_technology_name}', supplemental '#{supplemental_lighting_technology_name}', wall_wash '#{wall_wash_lighting_technology_name}'.  Starting LPD #{starting_space_type_lpd.round(2)} W/ft2, ending LPD #{ending_space_type_lpd.round(2)} W/ft2.")
    end

    if building_lighting_floor_area > 0
      starting_building_lpd = OpenStudio.convert(starting_building_lighting_power / building_lighting_floor_area, 'W/m^2', 'W/ft^2').get
      ending_building_lpd = OpenStudio.convert(ending_building_lighting_power / building_lighting_floor_area, 'W/m^2', 'W/ft^2').get
    else
      runner.registerWarning("Building lighting floor area is zero.  This can happen if space types are not assigned to spaces.  Unable to report out building level LPDs.")
      starting_building_lpd = 0
      ending_building_lpd = 0
    end
    runner.registerFinalCondition("Building lighting started with #{starting_building_lighting_power.round(2)} W (average LPD #{starting_building_lpd.round(2)} W/ft2) and ended with #{ending_building_lighting_power.round(2)} W (average LPD #{ending_building_lpd.round(2)} W/ft2).")
    runner.registerValue('set_interior_lighting_technology_initial_lighting_power', starting_building_lighting_power, 'W')
    runner.registerValue('set_interior_lighting_technology_initial_lighting_power_density', starting_building_lpd, 'W/ft^2')
    runner.registerValue('set_interior_lighting_technology_final_lighting_power', ending_building_lighting_power, 'W')
    runner.registerValue('set_interior_lighting_technology_final_lighting_power_density', ending_building_lpd, 'W/ft^2')

    return true
  end
end

# register the measure to be used by the application
SetInteriorLightingTechnology.new.registerWithApplication
