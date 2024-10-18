# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class SetWallTemplate < OpenStudio::Measure::ModelMeasure
  require 'openstudio-standards'

  # human readable name
  def name
    return 'Set Wall Template'
  end

  # human readable description
  def description
    return 'Change the wall components to make their properties match the selected template.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Change the wall components to make their properties match the selected template using the OpenStudio Standards methods.  Will replace the existing properties where present.'
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
    as_constructed_template.setDefaultValue('ComStock DOE Ref 1980-2004')
    args << as_constructed_template

    # Make an argument for the template
    template = OpenStudio::Measure::OSArgument.makeChoiceArgument('template', template_chs, true)
    template.setDisplayName('Template')
    as_constructed_template.setDescription('Template to apply.')
    template.setDefaultValue('ComStock DOE Ref 1980-2004')
    args << template

    # Make an argument for the climate zone
    climate_zone_chs = OpenStudio::StringVector.new
    climate_zones.each do |climate_zone|
      climate_zone_chs << climate_zone
    end
    climate_zone = OpenStudio::Measure::OSArgument.makeChoiceArgument('climate_zone', climate_zone_chs, true)
    climate_zone.setDisplayName('Climate Zone')
    climate_zone.setDefaultValue('ASHRAE 169-2013-2B')
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

    # set additional properties for building
    props = model.getBuilding.additionalProperties
    props.setFeature('wall_as_constructed_template', as_constructed_template)
    props.setFeature('wall_template', template)

    # Not applicable if the selected template matches the as-constructed template
    if template == as_constructed_template
      runner.registerAsNotApplicable("The building walls are already at the #{template} level, no changes will be made.")
      return true
    end

    # Make a standard
    reset_log
    standard = Standard.build(template)

    # Apply standard constructions to this model at the surface-by-surface level,
    # which will override default contruction sets for the surface types being updated,
    # which is not all surface types.
    types_to_modify = []
    types_to_modify << ['Outdoors', 'Wall']

    # Find just those surfaces
    surfaces_to_modify = []
    types_to_modify.each do |boundary_condition, surface_type|
      # Surfaces
      model.getSurfaces.sort.each do |surf|
        next unless surf.outsideBoundaryCondition == boundary_condition
        next unless surf.surfaceType == surface_type

        surfaces_to_modify << surf
      end

      # SubSurfaces
      model.getSubSurfaces.sort.each do |surf|
        next unless surf.outsideBoundaryCondition == boundary_condition
        next unless surf.subSurfaceType == surface_type

        surfaces_to_modify << surf
      end
    end

    # Modify these surfaces
    prev_created_consts = {}
    surfaces_to_modify.sort.each do |surf|
      prev_created_consts = standard.planar_surface_apply_standard_construction(surf, climate_zone, prev_created_consts)
    end

    # List the unique array of constructions
    prev_created_consts.each do |surf_type, construction|
      runner.registerInfo("For #{surf_type.join(' ')}, applied #{construction.name}.")
    end

    log_messages_to_runner(runner, debug = false)
    reset_log

    if prev_created_consts.empty?
      runner.registerAsNotApplicable("Found no #{surf_type.join(' ')} surfaces in the model to update")
    end

    return true
  end
end

# register the measure to be used by the application
SetWallTemplate.new.registerWithApplication
