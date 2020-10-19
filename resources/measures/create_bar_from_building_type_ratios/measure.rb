# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2020, Alliance for Sustainable Energy, LLC.
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

require 'openstudio-standards'

begin
  # load OpenStudio measure libraries from common location
  require 'measure_resources/os_lib_helper_methods'
  require 'measure_resources/os_lib_geometry'
  require 'measure_resources/os_lib_model_generation'
  require 'measure_resources/os_lib_model_simplification'
rescue LoadError
  # common location unavailable, load from local resources
  require_relative 'resources/os_lib_helper_methods'
  require_relative 'resources/os_lib_geometry'
  require_relative 'resources/os_lib_model_generation'
  require_relative 'resources/os_lib_model_simplification'
end

# start the measure
class CreateBarFromBuildingTypeRatios < OpenStudio::Measure::ModelMeasure
  # resource file modules
  include OsLib_HelperMethods
  include OsLib_Geometry
  include OsLib_ModelGeneration
  include OsLib_ModelSimplification

  # human readable name
  def name
    return 'Create Bar From Building Type Ratios'
  end

  # human readable description
  def description
    return 'Creates one or more rectangular building elements based on space type ratios of selected mix of building types, along with user arguments that describe the desired geometry characteristics.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'The building floor area can be described as a footprint size or as a total building area. The shape can be described by its aspect ratio or can be defined as a set width. Because this measure contains both DOE and DEER inputs, care needs to be taken to choose a template compatable with the selected building types. See readme document for additional guidance.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make an argument for the bldg_type_a
    bldg_type_a = OpenStudio::Measure::OSArgument.makeChoiceArgument('bldg_type_a', get_building_types, true)
    bldg_type_a.setDisplayName('Primary Building Type')
    bldg_type_a.setDefaultValue('SmallOffice')
    args << bldg_type_a

    # Make argument for bldg_type_a_num_units
    bldg_type_a_num_units = OpenStudio::Measure::OSArgument.makeIntegerArgument('bldg_type_a_num_units', true)
    bldg_type_a_num_units.setDisplayName('Primary Building Type Number of Units')
    bldg_type_a_num_units.setDescription('Number of units argument not currently used by this measure')
    bldg_type_a_num_units.setDefaultValue(1)
    args << bldg_type_a_num_units

    # Make an argument for the bldg_type_b
    bldg_type_b = OpenStudio::Measure::OSArgument.makeChoiceArgument('bldg_type_b', get_building_types, true)
    bldg_type_b.setDisplayName('Building Type B')
    bldg_type_b.setDefaultValue('SmallOffice')
    args << bldg_type_b

    # Make argument for bldg_type_b_fract_bldg_area
    bldg_type_b_fract_bldg_area = OpenStudio::Measure::OSArgument.makeDoubleArgument('bldg_type_b_fract_bldg_area', true)
    bldg_type_b_fract_bldg_area.setDisplayName('Building Type B Fraction of Building Floor Area')
    bldg_type_b_fract_bldg_area.setDefaultValue(0.0)
    args << bldg_type_b_fract_bldg_area

    # Make argument for bldg_type_b_num_units
    bldg_type_b_num_units = OpenStudio::Measure::OSArgument.makeIntegerArgument('bldg_type_b_num_units', true)
    bldg_type_b_num_units.setDisplayName('Building Type B Number of Units')
    bldg_type_b_num_units.setDescription('Number of units argument not currently used by this measure')
    bldg_type_b_num_units.setDefaultValue(1)
    args << bldg_type_b_num_units

    # Make an argument for the bldg_type_c
    bldg_type_c = OpenStudio::Measure::OSArgument.makeChoiceArgument('bldg_type_c', get_building_types, true)
    bldg_type_c.setDisplayName('Building Type C')
    bldg_type_c.setDefaultValue('SmallOffice')
    args << bldg_type_c

    # Make argument for bldg_type_c_fract_bldg_area
    bldg_type_c_fract_bldg_area = OpenStudio::Measure::OSArgument.makeDoubleArgument('bldg_type_c_fract_bldg_area', true)
    bldg_type_c_fract_bldg_area.setDisplayName('Building Type C Fraction of Building Floor Area')
    bldg_type_c_fract_bldg_area.setDefaultValue(0.0)
    args << bldg_type_c_fract_bldg_area

    # Make argument for bldg_type_c_num_units
    bldg_type_c_num_units = OpenStudio::Measure::OSArgument.makeIntegerArgument('bldg_type_c_num_units', true)
    bldg_type_c_num_units.setDisplayName('Building Type C Number of Units')
    bldg_type_c_num_units.setDescription('Number of units argument not currently used by this measure')
    bldg_type_c_num_units.setDefaultValue(1)
    args << bldg_type_c_num_units

    # Make an argument for the bldg_type_d
    bldg_type_d = OpenStudio::Measure::OSArgument.makeChoiceArgument('bldg_type_d', get_building_types, true)
    bldg_type_d.setDisplayName('Building Type D')
    bldg_type_d.setDefaultValue('SmallOffice')
    args << bldg_type_d

    # Make argument for bldg_type_d_fract_bldg_area
    bldg_type_d_fract_bldg_area = OpenStudio::Measure::OSArgument.makeDoubleArgument('bldg_type_d_fract_bldg_area', true)
    bldg_type_d_fract_bldg_area.setDisplayName('Building Type D Fraction of Building Floor Area')
    bldg_type_d_fract_bldg_area.setDefaultValue(0.0)
    args << bldg_type_d_fract_bldg_area

    # Make argument for bldg_type_d_num_units
    bldg_type_d_num_units = OpenStudio::Measure::OSArgument.makeIntegerArgument('bldg_type_d_num_units', true)
    bldg_type_d_num_units.setDisplayName('Building Type D Number of Units')
    bldg_type_d_num_units.setDescription('Number of units argument not currently used by this measure')
    bldg_type_d_num_units.setDefaultValue(1)
    args << bldg_type_d_num_units

    # Make argument for single_floor_area
    single_floor_area = OpenStudio::Measure::OSArgument.makeDoubleArgument('single_floor_area', true)
    single_floor_area.setDisplayName('Single Floor Area')
    single_floor_area.setDescription('Non-zero value will fix the single floor area, overriding a user entry for Total Building Floor Area')
    single_floor_area.setUnits('ft^2')
    single_floor_area.setDefaultValue(0.0)
    args << single_floor_area

    # Make argument for total_bldg_floor_area
    total_bldg_floor_area = OpenStudio::Measure::OSArgument.makeDoubleArgument('total_bldg_floor_area', true)
    total_bldg_floor_area.setDisplayName('Total Building Floor Area')
    total_bldg_floor_area.setUnits('ft^2')
    total_bldg_floor_area.setDefaultValue(10000.0)
    args << total_bldg_floor_area

    # Make argument for floor_height
    floor_height = OpenStudio::Measure::OSArgument.makeDoubleArgument('floor_height', true)
    floor_height.setDisplayName('Typical Floor to FLoor Height')
    floor_height.setDescription('Selecting a typical floor height of 0 will trigger a smart building type default.')
    floor_height.setUnits('ft')
    floor_height.setDefaultValue(0.0)
    args << floor_height

    # add argument to enable/disable multi custom space height bar
    custom_height_bar = OpenStudio::Measure::OSArgument.makeBoolArgument('custom_height_bar', true)
    custom_height_bar.setDisplayName('Enable Custom Height Bar Application')
    custom_height_bar.setDescription('This is argument value is only relevant when smart default floor to floor height is used for a building type that has spaces with custom heights.')
    custom_height_bar.setDefaultValue(true)
    args << custom_height_bar

    # Make argument for num_stories_above_grade
    num_stories_above_grade = OpenStudio::Measure::OSArgument.makeDoubleArgument('num_stories_above_grade', true)
    num_stories_above_grade.setDisplayName('Number of Stories Above Grade')
    num_stories_above_grade.setDefaultValue(1.0)
    args << num_stories_above_grade

    # Make argument for num_stories_below_grade
    num_stories_below_grade = OpenStudio::Measure::OSArgument.makeIntegerArgument('num_stories_below_grade', true)
    num_stories_below_grade.setDisplayName('Number of Stories Below Grade')
    num_stories_below_grade.setDefaultValue(0)
    args << num_stories_below_grade

    # Make argument for building_rotation
    building_rotation = OpenStudio::Measure::OSArgument.makeDoubleArgument('building_rotation', true)
    building_rotation.setDisplayName('Building Rotation')
    building_rotation.setDescription('Set Building Rotation off of North (positive value is clockwise). Rotation applied after geometry generation. Values greater than +/- 45 will result in aspect ratio and party wall orientations that do not match cardinal directions of the inputs.')
    building_rotation.setUnits('Degrees')
    building_rotation.setDefaultValue(0.0)
    args << building_rotation

    # Make argument for template
    template = OpenStudio::Measure::OSArgument.makeChoiceArgument('template', get_templates(true), true)
    template.setDisplayName('Target Standard')
    template.setDefaultValue('90.1-2004')
    args << template

    # Make argument for ns_to_ew_ratio
    ns_to_ew_ratio = OpenStudio::Measure::OSArgument.makeDoubleArgument('ns_to_ew_ratio', true)
    ns_to_ew_ratio.setDisplayName('Ratio of North/South Facade Length Relative to East/West Facade Length')
    ns_to_ew_ratio.setDescription('Selecting an aspect ratio of 0 will trigger a smart building type default. Aspect ratios less than one are not recommended for sliced bar geometry, instead rotate building and use a greater than 1 aspect ratio.')
    ns_to_ew_ratio.setDefaultValue(0.0)
    args << ns_to_ew_ratio

    # Make argument for perim_mult
    perim_mult = OpenStudio::Measure::OSArgument.makeDoubleArgument('perim_mult', true)
    perim_mult.setDisplayName('Perimeter Multiplier')
    perim_mult.setDescription('Selecting a value of 0 will trigger a smart building type default. This represents a multiplier for the building perimeter relative to the perimeter of a rectangular building that meets the area and aspect ratio inputs. Other than the smart default of 0.0 this argument should have a value of 1.0 or higher and is only applicable Multiple Space Types - Individual Stories Sliced division method.')
    perim_mult.setDefaultValue(0.0)
    args << perim_mult

    # Make argument for bar_width
    bar_width = OpenStudio::Measure::OSArgument.makeDoubleArgument('bar_width', true)
    bar_width.setDisplayName('Bar Width')
    bar_width.setDescription('Non-zero value will fix the building width, overriding user entry for Perimeter Multiplier. NS/EW Aspect Ratio may be limited based on target width.')
    bar_width.setUnits('ft')
    bar_width.setDefaultValue(0.0)
    args << bar_width

    # Make argument for bar_sep_dist_mult
    bar_sep_dist_mult = OpenStudio::Measure::OSArgument.makeDoubleArgument('bar_sep_dist_mult', true)
    bar_sep_dist_mult.setDisplayName('Bar Separation Distance Multiplier')
    bar_sep_dist_mult.setDescription('Multiplier of separation between bar elements relative to building height.')
    bar_sep_dist_mult.setDefaultValue(10.0)
    args << bar_sep_dist_mult

    # Make argument for wwr (in future add lookup for smart default)
    wwr = OpenStudio::Measure::OSArgument.makeDoubleArgument('wwr', true)
    wwr.setDisplayName('Window to Wall Ratio')
    wwr.setDescription('Selecting a window to wall ratio of 0 will trigger a smart building type default.')
    wwr.setDefaultValue(0.0)
    args << wwr

    # Make argument for party_wall_fraction
    party_wall_fraction = OpenStudio::Measure::OSArgument.makeDoubleArgument('party_wall_fraction', true)
    party_wall_fraction.setDisplayName('Fraction of Exterior Wall Area with Adjacent Structure')
    party_wall_fraction.setDescription('This will impact how many above grade exterior walls are modeled with adiabatic boundary condition.')
    party_wall_fraction.setDefaultValue(0.0)
    args << party_wall_fraction

    # party_wall_fraction was used where we wanted to represent some party walls but didn't know where they are, it ends up using methods to make whole surfaces adiabiatc by story and orientaiton to try to come close to requested fraction

    # Make argument for party_wall_stories_north
    party_wall_stories_north = OpenStudio::Measure::OSArgument.makeIntegerArgument('party_wall_stories_north', true)
    party_wall_stories_north.setDisplayName('Number of North facing stories with party wall')
    party_wall_stories_north.setDescription('This will impact how many above grade exterior north walls are modeled with adiabatic boundary condition. If this is less than the number of above grade stoes, upper flor will reamin exterior')
    party_wall_stories_north.setDefaultValue(0)
    args << party_wall_stories_north

    # Make argument for party_wall_stories_south
    party_wall_stories_south = OpenStudio::Measure::OSArgument.makeIntegerArgument('party_wall_stories_south', true)
    party_wall_stories_south.setDisplayName('Number of South facing stories with party wall')
    party_wall_stories_south.setDescription('This will impact how many above grade exterior south walls are modeled with adiabatic boundary condition. If this is less than the number of above grade stoes, upper flor will reamin exterior')
    party_wall_stories_south.setDefaultValue(0)
    args << party_wall_stories_south

    # Make argument for party_wall_stories_east
    party_wall_stories_east = OpenStudio::Measure::OSArgument.makeIntegerArgument('party_wall_stories_east', true)
    party_wall_stories_east.setDisplayName('Number of East facing stories with party wall')
    party_wall_stories_east.setDescription('This will impact how many above grade exterior east walls are modeled with adiabatic boundary condition. If this is less than the number of above grade stoes, upper flor will reamin exterior')
    party_wall_stories_east.setDefaultValue(0)
    args << party_wall_stories_east

    # Make argument for party_wall_stories_west
    party_wall_stories_west = OpenStudio::Measure::OSArgument.makeIntegerArgument('party_wall_stories_west', true)
    party_wall_stories_west.setDisplayName('Number of West facing stories with party wall')
    party_wall_stories_west.setDescription('This will impact how many above grade exterior west walls are modeled with adiabatic boundary condition. If this is less than the number of above grade stoes, upper flor will reamin exterior')
    party_wall_stories_west.setDefaultValue(0)
    args << party_wall_stories_west

    # Make argument for neighbor height specification method
    neighbor_height_method_chs = OpenStudio::StringVector.new
    neighbor_height_method_chs << 'Absolute'
    neighbor_height_method_chs << 'Relative'
    neighbor_height_method = OpenStudio::Measure::OSArgument.makeChoiceArgument('neighbor_height_method', neighbor_height_method_chs, true)
    neighbor_height_method.setDisplayName('Neighbor height specification method')
    neighbor_height_method.setDescription('Absolute will use heights specified by cardinal direction. Relative will use height offset.')
    neighbor_height_method.setDefaultValue('Absolute')
    args << neighbor_height_method

    # Make argument for height of neighboring building to the north
    building_height_relative_to_neighbors = OpenStudio::Measure::OSArgument.makeDoubleArgument('building_height_relative_to_neighbors', true)
    building_height_relative_to_neighbors.setDisplayName('Height of this building relative to neighboring buildings relative')
    building_height_relative_to_neighbors.setDescription('Negative number means neighbors are taller than this building, Positive number means neighbors are shorter than this building.')
    building_height_relative_to_neighbors.setDefaultValue(0)
    building_height_relative_to_neighbors.setUnits('ft')
    args << building_height_relative_to_neighbors

    # Make argument for height of neighboring building to the north
    neighbor_height_north = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_height_north', true)
    neighbor_height_north.setDisplayName('Height of neighboring building to the north')
    neighbor_height_north.setDescription('If greater than zero, adds a shade the width of the building with the specified height to the north of the building. Only used if Neighbor height specification method is individual. Use party walls for attached buildings. Neighbors rotate with building.')
    neighbor_height_north.setDefaultValue(0)
    neighbor_height_north.setUnits('ft')
    args << neighbor_height_north

    # Make argument for height of neighboring building to the south
    neighbor_height_south = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_height_south', true)
    neighbor_height_south.setDisplayName('Height of neighboring building to the south')
    neighbor_height_south.setDescription('If greater than zero, adds a shade the width of the building with the specified height to the south of the building. Only used if Neighbor height specification method is individual. Use party walls for attached buildings. Neighbors rotate with building.')
    neighbor_height_south.setDefaultValue(0)
    neighbor_height_south.setUnits('ft')
    args << neighbor_height_south

    # Make argument for height of neighboring building to the east
    neighbor_height_east = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_height_east', true)
    neighbor_height_east.setDisplayName('Height of neighboring building to the east')
    neighbor_height_east.setDescription('If greater than zero, adds a shade the width of the building with the specified height to the east of the building. Only used if Neighbor height specification method is individual. Use party walls for attached buildings. Neighbors rotate with building.')
    neighbor_height_east.setDefaultValue(0)
    neighbor_height_east.setUnits('ft')
    args << neighbor_height_east

    # Make argument for height of neighboring building to the west
    neighbor_height_west = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_height_west', true)
    neighbor_height_west.setDisplayName('Height of neighboring building to the west')
    neighbor_height_west.setDescription('If greater than zero, adds a shade the width of the building with the specified height to the west of the building. Only used if Neighbor height specification method is individual. Use party walls for attached buildings. Neighbors rotate with building.')
    neighbor_height_west.setDefaultValue(0)
    neighbor_height_west.setUnits('ft')
    args << neighbor_height_west

    # Make argument for offset distance of neighboring building to the north
    neighbor_offset_north = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_offset_north', true)
    neighbor_offset_north.setDisplayName('Distance of neighboring building to the north')
    neighbor_offset_north.setDescription('If greater than zero, puts the shade at a specified distance to the north of the building.')
    neighbor_offset_north.setDefaultValue(0)
    neighbor_offset_north.setUnits('ft')
    args << neighbor_offset_north

    # Make argument for offset distance of neighboring building to the south
    neighbor_offset_south = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_offset_south', true)
    neighbor_offset_south.setDisplayName('Distance of neighboring building to the south')
    neighbor_offset_south.setDescription('If greater than zero, puts the shade at a specified distance to the south of the building.')
    neighbor_offset_south.setDefaultValue(0)
    neighbor_offset_south.setUnits('ft')
    args << neighbor_offset_south

    # Make argument for offset distance of neighboring building to the east
    neighbor_offset_east = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_offset_east', true)
    neighbor_offset_east.setDisplayName('Distance of neighboring building to the east')
    neighbor_offset_east.setDescription('If greater than zero, puts the shade at a specified distance to the east of the building.')
    neighbor_offset_east.setDefaultValue(0)
    neighbor_offset_east.setUnits('ft')
    args << neighbor_offset_east

    # Make argument for offset distance of neighboring building to the west
    neighbor_offset_west = OpenStudio::Measure::OSArgument.makeDoubleArgument('neighbor_offset_west', true)
    neighbor_offset_west.setDisplayName('Distance of neighboring building to the west')
    neighbor_offset_west.setDescription('If greater than zero, puts the shade at a specified distance to the west of the building.')
    neighbor_offset_west.setDefaultValue(0)
    neighbor_offset_west.setUnits('ft')
    args << neighbor_offset_west

    # make an argument for bottom_story_ground_exposed_floor
    bottom_story_ground_exposed_floor = OpenStudio::Measure::OSArgument.makeBoolArgument('bottom_story_ground_exposed_floor', true)
    bottom_story_ground_exposed_floor.setDisplayName('Is the Bottom Story Exposed to Ground')
    bottom_story_ground_exposed_floor.setDescription("This should be true unless you are modeling a partial building which doesn't include the lowest story. The bottom story floor will have an adiabatic boundary condition when false.")
    bottom_story_ground_exposed_floor.setDefaultValue(true)
    args << bottom_story_ground_exposed_floor

    # make an argument for top_story_exterior_exposed_roof
    top_story_exterior_exposed_roof = OpenStudio::Measure::OSArgument.makeBoolArgument('top_story_exterior_exposed_roof', true)
    top_story_exterior_exposed_roof.setDisplayName('Is the Top Story an Exterior Roof')
    top_story_exterior_exposed_roof.setDescription("This should be true unless you are modeling a partial building which doesn't include the highest story. The top story ceiling will have an adiabatic boundary condition when false.")
    top_story_exterior_exposed_roof.setDefaultValue(true)
    args << top_story_exterior_exposed_roof

    # Make argument for story_multiplier
    choices = OpenStudio::StringVector.new
    choices << 'None'
    choices << 'Basements Ground Mid Top'
    # choices << "Basements Ground Midx5 Top"
    story_multiplier = OpenStudio::Measure::OSArgument.makeChoiceArgument('story_multiplier', choices, true)
    story_multiplier.setDisplayName('Calculation Method for Story Multiplier')
    story_multiplier.setDefaultValue('Basements Ground Mid Top')
    args << story_multiplier

    # make an argument for make_mid_story_surfaces_adiabatic (added to avoid issues with intersect and to lower surface count when using individual stories sliced)
    make_mid_story_surfaces_adiabatic = OpenStudio::Measure::OSArgument.makeBoolArgument('make_mid_story_surfaces_adiabatic', true)
    make_mid_story_surfaces_adiabatic.setDisplayName('Make Mid Story Floor Surfaces Adibatic')
    make_mid_story_surfaces_adiabatic.setDescription('If set to true, this will skip surface intersection and make mid story floors and celings adiabiatc, not just at multiplied gaps.')
    make_mid_story_surfaces_adiabatic.setDefaultValue(false)
    args << make_mid_story_surfaces_adiabatic

    # make an argument for bar sub-division approach
    choices = OpenStudio::StringVector.new
    choices << 'Multiple Space Types - Simple Sliced'
    choices << 'Multiple Space Types - Individual Stories Sliced'
    choices << 'Single Space Type - Core and Perimeter' # not useful for most use cases
    # choices << "Multiple Space Types - Individual Stories Sliced Keep Building Types Together"
    # choices << "Building Type Specific Smart Division"
    bar_division_method = OpenStudio::Measure::OSArgument.makeChoiceArgument('bar_division_method', choices, true)
    bar_division_method.setDisplayName('Division Method for Bar Space Types')
    bar_division_method.setDescription('To use perimeter multiplier greater than 1 selected Multiple Space Types - Individual Stories Sliced.')
    bar_division_method.setDefaultValue('Multiple Space Types - Individual Stories Sliced')
    args << bar_division_method

    # double_loaded_corridor
    choices = OpenStudio::StringVector.new
    choices << 'None'
    choices << 'Primary Space Type'
    # choices << 'All Space Types' # possible future option
    double_loaded_corridor = OpenStudio::Measure::OSArgument.makeChoiceArgument('double_loaded_corridor', choices, true)
    double_loaded_corridor.setDisplayName('Double Loaded Corridor')
    double_loaded_corridor.setDescription('Add double loaded corridor for building types that have a defined circulation space type, to the selected space types.')
    double_loaded_corridor.setDefaultValue('Primary Space Type')
    args << double_loaded_corridor

    # Make argument for space_type_sort_logic
    # todo - fix size to work, seems to always do by building type, but just reverses the building order
    choices = OpenStudio::StringVector.new
    choices << 'Size'
    choices << 'Building Type > Size'
    space_type_sort_logic = OpenStudio::Measure::OSArgument.makeChoiceArgument('space_type_sort_logic', choices, true)
    space_type_sort_logic.setDisplayName('Choose Space Type Sorting Method')
    space_type_sort_logic.setDefaultValue('Building Type > Size')
    args << space_type_sort_logic

    # make an argument for use_upstream_args
    use_upstream_args = OpenStudio::Measure::OSArgument.makeBoolArgument('use_upstream_args', true)
    use_upstream_args.setDisplayName('Use Upstream Argument Values')
    use_upstream_args.setDescription('When true this will look for arguments or registerValues in upstream measures that match arguments from this measure, and will use the value from the upstream measure in place of what is entered for this measure.')
    use_upstream_args.setDefaultValue(true)
    args << use_upstream_args

    # TODO: - expose perimeter depth as an argument

    # Argument used to make ComStock tsv workflow run correctly
    cz_choices = OpenStudio::StringVector.new
    cz_choices << 'Lookup From Stat File'
    cz_choices << 'ASHRAE 169-2013-1A'
    cz_choices << 'ASHRAE 169-2013-1B'
    cz_choices << 'ASHRAE 169-2013-2A'
    cz_choices << 'ASHRAE 169-2013-2B'
    cz_choices << 'ASHRAE 169-2013-3A'
    cz_choices << 'ASHRAE 169-2013-3B'
    cz_choices << 'ASHRAE 169-2013-3C'
    cz_choices << 'ASHRAE 169-2013-4A'
    cz_choices << 'ASHRAE 169-2013-4B'
    cz_choices << 'ASHRAE 169-2013-4C'
    cz_choices << 'ASHRAE 169-2013-5A'
    cz_choices << 'ASHRAE 169-2013-5B'
    cz_choices << 'ASHRAE 169-2013-5C'
    cz_choices << 'ASHRAE 169-2013-6A'
    cz_choices << 'ASHRAE 169-2013-6B'
    cz_choices << 'ASHRAE 169-2013-7A'
    cz_choices << 'ASHRAE 169-2013-8A'
    cz_choices << 'CEC T24-CEC1'
    cz_choices << 'CEC T24-CEC2'
    cz_choices << 'CEC T24-CEC3'
    cz_choices << 'CEC T24-CEC4'
    cz_choices << 'CEC T24-CEC5'
    cz_choices << 'CEC T24-CEC6'
    cz_choices << 'CEC T24-CEC7'
    cz_choices << 'CEC T24-CEC8'
    cz_choices << 'CEC T24-CEC9'
    cz_choices << 'CEC T24-CEC10'
    cz_choices << 'CEC T24-CEC11'
    cz_choices << 'CEC T24-CEC12'
    cz_choices << 'CEC T24-CEC13'
    cz_choices << 'CEC T24-CEC14'
    cz_choices << 'CEC T24-CEC15'
    cz_choices << 'CEC T24-CEC16'
    climate_zone = OpenStudio::Measure::OSArgument.makeChoiceArgument('climate_zone', cz_choices, true)
    climate_zone.setDisplayName('Climate Zone.')
    climate_zone.setDefaultValue('CEC T24-CEC1')
    args << climate_zone

    return args
  end

  # # define what happens when the measure is run
  # def run(model, runner, user_arguments)
  #   super(model, runner, user_arguments)
  #
  #   # assign the user inputs to variables
  #   args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments(model))
  #   if !args then return false end
  #
  #   # lookup and replace argument values from upstream measures
  #   if args['use_upstream_args'] == true
  #     args.each do |arg,value|
  #       next if arg == 'use_upstream_args' # this argument should not be changed
  #       value_from_osw = OsLib_HelperMethods.check_upstream_measure_for_arg(runner, arg)
  #       if !value_from_osw.empty?
  #         runner.registerInfo("Replacing argument named #{arg} from current measure with a value of #{value_from_osw[:value]} from #{value_from_osw[:measure_name]}.")
  #         new_val = value_from_osw[:value]
  #         # todo - make code to handle non strings more robust. check_upstream_measure_for_arg coudl pass bakc the argument type
  #         if arg == 'total_bldg_floor_area'
  #           args[arg] = new_val.to_f
  #         elsif arg == 'num_stories_above_grade'
  #           args[arg] = new_val.to_f
  #         elsif arg == 'zipcode'
  #           args[arg] = new_val.to_i
  #         else
  #           args[arg] = new_val
  #         end
  #       end
  #     end
  #   end
  #
  #   # check expected values of double arguments
  #   fraction_args = ['bldg_type_b_fract_bldg_area',
  #                    'bldg_type_c_fract_bldg_area',
  #                    'bldg_type_d_fract_bldg_area',
  #                    'wwr', 'party_wall_fraction']
  #   fraction = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => 1.0, 'min_eq_bool' => true, 'max_eq_bool' => true, 'arg_array' => fraction_args)
  #
  #   positive_args = ['total_bldg_floor_area']
  #   positive = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => nil, 'min_eq_bool' => false, 'max_eq_bool' => false, 'arg_array' => positive_args)
  #
  #   one_or_greater_args = ['num_stories_above_grade']
  #   one_or_greater = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 1.0, 'max' => nil, 'min_eq_bool' => true, 'max_eq_bool' => false, 'arg_array' => one_or_greater_args)
  #
  #   non_neg_args = ['bldg_type_a_num_units',
  #                   'bldg_type_c_num_units',
  #                   'bldg_type_d_num_units',
  #                   'num_stories_below_grade',
  #                   'floor_height',
  #                   'ns_to_ew_ratio',
  #                   'party_wall_stories_north',
  #                   'party_wall_stories_south',
  #                   'party_wall_stories_east',
  #                   'party_wall_stories_west',
  #                   'neighbor_height_north',
  #                   'neighbor_offset_north',
  #                   'neighbor_height_south',
  #                   'neighbor_offset_south',
  #                   'neighbor_height_east',
  #                   'neighbor_offset_east',
  #                   'neighbor_height_west',
  #                   'neighbor_offset_west',
  #                   'single_floor_area']
  #   non_neg = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => nil, 'min_eq_bool' => true, 'max_eq_bool' => false, 'arg_array' => non_neg_args)
  #
  #   # return false if any errors fail
  #   if !fraction then return false end
  #   if !positive then return false end
  #   if !one_or_greater then return false end
  #   if !non_neg then return false end
  #
  #   # if aspect ratio, story height or wwr have argument value of 0 then use smart building type defaults
  #   building_form_defaults = building_form_defaults(args['bldg_type_a'])
  #   if args['ns_to_ew_ratio'] == 0.0
  #     args['ns_to_ew_ratio'] = building_form_defaults[:aspect_ratio]
  #     runner.registerInfo("0.0 value for aspect ratio will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:aspect_ratio]}.")
  #   end
  #   if args['floor_height'] == 0.0
  #     args['floor_height'] = building_form_defaults[:typical_story]
  #     runner.registerInfo("0.0 value for floor height will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:typical_story]}.")
  #   end
  #   # because of this can't set wwr to 0.0. If that is desired then we can change this to check for 1.0 instead of 0.0
  #   if args['wwr'] == 0.0
  #     args['wwr'] = building_form_defaults[:wwr]
  #     runner.registerInfo("0.0 value for window to wall ratio will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:wwr]}.")
  #   end
  #
  #   # check that sum of fractions for b,c, and d is less than 1.0 (so something is left for primary building type)
  #   bldg_type_a_fract_bldg_area = 1.0 - args['bldg_type_b_fract_bldg_area'] - args['bldg_type_c_fract_bldg_area'] - args['bldg_type_d_fract_bldg_area']
  #   if bldg_type_a_fract_bldg_area <= 0.0
  #     runner.registerError('Primary Building Type fraction of floor area must be greater than 0. Please lower one or more of the fractions for Building Type B-D.')
  #     return false
  #   end
  #
  #   # Make the standard applier
  #   standard = Standard.build("#{args['template']}")
  #
  #   # report initial condition of model
  #   runner.registerInitialCondition("The building started with #{model.getSpaces.size} spaces.")
  #
  #   # set building rotation
  #   initial_rotation = model.getBuilding.northAxis
  #   if args['building_rotation'] != initial_rotation
  #     model.getBuilding.setNorthAxis(args['building_rotation'])
  #     runner.registerInfo("Set Building Rotation to #{model.getBuilding.northAxis}")
  #   end
  #
  #   # hash to old building type data
  #   building_type_hash = {}
  #
  #   # gather data for bldg_type_a
  #   building_type_hash[args['bldg_type_a']] = {}
  #   building_type_hash[args['bldg_type_a']][:frac_bldg_area] = bldg_type_a_fract_bldg_area
  #   building_type_hash[args['bldg_type_a']][:num_units] = args['bldg_type_a_num_units']
  #   building_type_hash[args['bldg_type_a']][:space_types] = get_space_types_from_building_type(args['bldg_type_a'], args['template'], true)
  #
  #   # gather data for bldg_type_b
  #   if args['bldg_type_b_fract_bldg_area'] > 0
  #     building_type_hash[args['bldg_type_b']] = {}
  #     building_type_hash[args['bldg_type_b']][:frac_bldg_area] = args['bldg_type_b_fract_bldg_area']
  #     building_type_hash[args['bldg_type_b']][:num_units] = args['bldg_type_b_num_units']
  #     building_type_hash[args['bldg_type_b']][:space_types] = get_space_types_from_building_type(args['bldg_type_b'], args['template'], true)
  #   end
  #
  #   # gather data for bldg_type_c
  #   if args['bldg_type_c_fract_bldg_area'] > 0
  #     building_type_hash[args['bldg_type_c']] = {}
  #     building_type_hash[args['bldg_type_c']][:frac_bldg_area] = args['bldg_type_c_fract_bldg_area']
  #     building_type_hash[args['bldg_type_c']][:num_units] = args['bldg_type_c_num_units']
  #     building_type_hash[args['bldg_type_c']][:space_types] = get_space_types_from_building_type(args['bldg_type_c'], args['template'], true)
  #   end
  #
  #   # gather data for bldg_type_d
  #   if args['bldg_type_d_fract_bldg_area'] > 0
  #     building_type_hash[args['bldg_type_d']] = {}
  #     building_type_hash[args['bldg_type_d']][:frac_bldg_area] = args['bldg_type_d_fract_bldg_area']
  #     building_type_hash[args['bldg_type_d']][:num_units] = args['bldg_type_d_num_units']
  #     building_type_hash[args['bldg_type_d']][:space_types] = get_space_types_from_building_type(args['bldg_type_d'], args['template'], true)
  #   end
  #
  #   # creating space types for requested building types
  #   building_type_hash.each do |building_type, building_type_hash|
  #     runner.registerInfo("Creating Space Types for #{building_type}.")
  #
  #     # mapping building_type name is needed for a few methods
  #     building_type = standard.model_get_lookup_name(building_type)
  #
  #     # create space_type_map from array
  #     sum_of_ratios = 0.0
  #     building_type_hash[:space_types].each do |space_type_name, hash|
  #       next if hash[:space_type_gen] == false # space types like undeveloped and basement are skipped.
  #
  #       # create space type
  #       space_type = OpenStudio::Model::SpaceType.new(model)
  #       space_type.setStandardsBuildingType(building_type)
  #       space_type.setStandardsSpaceType(space_type_name)
  #       space_type.setName("#{building_type} #{space_type_name}")
  #
  #       # set color
  #       test = standard.space_type_apply_rendering_color(space_type) # this uses openstudio-standards
  #       if !test
  #         runner.registerWarning("Could not find color for #{args['template']} #{space_type.name}")
  #       end
  #
  #       # extend hash to hold new space type object
  #       hash[:space_type] = space_type
  #
  #       # add to sum_of_ratios counter for adjustment multiplier
  #       sum_of_ratios += hash[:ratio]
  #     end
  #
  #     # store multiplier needed to adjsut sum of ratios to equl 1.0
  #     building_type_hash[:ratio_adjustment_multiplier] = 1.0 / sum_of_ratios
  #   end
  #
  #   # calculate length and with of bar
  #   # todo - update slicing to nicely handle aspect ratio less than 1
  #
  #   total_bldg_floor_area_si = OpenStudio.convert(args['total_bldg_floor_area'], 'ft^2', 'm^2').get
  #   single_floor_area_si = OpenStudio.convert(args['single_floor_area'], 'ft^2', 'm^2').get
  #
  #   num_stories = args['num_stories_below_grade'] + args['num_stories_above_grade']
  #
  #   # handle user-assigned single floor plate size condition
  #   if args['single_floor_area'] > 0.0
  #     footprint_si = single_floor_area_si
  #     total_bldg_floor_area_si = single_floor_area_si * num_stories.to_f
  #     runner.registerWarning('User-defined single floor area was used for calculation of total building floor area')
  #   else
  #     footprint_si = total_bldg_floor_area_si / num_stories.to_f
  #   end
  #   floor_height_si = OpenStudio.convert(args['floor_height'], 'ft', 'm').get
  #   width = Math.sqrt(footprint_si / args['ns_to_ew_ratio'])
  #   length = footprint_si / width
  #
  #   # populate space_types_hash
  #   space_types_hash = {}
  #   building_type_hash.each do |building_type, building_type_hash|
  #     building_type_hash[:space_types].each do |space_type_name, hash|
  #       next if hash[:space_type_gen] == false
  #
  #       space_type = hash[:space_type]
  #       ratio_of_bldg_total = hash[:ratio] * building_type_hash[:ratio_adjustment_multiplier] * building_type_hash[:frac_bldg_area]
  #       final_floor_area = ratio_of_bldg_total * total_bldg_floor_area_si # I think I can just pass ratio but passing in area is cleaner
  #       # only add wwr if 0 used for wwr arg and if space type has wwr as key
  #       space_types_hash[space_type] = { floor_area: final_floor_area, space_type: space_type }
  #       if args['wwr'] == 0 && hash.has_key?(:wwr)
  #         space_types_hash[space_type][:wwr] = hash[:wwr]
  #       end
  #     end
  #   end
  #
  #   # create envelope
  #   # populate bar_hash and create envelope with data from envelope_data_hash and user arguments
  #   bar_hash = {}
  #   bar_hash[:length] = length
  #   bar_hash[:width] = width
  #   bar_hash[:num_stories_below_grade] = args['num_stories_below_grade']
  #   bar_hash[:num_stories_above_grade] = args['num_stories_above_grade']
  #   bar_hash[:floor_height] = floor_height_si
  #   # bar_hash[:center_of_footprint] = OpenStudio::Point3d.new(length* 0.5,width * 0.5,0.0)
  #   bar_hash[:center_of_footprint] = OpenStudio::Point3d.new(0, 0, 0)
  #   bar_hash[:bar_division_method] = args['bar_division_method']
  #   bar_hash[:make_mid_story_surfaces_adiabatic] = args['make_mid_story_surfaces_adiabatic']
  #   bar_hash[:space_types] = space_types_hash
  #   bar_hash[:building_wwr_n] = args['wwr']
  #   bar_hash[:building_wwr_s] = args['wwr']
  #   bar_hash[:building_wwr_e] = args['wwr']
  #   bar_hash[:building_wwr_w] = args['wwr']
  #
  #   # round up non integer stoires to next integer
  #   num_stories_round_up = num_stories.ceil
  #
  #   # party_walls_array to be used by orientation specific or fractional party wall values
  #   party_walls_array = [] # this is an array of arrays, where each entry is effective building story with array of directions
  #
  #   if args['party_wall_stories_north'] + args['party_wall_stories_south'] + args['party_wall_stories_east'] + args['party_wall_stories_west'] > 0
  #
  #     # loop through effective number of stories add orientation specific party walls per user arguments
  #     num_stories_round_up.times do |i|
  #       test_value = i + 1 - bar_hash[:num_stories_below_grade]
  #
  #       array = []
  #       if args['party_wall_stories_north'] >= test_value
  #         array << 'north'
  #       end
  #       if args['party_wall_stories_south'] >= test_value
  #         array << 'south'
  #       end
  #       if args['party_wall_stories_east'] >= test_value
  #         array << 'east'
  #       end
  #       if args['party_wall_stories_west'] >= test_value
  #         array << 'west'
  #       end
  #
  #       # populate party_wall_array for this story
  #       party_walls_array << array
  #     end
  #   end
  #
  #   # calculate party walls if using party_wall_fraction method
  #   if args['party_wall_fraction'] > 0 && !party_walls_array.empty?
  #     runner.registerWarning('Both orientaiton and fractional party wall values arguments were populated, will ignore fractional party wall input')
  #   elsif args['party_wall_fraction'] > 0
  #
  #     # orientation of long and short side of building will vary based on building rotation
  #
  #     # full story ext wall area
  #     typical_length_facade_area = length * floor_height_si
  #     typical_width_facade_area = width * floor_height_si
  #
  #     # top story ext wall area, may be partial story
  #     partial_story_multiplier = (1.0 - args['num_stories_above_grade'].ceil + args['num_stories_above_grade'])
  #     area_multiplier = partial_story_multiplier
  #     edge_multiplier = Math.sqrt(area_multiplier)
  #     top_story_length = length * edge_multiplier
  #     top_story_width = width * edge_multiplier
  #     top_story_length_facade_area = top_story_length * floor_height_si
  #     top_story_width_facade_area = top_story_width * floor_height_si
  #
  #     total_exterior_wall_area = 2 * (length + width) * (args['num_stories_above_grade'].ceil - 1.0) * floor_height_si + 2 * (top_story_length + top_story_width) * floor_height_si
  #     target_party_wall_area = total_exterior_wall_area * args['party_wall_fraction']
  #
  #     width_counter = 0
  #     width_area = 0.0
  #     facade_area = typical_width_facade_area
  #     until (width_area + facade_area >= target_party_wall_area) || (width_counter == args['num_stories_above_grade'].ceil * 2)
  #       # update facade area for top story
  #       if width_counter == args['num_stories_above_grade'].ceil - 1 || width_counter == args['num_stories_above_grade'].ceil * 2 - 1
  #         facade_area = top_story_width_facade_area
  #       else
  #         facade_area = typical_width_facade_area
  #       end
  #
  #       width_counter += 1
  #       width_area += facade_area
  #
  #     end
  #     width_area_remainder = target_party_wall_area - width_area
  #
  #     length_counter = 0
  #     length_area = 0.0
  #     facade_area = typical_length_facade_area
  #     until (length_area + facade_area >= target_party_wall_area) || (length_counter == args['num_stories_above_grade'].ceil * 2)
  #       # update facade area for top story
  #       if length_counter == args['num_stories_above_grade'].ceil - 1 || length_counter == args['num_stories_above_grade'].ceil * 2 - 1
  #         facade_area = top_story_length_facade_area
  #       else
  #         facade_area = typical_length_facade_area
  #       end
  #
  #       length_counter += 1
  #       length_area += facade_area
  #     end
  #     length_area_remainder = target_party_wall_area - length_area
  #
  #     # get rotation and best fit to adjust orientation for fraction party wall
  #     rotation = args['building_rotation'] % 360.0 # should result in value between 0 and 360
  #     card_dir_array = [0.0, 90.0, 180.0, 270.0, 360.0]
  #     # reverse array to properly handle 45, 135, 225, and 315
  #     best_fit = card_dir_array.reverse.min_by { |x| (x.to_f - rotation).abs }
  #
  #     if ![90.0, 270.0].include? best_fit
  #       width_card_dir = ['east', 'west']
  #       length_card_dir = ['north', 'south']
  #     else # if rotation is closest to 90 or 270 then reverse which orientation is used for length and width
  #       width_card_dir = ['north', 'south']
  #       length_card_dir = ['east', 'west']
  #     end
  #
  #     # if dont' find enough on short sides
  #     if width_area_remainder <= typical_length_facade_area
  #
  #       num_stories_round_up.times do |i|
  #         if i + 1 <= args['num_stories_below_grade']
  #           party_walls_array << []
  #           next
  #         end
  #         if i + 1 - args['num_stories_below_grade'] <= width_counter
  #           if i + 1 - args['num_stories_below_grade'] <= width_counter - args['num_stories_above_grade']
  #             party_walls_array << width_card_dir
  #           else
  #             party_walls_array << [width_card_dir.first]
  #           end
  #         else
  #           party_walls_array << []
  #         end
  #       end
  #
  #     else # use long sides instead
  #
  #       num_stories_round_up.times do |i|
  #         if i + 1 <= args['num_stories_below_grade']
  #           party_walls_array << []
  #           next
  #         end
  #         if i + 1 - args['num_stories_below_grade'] <= length_counter
  #           if i + 1 - args['num_stories_below_grade'] <= length_counter - args['num_stories_above_grade']
  #             party_walls_array << length_card_dir
  #           else
  #             party_walls_array << [length_card_dir.first]
  #           end
  #         else
  #           party_walls_array << []
  #         end
  #       end
  #     end
  #     # TODO: - currently won't go past making two opposing sets of walls party walls. Info and registerValue are after create_bar in measure.rb
  #   end
  #
  #   # populate bar hash with story information
  #   bar_hash[:stories] = {}
  #   num_stories_round_up.times do |i|
  #     if party_walls_array.empty?
  #       party_walls = []
  #     else
  #       party_walls = party_walls_array[i]
  #     end
  #
  #     # add below_partial_story
  #     if num_stories.ceil > num_stories && i == num_stories_round_up - 2
  #       below_partial_story = true
  #     else
  #       below_partial_story = false
  #     end
  #
  #     # bottom_story_ground_exposed_floor and top_story_exterior_exposed_roof already setup as bool
  #
  #     bar_hash[:stories]["key #{i}"] = { story_party_walls: party_walls, story_min_multiplier: 1, story_included_in_building_area: true, below_partial_story: below_partial_story, bottom_story_ground_exposed_floor: args['bottom_story_ground_exposed_floor'], top_story_exterior_exposed_roof: args['top_story_exterior_exposed_roof'] }
  #   end
  #
  #   # remove non-resource objects not removed by removing the building
  #   remove_non_resource_objects(runner, model)
  #
  #   # rename building to infer template in downstream measure
  #   name_array = [args['template'], args['bldg_type_a']]
  #   if args['bldg_type_b_fract_bldg_area'] > 0 then name_array << args['bldg_type_b'] end
  #   if args['bldg_type_c_fract_bldg_area'] > 0 then name_array << args['bldg_type_c'] end
  #   if args['bldg_type_d_fract_bldg_area'] > 0 then name_array << args['bldg_type_d'] end
  #   model.getBuilding.setName(name_array.join('|').to_s)
  #
  #   # store expected floor areas to check after bar made
  #   target_areas = {}
  #   bar_hash[:space_types].each do |k, v|
  #     target_areas[k] = v[:floor_area]
  #   end
  #
  #   # create bar
  #   create_bar(runner, model, bar_hash, args['story_multiplier'])
  #
  #   # check expected floor areas against actual
  #   model.getSpaceTypes.sort.each do |space_type|
  #     next if !target_areas.key? space_type
  #
  #     # convert to IP
  #     actual_ip = OpenStudio.convert(space_type.floorArea, 'm^2', 'ft^2').get
  #     target_ip = OpenStudio.convert(target_areas[space_type], 'm^2', 'ft^2').get
  #
  #     if (space_type.floorArea - target_areas[space_type]).abs >= 1.0
  #
  #       if !args['bar_division_method'].include? 'Single Space Type'
  #         runner.registerError("#{space_type.name} doesn't have the expected floor area (actual #{OpenStudio.toNeatString(actual_ip, 0, true)} ft^2, target #{OpenStudio.toNeatString(target_ip, 0, true)} ft^2)")
  #         return false
  #       else
  #         # will see this if use Single Space type division method on multi-use building or single building type without whole building space type
  #         runner.registerWarning("#{space_type.name} doesn't have the expected floor area (actual #{OpenStudio.toNeatString(actual_ip, 0, true)} ft^2, target #{OpenStudio.toNeatString(target_ip, 0, true)} ft^2)")
  #       end
  #
  #     end
  #   end
  #
  #   # check party wall fraction by looping through surfaces.
  #   actual_ext_wall_area = model.getBuilding.exteriorWallArea
  #   actual_party_wall_area = 0.0
  #   model.getSurfaces.each do |surface|
  #     next if surface.outsideBoundaryCondition != 'Adiabatic'
  #     next if surface.surfaceType != 'Wall'
  #     actual_party_wall_area += surface.grossArea * surface.space.get.multiplier
  #   end
  #   actual_party_wall_fraction = actual_party_wall_area / (actual_party_wall_area + actual_ext_wall_area)
  #   runner.registerInfo("Target party wall fraction is #{args['party_wall_fraction']}. Realized fraction is #{actual_party_wall_fraction.round(2)}")
  #   runner.registerValue('party_wall_fraction_actual', actual_party_wall_fraction)
  #
  #   # test for excessive exterior roof area (indication of problem with intersection and or surface matching)
  #   ext_roof_area = model.getBuilding.exteriorSurfaceArea - model.getBuilding.exteriorWallArea
  #   expected_roof_area = args['total_bldg_floor_area'] / (args['num_stories_above_grade'] + args['num_stories_below_grade']).to_f
  #   if ext_roof_area > expected_roof_area && single_floor_area_si == 0.0 # only test if using whole-building area input
  #     runner.registerError('Roof area larger than expected, may indicate problem with inter-floor surface intersection or matching.')
  #     return false
  #   end
  #
  #   # Add the neighboring building shading
  #   neighbor_height_north_m = OpenStudio.convert(args['neighbor_height_north'], 'ft', 'm').get
  #   neighbor_height_south_m = OpenStudio.convert(args['neighbor_height_south'], 'ft', 'm').get
  #   neighbor_height_east_m = OpenStudio.convert(args['neighbor_height_east'], 'ft', 'm').get
  #   neighbor_height_west_m = OpenStudio.convert(args['neighbor_height_west'], 'ft', 'm').get
  #
  #   neighbor_offset_north_m = OpenStudio.convert(args['neighbor_offset_north'], 'ft', 'm').get
  #   neighbor_offset_south_m = OpenStudio.convert(args['neighbor_offset_south'], 'ft', 'm').get
  #   neighbor_offset_east_m = OpenStudio.convert(args['neighbor_offset_east'], 'ft', 'm').get
  #   neighbor_offset_west_m = OpenStudio.convert(args['neighbor_offset_west'], 'ft', 'm').get
  #
  #   # Get the building rotation and reset the rotation to 0 temporarily
  #   initial_rotation = model.getBuilding.northAxis
  #   model.getBuilding.setNorthAxis(0)
  #
  #   # Get the bounding box for the entire building
  #   bldg_bounding_box = OpenStudio::BoundingBox.new
  #   model.getSpaces.sort.each do |space|
  #     space_bounding_box_corners = space.buildingTransformation * space.boundingBox.corners
  #     bldg_bounding_box.addPoints(space_bounding_box_corners)
  #   end
  #
  #   # Ensure that the building bounding box is not empty
  #   if bldg_bounding_box.isEmpty
  #     runner.registerError("Bounding box for the model is empty: no spaces were found, cannot add neighboring buildings.")
  #     return false
  #   end
  #
  #   # Get the dimensions of the bounding box in cardinal directions
  #   # north is max y, south is min y
  #   building_extent_north_m = bldg_bounding_box.maxY.get
  #   building_extent_south_m = bldg_bounding_box.minY.get
  #
  #   # east is max x, west is min x
  #   building_extent_east_m = bldg_bounding_box.maxX.get
  #   building_extent_west_m = bldg_bounding_box.minX.get
  #
  #   # north is max y, south is min y
  #   neighbor_location_north_m = building_extent_north_m + neighbor_offset_north_m
  #   neighbor_location_south_m = building_extent_south_m - neighbor_offset_south_m
  #
  #   # east is max x, west is min x
  #   neighbor_location_east_m = building_extent_east_m + neighbor_offset_east_m
  #   neighbor_location_west_m = building_extent_west_m - neighbor_offset_west_m
  #
  #   # up is max z, down is min z
  #   building_extent_up_m = bldg_bounding_box.maxZ.get
  #
  #   # Calculate the neighbor heights if the "Relative" method is selected
  #   # Negative number means neighbors are taller than this building
  #   # Positive number means neighbors are shorter than this building
  #   if args['neighbor_height_method'] == 'Relative'
  #     building_height_relative_to_neighbors_m = OpenStudio.convert(args['building_height_relative_to_neighbors'], 'ft', 'm').get
  #     neighbor_height_north_m = building_extent_up_m - building_height_relative_to_neighbors_m
  #     neighbor_height_south_m = building_extent_up_m - building_height_relative_to_neighbors_m
  #     neighbor_height_east_m = building_extent_up_m - building_height_relative_to_neighbors_m
  #     neighbor_height_west_m = building_extent_up_m - building_height_relative_to_neighbors_m
  #   end
  #
  #   # Only go through the process if at least one neighboring building is requested and is taller than zero
  #   if [neighbor_height_north_m, neighbor_height_south_m, neighbor_height_east_m, neighbor_height_west_m].max > 0
  #     # Make shading surfaces
  #     shade_group = OpenStudio::Model::ShadingSurfaceGroup.new(model)
  #
  #     # North
  #     if neighbor_height_north_m > 0 && neighbor_offset_north_m > 0
  #       north_neighbor_vertices = []
  #       north_neighbor_vertices << OpenStudio::Point3d.new(building_extent_west_m, neighbor_location_north_m, 0)
  #       north_neighbor_vertices << OpenStudio::Point3d.new(building_extent_west_m, neighbor_location_north_m, neighbor_height_north_m)
  #       north_neighbor_vertices << OpenStudio::Point3d.new(building_extent_east_m, neighbor_location_north_m, neighbor_height_north_m)
  #       north_neighbor_vertices << OpenStudio::Point3d.new(building_extent_east_m, neighbor_location_north_m, 0)
  #       north_shade = OpenStudio::Model::ShadingSurface.new(north_neighbor_vertices, model)
  #       north_shade.setName('North Neighbor Shade')
  #       north_shade.setShadingSurfaceGroup(shade_group)
  #       runner.registerInfo("Added north neighboring building #{OpenStudio.convert(neighbor_height_north_m, 'm', 'ft').get.round} ft tall, #{args['neighbor_offset_north'].round} ft away.")
  #     end
  #
  #     # South
  #     if neighbor_height_south_m > 0 && neighbor_offset_south_m > 0
  #       south_neighbor_vertices = []
  #       south_neighbor_vertices << OpenStudio::Point3d.new(building_extent_east_m, neighbor_location_south_m, 0)
  #       south_neighbor_vertices << OpenStudio::Point3d.new(building_extent_east_m, neighbor_location_south_m, neighbor_height_south_m)
  #       south_neighbor_vertices << OpenStudio::Point3d.new(building_extent_west_m, neighbor_location_south_m, neighbor_height_south_m)
  #       south_neighbor_vertices << OpenStudio::Point3d.new(building_extent_west_m, neighbor_location_south_m, 0)
  #       south_shade = OpenStudio::Model::ShadingSurface.new(south_neighbor_vertices, model)
  #       south_shade.setName('South Neighbor Shade')
  #       south_shade.setShadingSurfaceGroup(shade_group)
  #       runner.registerInfo("Added south neighboring building #{OpenStudio.convert(neighbor_height_south_m, 'm', 'ft').get.round} ft tall, #{args['neighbor_offset_south'].round} ft away.")
  #     end
  #
  #     # East
  #     if neighbor_height_east_m > 0 && neighbor_offset_east_m > 0
  #       east_neighbor_vertices = []
  #       east_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_east_m, building_extent_north_m, 0)
  #       east_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_east_m, building_extent_north_m, neighbor_height_east_m)
  #       east_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_east_m, building_extent_south_m, neighbor_height_east_m)
  #       east_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_east_m, building_extent_south_m, 0)
  #       east_shade = OpenStudio::Model::ShadingSurface.new(east_neighbor_vertices, model)
  #       east_shade.setName('East Neighbor Shade')
  #       east_shade.setShadingSurfaceGroup(shade_group)
  #       runner.registerInfo("Added east neighboring building #{OpenStudio.convert(neighbor_height_east_m, 'm', 'ft').get.round} ft tall, #{args['neighbor_offset_east'].round} ft away.")
  #     end
  #
  #     # West
  #     if neighbor_height_west_m > 0 && neighbor_offset_west_m > 0
  #       west_neighbor_vertices = []
  #       west_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_west_m, building_extent_south_m, 0)
  #       west_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_west_m, building_extent_south_m, neighbor_height_west_m)
  #       west_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_west_m, building_extent_north_m, neighbor_height_west_m)
  #       west_neighbor_vertices << OpenStudio::Point3d.new(neighbor_location_west_m, building_extent_north_m, 0)
  #       west_shade = OpenStudio::Model::ShadingSurface.new(west_neighbor_vertices, model)
  #       west_shade.setName('West Neighbor Shade')
  #       west_shade.setShadingSurfaceGroup(shade_group)
  #       runner.registerInfo("Added west neighboring building #{OpenStudio.convert(neighbor_height_west_m, 'm', 'ft').get.round} ft tall, #{args['neighbor_offset_west'].round} ft away.")
  #     end
  #   end
  #
  #   # Reset the building to the initial rotation
  #   model.getBuilding.setNorthAxis(initial_rotation)
  #
  #   # report final condition of model
  #   runner.registerFinalCondition("The building finished with #{model.getSpaces.size} spaces.")
  #
  #   return true
  # end
  #
  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # method run from os_lib_model_generation.rb
    result = bar_from_building_type_ratios(model, runner, user_arguments)

    if result == false
      return false
    else
      return true
    end
  end
end

# register the measure to be used by the application
CreateBarFromBuildingTypeRatios.new.registerWithApplication
