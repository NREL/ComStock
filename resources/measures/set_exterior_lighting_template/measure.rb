# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'openstudio-standards'
require_relative 'resources/deer_building_types'

# start the measure
class SetExteriorLightingTemplate < OpenStudio::Measure::ModelMeasure
  include DEERBuildingTypes

  # human readable name
  def name
    return 'Set Exterior Lighting Template'
  end

  # human readable description
  def description
    return 'Change the exterior lighting components to make their properties match the selected template.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Change the exterior lighting components to make their properties match the selected template using the OpenStudio Standards methods.  Will replace the existing properties where present.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Templates
    templates = [
      'DEER Pre-1975',
      'DEER 1985',
      'DEER 1996',
      'DEER 2003',
      'DEER 2007',
      'DEER 2011',
      'DEER 2014',
      'DEER 2015',
      'DEER 2017',
      'ComStock DEER Pre-1975',
      'ComStock DEER 1985',
      'ComStock DEER 1996',
      'ComStock DEER 2003',
      'ComStock DEER 2007',
      'ComStock DEER 2011',
      'ComStock DEER 2014',
      'ComStock DEER 2015',
      'ComStock DEER 2017',
      'ComStock DEER 2020',
      'DOE Ref Pre-1980',
      'DOE Ref 1980-2004',
      '90.1-2004',
      '90.1-2007',
      '90.1-2010',
      '90.1-2013',
      '90.1-2016',
      '90.1-2019',
      'ComStock DOE Ref Pre-1980',
      'ComStock DOE Ref 1980-2004',
      'ComStock 90.1-2004',
      'ComStock 90.1-2007',
      'ComStock 90.1-2010',
      'ComStock 90.1-2013',
      'ComStock 90.1-2016',
      'ComStock 90.1-2019'
    ]

    # Climate Zones
    climate_zones = [
      'ASHRAE 169-2013-1A',
      'ASHRAE 169-2013-1B',
      'ASHRAE 169-2013-2A',
      'ASHRAE 169-2013-2B',
      'ASHRAE 169-2013-3A',
      'ASHRAE 169-2013-3B',
      'ASHRAE 169-2013-3C',
      'ASHRAE 169-2013-4A',
      'ASHRAE 169-2013-4B',
      'ASHRAE 169-2013-4C',
      'ASHRAE 169-2013-5A',
      'ASHRAE 169-2013-5B',
      'ASHRAE 169-2013-5C',
      'ASHRAE 169-2013-6A',
      'ASHRAE 169-2013-6B',
      'ASHRAE 169-2013-7A',
      'ASHRAE 169-2013-8A',
      'CEC T24-CEC1',
      'CEC T24-CEC2',
      'CEC T24-CEC3',
      'CEC T24-CEC4',
      'CEC T24-CEC5',
      'CEC T24-CEC6',
      'CEC T24-CEC7',
      'CEC T24-CEC8',
      'CEC T24-CEC9',
      'CEC T24-CEC10',
      'CEC T24-CEC11',
      'CEC T24-CEC12',
      'CEC T24-CEC13',
      'CEC T24-CEC14',
      'CEC T24-CEC15',
      'CEC T24-CEC16'
    ]

    # Make an argument for the as-built template
    template_chs = OpenStudio::StringVector.new
    templates.each do |template|
      template_chs << template
    end
    as_constructed_template = OpenStudio::Measure::OSArgument.makeChoiceArgument('as_constructed_template', template_chs, true)
    as_constructed_template.setDisplayName('As Constructed Template')
    as_constructed_template.setDescription('Template that represents the year the building was first constructed.')
    as_constructed_template.setDefaultValue('DEER 1985')
    args << as_constructed_template

    # Make an argument for the template
    template = OpenStudio::Measure::OSArgument.makeChoiceArgument('template', template_chs, true)
    template.setDisplayName('Template')
    as_constructed_template.setDescription('Template to apply.')
    template.setDefaultValue('DEER 1985')
    args << template

    # Make an argument for the climate zone
    climate_zone_chs = OpenStudio::StringVector.new
    climate_zones.each do |climate_zone|
      climate_zone_chs << climate_zone
    end
    climate_zone = OpenStudio::Measure::OSArgument.makeChoiceArgument('climate_zone', climate_zone_chs, true)
    climate_zone.setDisplayName('Climate Zone')
    climate_zone.setDefaultValue('CEC T24-CEC1')
    args << climate_zone

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables that can be accessed across the measure
    as_constructed_template = runner.getStringArgumentValue('as_constructed_template', user_arguments)
    template = runner.getStringArgumentValue('template', user_arguments)
    climate_zone = runner.getStringArgumentValue('climate_zone', user_arguments)

    runner.registerInfo("Found #{model.getExteriorLightss.size} types of exterior lights in the model.")

    # set additional properties for building
    props = model.getBuilding.additionalProperties
    props.setFeature('exterior_lighting_as_constructed_template', as_constructed_template)
    props.setFeature('exterior_lighting_template', template)

    # Not applicable if the selected template matches the as-constructed template
    if template == as_constructed_template
      runner.registerAsNotApplicable("The exterior lighting is already at the #{template} level, no changes will be made.")
      return true
    end

    # Make a standard
    reset_log
    standard = Standard.build(template)

    # populate search hash
    exterior_lighting_zone_number = 3
    search_criteria = {
      'template' => template,
      'lighting_zone' => exterior_lighting_zone_number
    }

    # load exterior_lighting_properties
    # @todo allow variance in lighting generation and lighting zone number once available in openstudio-standards
    exterior_lighting_properties = OpenstudioStandards::ExteriorLighting.model_get_exterior_lighting_properties(lighting_generation: 'default',
                                                                                                                lighting_zone: 3)
    # make sure lighting properties were found
    if exterior_lighting_properties.nil?
      runner.registerError("Exterior lighting properties not found for #{template}, ext lighting zone #{exterior_lighting_zone_number}, none will be added to model.")
      return false
    end

    # get model specific values to map to exterior_lighting_properties
    area_length_count_hash = OpenstudioStandards::ExteriorLighting.model_get_exterior_lighting_sizes(model)

    # Modify existing exterior lights
    model.getExteriorLightss.each do |ext_lights|
      ext_lights_def = ext_lights.exteriorLightsDefinition
      old_power = ext_lights_def.designLevel
      case ext_lights.endUseSubcategory
      when 'Parking Areas and Drives'
        # adjust exterior lights for parking area
        next unless area_length_count_hash[:parking_area_and_drives_area] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['parking_areas_and_drives']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced parking lot lighting from #{old_power}W/ft^2 to #{new_power}W/ft^2.")
      when 'Main Entries'
        # adjust exterior lights for main entries
        next unless area_length_count_hash[:main_entries] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['main_entries']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced main entry lighting from #{old_power}W/ft to #{new_power}W/ft.")
      when 'Building Facades'
        # adjust exterior lights for building facades
        next unless area_length_count_hash[:building_facades] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['building_facades']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced building facade lighting from #{old_power}W/ft^2 to #{new_power}W/ft^2.")
      when 'Other Doors'
        # adjust exterior lights for other doors
        next unless area_length_count_hash[:other_doors] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['other_doors']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced other doors lighting from #{old_power}W/ft to #{new_power}W/ft.")
      when 'Entry Canopies'
        # adjust exterior lights for entry canopies
        next unless area_length_count_hash[:canopy_entry_area] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['entry_canopies']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced entry canopy lighting from #{old_power}W/ft^2 to #{new_power}W/ft^2.")
      when 'Emergency Canopies'
        # adjust exterior lights for emergency canopies
        next unless area_length_count_hash[:canopy_emergency_area] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['loading_areas_for_emergency_vehicles']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced emergency canopy lighting from #{old_power}W/ft^2 to #{new_power}W/ft^2.")
      when 'Drive Through Windows'
        # adjust exterior lights for drive through windows
        next unless area_length_count_hash[:drive_through_windows] > 0

        # lighting value lookup
        new_power = exterior_lighting_properties['drive_through_windows_and_doors']
        ext_lights_def.setDesignLevel(new_power)
        runner.registerInfo("Reduced drive through window lighting from #{old_power}W to #{new_power}W.")
      else
        runner.registerInfo("Exterior lighting end use subcategory '#{ext_lights.endUseSubcategory}' not recognized for exterior lights '#{ext_light_def.name}' with power #{old_power.round}W.")
      end
    end

    return true
  end
end

# register the measure to be used by the application
SetExteriorLightingTemplate.new.registerWithApplication
