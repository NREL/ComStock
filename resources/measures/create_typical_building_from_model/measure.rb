# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class CreateTypicalBuildingFromModel < OpenStudio::Measure::ModelMeasure
  require 'openstudio-standards'

  # require all .rb files in resources folder
  Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }

  # resource file modules
  include OsLib_HelperMethods
  include OsLib_ModelGeneration

  # human readable name
  def name
    return 'Create Typical Building from Model'
  end

  # human readable description
  def description
    return 'Takes a model with space and stub space types, and assigns constructions, schedules, internal loads, hvac, and other loads such as exterior lights and service water heating. The end result is somewhat like a custom protptye model with user geometry, but it may use different HVAC systems.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Initially this was intended for stub space types, but it is possible that it will be run on models tha talready have internal loads, schedules, or constructions that should be preserved. Set it up to support addition at later date of bool args to skip specific types of model elements.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # see if building name contains any template values
    default_string = '90.1-2010'
    get_templates.each do |template_string|
      if model.getBuilding.name.to_s.include?(template_string)
        default_string = template_string
        next
      end
    end

    # Make argument for template
    template = OpenStudio::Measure::OSArgument.makeChoiceArgument('template', get_templates, true)
    template.setDisplayName('Target Standard')
    template.setDefaultValue(default_string)
    args << template

    # Make argument for system type
    hvac_chs = OpenStudio::StringVector.new
    hvac_chs << 'Inferred'
    hvac_chs << 'Baseboard central air source heat pump'
    hvac_chs << 'Baseboard district hot water'
    hvac_chs << 'Baseboard district hot water heat'
    hvac_chs << 'Baseboard district hot water heat with direct evap coolers'
    hvac_chs << 'Baseboard electric'
    hvac_chs << 'Baseboard electric heat'
    hvac_chs << 'Baseboard electric heat with direct evap coolers'
    hvac_chs << 'Baseboard gas boiler'
    hvac_chs << 'Baseboard hot water heat'
    hvac_chs << 'Baseboard hot water heat with direct evap coolers'
    hvac_chs << 'Direct evap coolers'
    hvac_chs << 'Direct evap coolers with baseboard central air source heat pump'
    hvac_chs << 'Direct evap coolers with baseboard district hot water'
    hvac_chs << 'Direct evap coolers with baseboard electric'
    hvac_chs << 'Direct evap coolers with baseboard gas boiler'
    hvac_chs << 'Direct evap coolers with forced air furnace'
    hvac_chs << 'Direct evap coolers with gas unit heaters'
    hvac_chs << 'Direct evap coolers with no heat'
    hvac_chs << 'Direct evap coolers with unit heaters'
    hvac_chs << 'DOAS with fan coil air-cooled chiller and boiler'
    hvac_chs << 'DOAS with fan coil air-cooled chiller and central air source heat pump'
    hvac_chs << 'DOAS with fan coil air-cooled chiller with baseboard electric'
    hvac_chs << 'DOAS with fan coil air-cooled chiller with boiler'
    hvac_chs << 'DOAS with fan coil air-cooled chiller with central air source heat pump'
    hvac_chs << 'DOAS with fan coil air-cooled chiller with district hot water'
    hvac_chs << 'DOAS with fan coil air-cooled chiller with gas unit heaters'
    hvac_chs << 'DOAS with fan coil air-cooled chiller with no heat'
    hvac_chs << 'DOAS with fan coil chiller and boiler'
    hvac_chs << 'DOAS with fan coil chiller and central air source heat pump'
    hvac_chs << 'DOAS with fan coil chiller with baseboard electric'
    hvac_chs << 'DOAS with fan coil chiller with boiler'
    hvac_chs << 'DOAS with fan coil chiller with central air source heat pump'
    hvac_chs << 'DOAS with fan coil chiller with district hot water'
    hvac_chs << 'DOAS with fan coil chiller with gas unit heaters'
    hvac_chs << 'DOAS with fan coil chiller with no heat'
    hvac_chs << 'DOAS with fan coil district chilled water and boiler'
    hvac_chs << 'DOAS with fan coil district chilled water and central air source heat pump'
    hvac_chs << 'DOAS with fan coil district chilled water electric baseboard heat'
    hvac_chs << 'DOAS with fan coil district chilled water unit heaters'
    hvac_chs << 'DOAS with fan coil district chilled water with baseboard electric'
    hvac_chs << 'DOAS with fan coil district chilled water with boiler'
    hvac_chs << 'DOAS with fan coil district chilled water with central air source heat pump'
    hvac_chs << 'DOAS with fan coil district chilled water with district hot water'
    hvac_chs << 'DOAS with fan coil district chilled water with gas unit heaters'
    hvac_chs << 'DOAS with fan coil district chilled water with no heat'
    hvac_chs << 'DOAS with fan coil district hot and chilled water'
    hvac_chs << 'DOAS with fan coil district hot water and air-cooled chiller'
    hvac_chs << 'DOAS with fan coil district hot water and chiller'
    hvac_chs << 'DOAS with VRF'
    hvac_chs << 'DOAS with water source heat pumps cooling tower with boiler'
    hvac_chs << 'DOAS with water source heat pumps district chilled water with district hot water'
    hvac_chs << 'DOAS with water source heat pumps fluid cooler with boiler'
    hvac_chs << 'DOAS with water source heat pumps with ground source heat pump'
    hvac_chs << 'Fan coil air-cooled chiller and boiler'
    hvac_chs << 'Fan coil air-cooled chiller and central air source heat pump'
    hvac_chs << 'Fan coil air-cooled chiller with baseboard electric'
    hvac_chs << 'Fan coil air-cooled chiller with boiler'
    hvac_chs << 'Fan coil air-cooled chiller with central air source heat pump'
    hvac_chs << 'Fan coil air-cooled chiller with district hot water'
    hvac_chs << 'Fan coil air-cooled chiller with gas unit heaters'
    hvac_chs << 'Fan coil air-cooled chiller with no heat'
    hvac_chs << 'Fan coil chiller and boiler'
    hvac_chs << 'Fan coil chiller and central air source heat pump'
    hvac_chs << 'Fan coil chiller with baseboard electric'
    hvac_chs << 'Fan coil chiller with boiler'
    hvac_chs << 'Fan coil chiller with central air source heat pump'
    hvac_chs << 'Fan coil chiller with district hot water'
    hvac_chs << 'Fan coil chiller with gas unit heaters'
    hvac_chs << 'Fan coil chiller with no heat'
    hvac_chs << 'Fan coil district chilled water and boiler'
    hvac_chs << 'Fan coil district chilled water and central air source heat pump'
    hvac_chs << 'Fan coil district chilled water electric baseboard heat'
    hvac_chs << 'Fan coil district chilled water unit heaters'
    hvac_chs << 'Fan coil district chilled water with baseboard electric'
    hvac_chs << 'Fan coil district chilled water with boiler'
    hvac_chs << 'Fan coil district chilled water with central air source heat pump'
    hvac_chs << 'Fan coil district chilled water with district hot water'
    hvac_chs << 'Fan coil district chilled water with gas unit heaters'
    hvac_chs << 'Fan coil district chilled water with no heat'
    hvac_chs << 'Fan coil district hot and chilled water'
    hvac_chs << 'Fan coil district hot water and air-cooled chiller'
    hvac_chs << 'Fan coil district hot water and chiller'
    hvac_chs << 'Forced air furnace'
    hvac_chs << 'Forced air furnace direct evap cooler'
    hvac_chs << 'Forced air furnace district chilled water fan coil'
    hvac_chs << 'Gas unit heaters'
    hvac_chs << 'Ground Source Heat Pumps with DOAS'
    hvac_chs << 'Heat pump heat with direct evap cooler'
    hvac_chs << 'Heat pump heat with no cooling'
    hvac_chs << 'Ideal Air Loads'
    hvac_chs << 'PSZ-AC district chilled water with baseboard district hot water'
    hvac_chs << 'PSZ-AC district chilled water with baseboard electric'
    hvac_chs << 'PSZ-AC district chilled water with baseboard gas boiler'
    hvac_chs << 'PSZ-AC district chilled water with central air source heat pump'
    hvac_chs << 'PSZ-AC district chilled water with district hot water'
    hvac_chs << 'PSZ-AC district chilled water with electric coil'
    hvac_chs << 'PSZ-AC district chilled water with gas boiler'
    hvac_chs << 'PSZ-AC district chilled water with gas coil'
    hvac_chs << 'PSZ-AC district chilled water with gas unit heaters'
    hvac_chs << 'PSZ-AC district chilled water with no heat'
    hvac_chs << 'PSZ-AC with baseboard district hot water'
    hvac_chs << 'PSZ-AC with baseboard electric'
    hvac_chs << 'PSZ-AC with baseboard gas boiler'
    hvac_chs << 'PSZ-AC with central air source heat pump'
    hvac_chs << 'PSZ-AC with central air source heat pump heat'
    hvac_chs << 'PSZ-AC with district hot water'
    hvac_chs << 'PSZ-AC with district hot water heat'
    hvac_chs << 'PSZ-AC with electric baseboard heat'
    hvac_chs << 'PSZ-AC with electric coil'
    hvac_chs << 'PSZ-AC with gas boiler'
    hvac_chs << 'PSZ-AC with gas coil'
    hvac_chs << 'PSZ-AC with gas coil heat'
    hvac_chs << 'PSZ-AC with gas unit heaters'
    hvac_chs << 'PSZ-AC with no heat'
    hvac_chs << 'PSZ-HP'
    hvac_chs << 'PTAC with baseboard district hot water'
    hvac_chs << 'PTAC with baseboard electric'
    hvac_chs << 'PTAC with baseboard gas boiler'
    hvac_chs << 'PTAC with central air source heat pump'
    hvac_chs << 'PTAC with central air source heat pump heat'
    hvac_chs << 'PTAC with district hot water'
    hvac_chs << 'PTAC with district hot water heat'
    hvac_chs << 'PTAC with electric baseboard heat'
    hvac_chs << 'PTAC with electric coil'
    hvac_chs << 'PTAC with gas boiler'
    hvac_chs << 'PTAC with gas coil'
    hvac_chs << 'PTAC with gas coil heat'
    hvac_chs << 'PTAC with gas unit heaters'
    hvac_chs << 'PTAC with hot water heat'
    hvac_chs << 'PTAC with hot water heat with central air source heat pump'
    hvac_chs << 'PTAC with no heat'
    hvac_chs << 'PTHP'
    hvac_chs << 'PVAV with central air source heat pump reheat'
    hvac_chs << 'PVAV with district hot water reheat'
    hvac_chs << 'PVAV with gas boiler reheat'
    hvac_chs << 'PVAV with gas heat with electric reheat'
    hvac_chs << 'PVAV with PFP boxes'
    hvac_chs << 'PVAV with reheat'
    hvac_chs << 'PVAV with reheat with central air source heat pump'
    hvac_chs << 'Residential AC with baseboard central air source heat pump'
    hvac_chs << 'Residential AC with baseboard district hot water'
    hvac_chs << 'Residential AC with baseboard electric'
    hvac_chs << 'Residential AC with baseboard gas boiler'
    hvac_chs << 'Residential AC with electric baseboard heat'
    hvac_chs << 'Residential AC with no heat'
    hvac_chs << 'Residential AC with residential forced air furnace'
    hvac_chs << 'Residential forced air'
    hvac_chs << 'Residential forced air cooling hot water baseboard heat'
    hvac_chs << 'Residential forced air furnace'
    hvac_chs << 'Residential forced air with district hot water'
    hvac_chs << 'Residential heat pump'
    hvac_chs << 'Residential heat pump with no cooling'
    hvac_chs << 'Unit heaters'
    hvac_chs << 'VAV air-cooled chiller with central air source heat pump reheat'
    hvac_chs << 'VAV air-cooled chiller with district hot water reheat'
    hvac_chs << 'VAV air-cooled chiller with gas boiler reheat'
    hvac_chs << 'VAV air-cooled chiller with gas coil reheat'
    hvac_chs << 'VAV air-cooled chiller with no reheat with baseboard electric'
    hvac_chs << 'VAV air-cooled chiller with no reheat with gas unit heaters'
    hvac_chs << 'VAV air-cooled chiller with no reheat with zone heat pump'
    hvac_chs << 'VAV air-cooled chiller with PFP boxes'
    hvac_chs << 'VAV chiller with central air source heat pump reheat'
    hvac_chs << 'VAV chiller with district hot water reheat'
    hvac_chs << 'VAV chiller with gas boiler reheat'
    hvac_chs << 'VAV chiller with gas coil reheat'
    hvac_chs << 'VAV chiller with no reheat with baseboard electric'
    hvac_chs << 'VAV chiller with no reheat with gas unit heaters'
    hvac_chs << 'VAV chiller with no reheat with zone heat pump'
    hvac_chs << 'VAV chiller with PFP boxes'
    hvac_chs << 'VAV cool with zone heat pump heat'
    hvac_chs << 'VAV district chilled water with central air source heat pump reheat'
    hvac_chs << 'VAV district chilled water with district hot water reheat'
    hvac_chs << 'VAV district chilled water with gas boiler reheat'
    hvac_chs << 'VAV district chilled water with gas coil reheat'
    hvac_chs << 'VAV district chilled water with no reheat with baseboard electric'
    hvac_chs << 'VAV district chilled water with no reheat with gas unit heaters'
    hvac_chs << 'VAV district chilled water with no reheat with zone heat pump'
    hvac_chs << 'VAV district chilled water with PFP boxes'
    hvac_chs << 'VAV with electric baseboard heat'
    hvac_chs << 'VAV with gas reheat'
    hvac_chs << 'VAV with PFP boxes'
    hvac_chs << 'VAV with reheat'
    hvac_chs << 'VAV with reheat central air source heat pump'
    hvac_chs << 'VAV with zone unit heaters'
    hvac_chs << 'VRF'
    hvac_chs << 'VRF with DOAS'
    hvac_chs << 'Water source heat pumps cooling tower with boiler'
    hvac_chs << 'Water source heat pumps district chilled water with district hot water'
    hvac_chs << 'Water source heat pumps fluid cooler with boiler'
    hvac_chs << 'Water source heat pumps with ground source heat pump'
    hvac_chs << 'Window AC with baseboard central air source heat pump'
    hvac_chs << 'Window AC with baseboard district hot water'
    hvac_chs << 'Window AC with baseboard electric'
    hvac_chs << 'Window AC with baseboard gas boiler'
    hvac_chs << 'Window AC with district hot water baseboard heat'
    hvac_chs << 'Window AC with electric baseboard heat'
    hvac_chs << 'Window AC with forced air furnace'
    hvac_chs << 'Window AC with hot water baseboard heat'
    hvac_chs << 'Window AC with no heat'
    hvac_chs << 'Window AC with unit heaters'
    system_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('system_type', hvac_chs, true)
    system_type.setDisplayName('HVAC System Type')
    system_type.setDefaultValue('Inferred')
    args << system_type

    # Make argument for HVAC delivery type
    hvac_type_chs = OpenStudio::StringVector.new
    hvac_type_chs << 'Forced Air'
    hvac_type_chs << 'Hydronic'
    hvac_delivery_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('hvac_delivery_type', hvac_type_chs, true)
    hvac_delivery_type.setDisplayName('HVAC System Delivery Type')
    hvac_delivery_type.setDescription('How the HVAC system delivers heating or cooling to the zone.')
    hvac_delivery_type.setDefaultValue('Forced Air')
    args << hvac_delivery_type

    # Make argument for HVAC heating source
    htg_src_chs = OpenStudio::StringVector.new
    htg_src_chs << 'Electricity'
    htg_src_chs << 'NaturalGas'
    htg_src_chs << 'DistrictHeating'
    htg_src_chs << 'DistrictAmbient'
    htg_src = OpenStudio::Measure::OSArgument.makeChoiceArgument('htg_src', htg_src_chs, true)
    htg_src.setDisplayName('HVAC Heating Source')
    htg_src.setDescription('The primary source of heating used by HVAC systems in the model.')
    htg_src.setDefaultValue('NaturalGas')
    args << htg_src

    # Make argument for HVAC cooling source
    clg_src_chs = OpenStudio::StringVector.new
    clg_src_chs << 'Electricity'
    clg_src_chs << 'DistrictCooling'
    clg_src_chs << 'DistrictAmbient'
    clg_src = OpenStudio::Measure::OSArgument.makeChoiceArgument('clg_src', clg_src_chs, true)
    clg_src.setDisplayName('HVAC Cooling Source')
    clg_src.setDescription('The primary source of cooling used by HVAC systems in the model.')
    clg_src.setDefaultValue('Electricity')
    args << clg_src

    swh_src_chs = OpenStudio::StringVector.new
    swh_src_chs << 'Inferred'
    swh_src_chs << 'NaturalGas'
    swh_src_chs << 'Electricity'
    swh_src_chs << 'HeatPump'
    swh_src = OpenStudio::Measure::OSArgument.makeChoiceArgument('swh_src', swh_src_chs, true)
    swh_src.setDisplayName('Service Water Heating Source')
    swh_src.setDescription('The primary source of heating used by SWH systems in the model.')
    swh_src.setDefaultValue('Inferred')
    args << swh_src

    #     # make argument for fuel type (not used yet)
    #     fuel_type_cooking = OpenStudio::Measure::OSArgument::makeChoiceArgument("fuel_type_cooking", fuel_choices,true)
    #     fuel_type_cooking.setDisplayName("Fuel Type for Cooking Loads")
    #     fuel_type_cooking.setDefaultValue("Gas")
    #     args << fuel_type_cooking
    #
    #     # make argument for fuel type (not used yet)
    #     fuel_type_laundry = OpenStudio::Measure::OSArgument::makeChoiceArgument("fuel_type_laundry", fuel_choices,true)
    #     fuel_type_laundry.setDisplayName("Fuel Type for Laundry Dryer Loads")
    #     fuel_type_laundry.setDefaultValue("Electric")
    #     args << fuel_type_laundry

    # Argument used to make ComStock tsv workflow run correctly
    cz_choices = OpenStudio::StringVector.new
    cz_choices << 'Lookup From Model'
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
    climate_zone.setDefaultValue('Lookup From Model')
    args << climate_zone

    # make argument for kitchen makeup
    kitchen_makeup_choices = OpenStudio::StringVector.new
    kitchen_makeup_choices << 'None'
    kitchen_makeup_choices << 'Largest Zone'
    kitchen_makeup_choices << 'Adjacent'
    kitchen_makeup = OpenStudio::Measure::OSArgument.makeChoiceArgument('kitchen_makeup', kitchen_makeup_choices, true)
    kitchen_makeup.setDisplayName('Kitchen Exhaust MakeUp Air Calculation Method')
    kitchen_makeup.setDescription('Determine logic to identify dining or cafe zones to provide makeup air to kitchen exhaust.')
    kitchen_makeup.setDefaultValue('Adjacent')
    args << kitchen_makeup

    # make argument for exterior_lighting_zone
    exterior_lighting_zone_choices = OpenStudio::StringVector.new
    exterior_lighting_zone_choices << '0 - Undeveloped Areas Parks'
    exterior_lighting_zone_choices << '1 - Developed Areas Parks'
    exterior_lighting_zone_choices << '2 - Neighborhood'
    exterior_lighting_zone_choices << '3 - All Other Areas'
    exterior_lighting_zone_choices << '4 - High Activity'
    exterior_lighting_zone = OpenStudio::Measure::OSArgument.makeChoiceArgument('exterior_lighting_zone', exterior_lighting_zone_choices, true)
    exterior_lighting_zone.setDisplayName('Exterior Lighting Zone')
    exterior_lighting_zone.setDescription('Identify the Exterior Lighitng Zone for the Building Site.')
    exterior_lighting_zone.setDefaultValue('3 - All Other Areas')
    args << exterior_lighting_zone

    # make an argument for add_constructions
    add_constructions = OpenStudio::Measure::OSArgument.makeBoolArgument('add_constructions', true)
    add_constructions.setDisplayName('Add Constructions to Model')
    add_constructions.setDescription('Construction Set will be appied to entire building')
    add_constructions.setDefaultValue(true)
    args << add_constructions

    # make an argument for add_space_type_loads
    add_space_type_loads = OpenStudio::Measure::OSArgument.makeBoolArgument('add_space_type_loads', true)
    add_space_type_loads.setDisplayName('Add Space Type Loads to Model')
    add_space_type_loads.setDescription('Populate existing space types in model with internal loads.')
    add_space_type_loads.setDefaultValue(true)
    args << add_space_type_loads

    # make an argument for add_elevators
    add_elevators = OpenStudio::Measure::OSArgument.makeBoolArgument('add_elevators', true)
    add_elevators.setDisplayName('Add Elevators to Model')
    add_elevators.setDescription('Elevators will be add directly to space in model vs. being applied to a space type.')
    add_elevators.setDefaultValue(true)
    args << add_elevators

    # make an argument for add_exterior_lights
    add_exterior_lights = OpenStudio::Measure::OSArgument.makeBoolArgument('add_exterior_lights', true)
    add_exterior_lights.setDisplayName('Add Exterior Lights to Model')
    add_exterior_lights.setDescription('Multiple exterior lights objects will be added for different classes of lighting such as parking and facade.')
    add_exterior_lights.setDefaultValue(true)
    args << add_exterior_lights

    # make an argument for onsite_parking_fraction
    onsite_parking_fraction = OpenStudio::Measure::OSArgument.makeDoubleArgument('onsite_parking_fraction', true)
    onsite_parking_fraction.setDisplayName('Onsite Parking Fraction')
    onsite_parking_fraction.setDescription('If set to 0 no exterior lighting for parking will be added')
    onsite_parking_fraction.setDefaultValue(1.0)
    args << onsite_parking_fraction

    # make an argument for add_exhaust
    add_exhaust = OpenStudio::Measure::OSArgument.makeBoolArgument('add_exhaust', true)
    add_exhaust.setDisplayName('Add Exhaust Fans to Model')
    add_exhaust.setDescription('Depending upon building type exhaust fans can be in kitchens, restrooms or other space types')
    add_exhaust.setDefaultValue(true)
    args << add_exhaust

    # make an argument for add_swh
    add_swh = OpenStudio::Measure::OSArgument.makeBoolArgument('add_swh', true)
    add_swh.setDisplayName('Add Service Water Heating to Model')
    add_swh.setDescription('This will add both the supply and demand side of service water heating.')
    add_swh.setDefaultValue(true)
    args << add_swh

    # make an argument for add_thermostat
    add_thermostat = OpenStudio::Measure::OSArgument.makeBoolArgument('add_thermostat', true)
    add_thermostat.setDisplayName('Add Thermostats')
    add_thermostat.setDescription('Add Thermost to model based on Space Type Standards information of spaces assigned to thermal zones.')
    add_thermostat.setDefaultValue(true)
    args << add_thermostat

    # make an argument for add_hvac
    add_hvac = OpenStudio::Measure::OSArgument.makeBoolArgument('add_hvac', true)
    add_hvac.setDisplayName('Add HVAC System to Model')
    add_hvac.setDescription('Add HVAC System and thermostats to model')
    add_hvac.setDefaultValue(true)
    args << add_hvac

    # make an argument for add_internal_mass
    add_internal_mass = OpenStudio::Measure::OSArgument.makeBoolArgument('add_internal_mass', true)
    add_internal_mass.setDisplayName('Add Internal Mass to Model')
    add_internal_mass.setDescription('Adds internal mass to each space.')
    add_internal_mass.setDefaultValue(true)
    args << add_internal_mass

    # make an argument for add_refrigeration
    add_refrigeration = OpenStudio::Measure::OSArgument.makeBoolArgument('add_refrigeration', true)
    add_refrigeration.setDisplayName('Add Refrigeration to Model')
    add_refrigeration.setDescription('Add refrigeration cases and walkins model')
    add_refrigeration.setDefaultValue(true)
    args << add_refrigeration

    # modify weekday hours of operation
    modify_wkdy_op_hrs = OpenStudio::Measure::OSArgument.makeBoolArgument('modify_wkdy_op_hrs', true)
    modify_wkdy_op_hrs.setDisplayName('Modify weekday hours of operation')
    modify_wkdy_op_hrs.setDescription('Modify the weekday hours of operation in the model.')
    modify_wkdy_op_hrs.setDefaultValue(false)
    args << modify_wkdy_op_hrs

    # weekday hours of operation start time
    wkdy_op_hrs_start_time = OpenStudio::Measure::OSArgument.makeStringArgument('wkdy_op_hrs_start_time', true)
    wkdy_op_hrs_start_time.setDisplayName('Weekday Operating Hours Start Time')
    wkdy_op_hrs_start_time.setDescription('Weekday operating hours start time in 08:30 format, using 24-hr clock.  Only used if Modify weekday hours of operation is true.')
    wkdy_op_hrs_start_time.setDefaultValue('08:00')
    args << wkdy_op_hrs_start_time

    # weekday hours of operation duration
    wkdy_op_hrs_duration = OpenStudio::Measure::OSArgument.makeStringArgument('wkdy_op_hrs_duration', true)
    wkdy_op_hrs_duration.setDisplayName('Weekday Operating Hours Duration')
    wkdy_op_hrs_duration.setDescription('Length of weekday operating hours in 08:30 format, up to 24:00.  Only used if Modify weekday hours of operation is true.')
    wkdy_op_hrs_duration.setDefaultValue('08:00')
    args << wkdy_op_hrs_duration

    # modify weekend hours of operation
    modify_wknd_op_hrs = OpenStudio::Measure::OSArgument.makeBoolArgument('modify_wknd_op_hrs', true)
    modify_wknd_op_hrs.setDisplayName('Modify weekend hours of operation')
    modify_wknd_op_hrs.setDescription('Modify the weekend hours of operation in the model.')
    modify_wknd_op_hrs.setDefaultValue(false)
    args << modify_wknd_op_hrs

    # weekend hours of operation start time
    wknd_op_hrs_start_time = OpenStudio::Measure::OSArgument.makeStringArgument('wknd_op_hrs_start_time', true)
    wknd_op_hrs_start_time.setDisplayName('Weekend Operating Hours Start Time')
    wknd_op_hrs_start_time.setDescription('Weekend operating hours start time in 08:30 format, using 24-hr clock.  Only used if Modify weekend hours of operation is true.')
    wknd_op_hrs_start_time.setDefaultValue('08:00')
    args << wknd_op_hrs_start_time

    # weekend hours of operation duration
    wknd_op_hrs_duration = OpenStudio::Measure::OSArgument.makeStringArgument('wknd_op_hrs_duration', true)
    wknd_op_hrs_duration.setDisplayName('Weekend Operating Hours Duration')
    wknd_op_hrs_duration.setDescription('Length of weekend operating hours in 08:30 format, up to 24:00.  Only used if Modify weekend hours of operation is true.')
    wknd_op_hrs_duration.setDefaultValue('08:00')
    args << wknd_op_hrs_duration

    # make an argument for unmet_hours_tolerance
    unmet_hours_tolerance = OpenStudio::Measure::OSArgument.makeDoubleArgument('unmet_hours_tolerance', true)
    unmet_hours_tolerance.setDisplayName('Unmet Hours Tolerance')
    unmet_hours_tolerance.setDescription('Set the thermostat setpoint tolerance for unmet hours in degrees Rankine')
    unmet_hours_tolerance.setDefaultValue(1.0)
    args << unmet_hours_tolerance

    # make an argument for remove_objects
    remove_objects = OpenStudio::Measure::OSArgument.makeBoolArgument('remove_objects', true)
    remove_objects.setDisplayName('Clean Model of non-geometry objects')
    remove_objects.setDescription('Only removes objects of type that are selected to be added.')
    remove_objects.setDefaultValue(true)
    args << remove_objects

    # make an argument for use_upstream_args
    use_upstream_args = OpenStudio::Measure::OSArgument.makeBoolArgument('use_upstream_args', true)
    use_upstream_args.setDisplayName('Use Upstream Argument Values')
    use_upstream_args.setDescription('When true this will look for arguments or registerValues in upstream measures that match arguments from this measure, and will use the value from the upstream measure in place of what is entered for this measure.')
    use_upstream_args.setDefaultValue(true)
    args << use_upstream_args

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments(model))
    if !args then return false end

    # lookup and replace argument values from upstream measures
    if args['use_upstream_args'] == true
      args.each do |arg,value|
        next if arg == 'use_upstream_args' # this argument should not be changed
        value_from_osw = OsLib_HelperMethods.check_upstream_measure_for_arg(runner, arg)
        if !value_from_osw.empty?
          runner.registerInfo("Replacing argument named #{arg} from current measure with a value of #{value_from_osw[:value]} from #{value_from_osw[:measure_name]}.")
          new_val = value_from_osw[:value]
          # todo - make code to handle non strings more robust. check_upstream_measure_for_arg coudl pass bakc the argument type
          if arg == 'total_bldg_floor_area'
            args[arg] = new_val.to_f
          elsif arg == 'num_stories_above_grade'
            args[arg] = new_val.to_f
          elsif arg == 'zipcode'
            args[arg] = new_val.to_i
          else
            args[arg] = new_val
          end
        end
      end
    end

    # validate fraction parking
    fraction = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => 1.0, 'min_eq_bool' => true, 'max_eq_bool' => true, 'arg_array' => ['onsite_parking_fraction'])
    if !fraction then return false end

    # validate unmet hours tolerance
    unmet_hours_tolerance_valid = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => 5.0, 'min_eq_bool' => true, 'max_eq_bool' => true, 'arg_array' => ['unmet_hours_tolerance'])
    if !unmet_hours_tolerance_valid then return false end

    # validate weekday hours of operation
    wkdy_op_hrs_start_time_hr = nil
    wkdy_op_hrs_start_time_min = nil
    wkdy_op_hrs_duration_hr = nil
    wkdy_op_hrs_duration_min = nil
    if args['modify_wkdy_op_hrs']
      # weekday start time hr
      wkdy_op_hrs_start_time_hr = args['wkdy_op_hrs_start_time'].split(':')[0].to_i
      if wkdy_op_hrs_start_time_hr < 0 || wkdy_op_hrs_start_time_hr > 24
        runner.registerError("Weekday operating hours start time hrs must be between 0 and 24.  #{args['wkdy_op_hrs_start_time']} was entered.")
        return false
      end

      # weekday start time min
      wkdy_op_hrs_start_time_min = args['wkdy_op_hrs_start_time'].split(':')[1].to_i
      if wkdy_op_hrs_start_time_min < 0 || wkdy_op_hrs_start_time_min > 59
        runner.registerError("Weekday operating hours start time mins must be between 0 and 59.  #{args['wkdy_op_hrs_start_time']} was entered.")
        return false
      end

      # weekday duration hr
      wkdy_op_hrs_duration_hr = args['wkdy_op_hrs_duration'].split(':')[0].to_i
      if wkdy_op_hrs_duration_hr < 0 || wkdy_op_hrs_duration_hr > 24
        runner.registerError("Weekday operating hours duration hrs must be between 0 and 24.  #{args['wkdy_op_hrs_duration']} was entered.")
        return false
      end

      # weekday duration min
      wkdy_op_hrs_duration_min = args['wkdy_op_hrs_duration'].split(':')[1].to_i
      if wkdy_op_hrs_duration_min < 0 || wkdy_op_hrs_duration_min > 59
        runner.registerError("Weekday operating hours duration mins must be between 0 and 59.  #{args['wkdy_op_hrs_duration']} was entered.")
        return false
      end

      # check that weekday start time plus duration does not exceed 24 hrs
      if (wkdy_op_hrs_start_time_hr + wkdy_op_hrs_duration_hr + (wkdy_op_hrs_start_time_min + wkdy_op_hrs_duration_min)/60.0) > 24.0
        runner.registerInfo("Weekday start time of #{args['wkdy_op_hrs_start']} plus duration of #{args['wkdy_op_hrs_duration']} is more than 24 hrs, hours of operation overlap midnight.")
      end
    end

    # validate weekend hours of operation
    wknd_op_hrs_start_time_hr = nil
    wknd_op_hrs_start_time_min = nil
    wknd_op_hrs_duration_hr = nil
    wknd_op_hrs_duration_min = nil
    if args['modify_wknd_op_hrs']
      # weekend start time hr
      wknd_op_hrs_start_time_hr = args['wknd_op_hrs_start_time'].split(':')[0].to_i
      if wknd_op_hrs_start_time_hr < 0 || wknd_op_hrs_start_time_hr > 24
        runner.registerError("Weekend operating hours start time hrs must be between 0 and 24.  #{args['wknd_op_hrs_start_time_change']} was entered.")
        return false
      end

      # weekend start time min
      wknd_op_hrs_start_time_min = args['wknd_op_hrs_start_time'].split(':')[1].to_i
      if wknd_op_hrs_start_time_min < 0 || wknd_op_hrs_start_time_min > 59
        runner.registerError("Weekend operating hours start time mins must be between 0 and 59.  #{args['wknd_op_hrs_start_time_change']} was entered.")
        return false
      end

      # weekend duration hr
      wknd_op_hrs_duration_hr = args['wknd_op_hrs_duration'].split(':')[0].to_i
      if wknd_op_hrs_duration_hr < 0 || wknd_op_hrs_duration_hr > 24
        runner.registerError("Weekend operating hours duration hrs must be between 0 and 24.  #{args['wknd_op_hrs_duration']} was entered.")
        return false
      end

      # weekend duration min
      wknd_op_hrs_duration_min = args['wknd_op_hrs_duration'].split(':')[1].to_i
      if wknd_op_hrs_duration_min < 0 || wknd_op_hrs_duration_min > 59
        runner.registerError("Weekend operating hours duration min smust be between 0 and 59.  #{args['wknd_op_hrs_duration']} was entered.")
        return false
      end

      # check that weekend start time plus duration does not exceed 24 hrs
      if (wknd_op_hrs_start_time_hr + wknd_op_hrs_duration_hr + (wknd_op_hrs_start_time_min + wknd_op_hrs_duration_min)/60.0) > 24.0
        runner.registerInfo("Weekend start time of #{args['wknd_op_hrs_start']} plus duration of #{args['wknd_op_hrs_duration']} is more than 24 hrs, hours of operation overlap midnight.")
      end
    end

    # report initial condition of model
    initial_objects = model.getModelObjects.size
    runner.registerInitialCondition("The building started with #{initial_objects} objects.")

    # open channel to log messages
    reset_log

    # Make the standard applier
    standard = Standard.build((args['template']).to_s)

    # add internal loads to space types
    if args['add_space_type_loads']

      # remove internal loads
      if args['remove_objects']
        model.getSpaceLoads.each do |instance|
          next if instance.name.to_s.include?('Elevator') # most prototype building types model exterior elevators with name Elevator
          next if instance.to_InternalMass.is_initialized
          next if instance.to_WaterUseEquipment.is_initialized
          instance.remove
        end
        model.getDesignSpecificationOutdoorAirs.each(&:remove)
        model.getDefaultScheduleSets.each(&:remove)
      end

      model.getSpaceTypes.each do |space_type|
        # Don't add infiltration here; will be added later in the script
        test = standard.space_type_apply_internal_loads(space_type, true, true, true, true, true, false)
        if test == false
          runner.registerWarning("Could not add loads for #{space_type.name}. Not expected for #{args['template']}")
          next
        end

        # apply internal load schedules
        # the last bool test it to make thermostat schedules. They are now added in HVAC section instead of here
        standard.space_type_apply_internal_load_schedules(space_type, true, true, true, true, true, true, false)

        # extend space type name to include the args['template']. Consider this as well for load defs
        space_type.setName("#{space_type.name} - #{args['template']}")
        runner.registerInfo("Adding loads to space type named #{space_type.name}")
      end

      # warn if spaces in model without space type
      spaces_without_space_types = []
      model.getSpaces.each do |space|
        next if space.spaceType.is_initialized
        spaces_without_space_types << space
      end
      if !spaces_without_space_types.empty?
        runner.registerWarning("#{spaces_without_space_types.size} spaces do not have space types assigned, and wont' receive internal loads from standards space type lookups.")
      end
    end

    # identify primary building type (used for construction, and ideally HVAC as well)
    building_types = {}
    model.getSpaceTypes.each do |space_type|
      # populate hash of building types
      if space_type.standardsBuildingType.is_initialized
        bldg_type = space_type.standardsBuildingType.get
        if !building_types.key?(bldg_type)
          building_types[bldg_type] = space_type.floorArea
        else
          building_types[bldg_type] += space_type.floorArea
        end
      else
        runner.registerWarning("Can't identify building type for #{space_type.name}")
      end
    end
    primary_bldg_type = building_types.key(building_types.values.max) # TODO: - this fails if no space types, or maybe just no space types with standards
    lookup_building_type = standard.model_get_lookup_name(primary_bldg_type) # Used for some lookups in the standards gem
    model.getBuilding.setStandardsBuildingType(primary_bldg_type)

    # make construction set and apply to building
    if args['add_constructions']

      # remove default construction sets
      if args['remove_objects']
        model.getDefaultConstructionSets.each(&:remove)
      end

      # TODO: - allow building type and space type specific constructions set selection.
      if ['SmallHotel', 'LargeHotel', 'MidriseApartment', 'HighriseApartment'].include?(primary_bldg_type)
        is_residential = 'Yes'
        occ_type = 'Residential'
      else
        is_residential = 'No'
        occ_type = 'Nonresidential'
      end
      if args['climate_zone'] == 'Lookup From Model'
        climate_zone = standard.model_get_building_climate_zone_and_building_type(model)['climate_zone']
        runner.registerInfo("Using climate zone #{climate_zone} from model")
      else
        climate_zone = args['climate_zone']
        runner.registerInfo("Using climate zone #{climate_zone} from user arguments")
      end
      bldg_def_const_set = standard.model_add_construction_set(model, climate_zone, lookup_building_type, nil, is_residential)
      if bldg_def_const_set.is_initialized
        bldg_def_const_set = bldg_def_const_set.get
        if is_residential then bldg_def_const_set.setName("Res #{bldg_def_const_set.name}") end
        model.getBuilding.setDefaultConstructionSet(bldg_def_const_set)
        runner.registerInfo("Adding default construction set named #{bldg_def_const_set.name}")
      else
        runner.registerError("Could not create default construction set for the building type #{lookup_building_type} in climate zone #{climate_zone}.")
        log_messages_to_runner(runner, debug = true)
        return false
      end

      # Replace the construction of any outdoor-facing "AtticFloor" surfaces
      # with the "ExteriorRoof" - "IEAD" construction for the specific climate zone and template.
      # This prevents creation of buildings where the DOE Prototype building construction set
      # assumes an attic but the supplied geometry used does not have an attic.
      new_construction = nil
      climate_zone_set = standard.model_find_climate_zone_set(model, climate_zone)
      model.getSurfaces.sort.each do |surf|
        next unless surf.outsideBoundaryCondition == 'Outdoors'
        next unless surf.surfaceType == 'RoofCeiling'
        next if surf.construction.empty?
        construction = surf.construction.get
        standards_info = construction.standardsInformation
        next if standards_info.intendedSurfaceType.empty?
        next unless standards_info.intendedSurfaceType.get == 'AtticFloor'
        if new_construction.nil?
          new_construction = standard.model_find_and_add_construction(model,
                                                                      climate_zone_set,
                                                                      'ExteriorRoof',
                                                                      'IEAD',
                                                                      occ_type)
        end
        surf.setConstruction(new_construction)
        runner.registerInfo("Changed the construction for #{surf.name} from #{construction.name} to #{new_construction.name} to avoid outdoor-facing attic floor constructions in buildings with no attic space.")
      end

      # address any adiabatic surfaces that don't have hard assigned constructions
      model.getSurfaces.each do |surface|
        next if surface.outsideBoundaryCondition != 'Adiabatic'
        next if surface.construction.is_initialized
        surface.setAdjacentSurface(surface)
        surface.setConstruction(surface.construction.get)
        surface.setOutsideBoundaryCondition('Adiabatic')
      end

      # modify the infiltration rates
      if args['remove_objects']
        model.getSpaceInfiltrationDesignFlowRates.each(&:remove)
      end
      standard.model_apply_infiltration_standard(model)
      standard.model_modify_infiltration_coefficients(model, primary_bldg_type, climate_zone)

      # set ground temperatures from DOE prototype buildings
      standard.model_add_ground_temperatures(model, primary_bldg_type, climate_zone)

    end

    # add elevators (returns ElectricEquipment object)
    if args['add_elevators']

      # remove elevators as spaceLoads or exteriorLights
      model.getSpaceLoads.each do |instance|
        next if !instance.name.to_s.include?('Elevator') # most prototype building types model exterior elevators with name Elevator
        instance.remove
      end
      model.getExteriorLightss.each do |ext_light|
        next if !ext_light.name.to_s.include?('Fuel equipment') # some prototype building types model exterior elevators by this name
        ext_light.remove
      end

      elevators = standard.model_add_elevators(model)
      if elevators.nil?
        runner.registerInfo('No elevators added to the building.')
      else
        elevator_def = elevators.electricEquipmentDefinition
        design_level = elevator_def.designLevel.get
        runner.registerInfo("Adding #{elevators.multiplier.round(1)} elevators each with power of #{OpenStudio.toNeatString(design_level, 0, true)} (W), plus lights and fans.")
        elevator_def.setFractionLost(1.0)
        elevator_def.setFractionRadiant(0.0)
      end
    end

    # add exterior lights (returns a hash where key is lighting type and value is exteriorLights object)
    if args['add_exterior_lights']

      if args['remove_objects']
        model.getExteriorLightss.each do |ext_light|
          next if ext_light.name.to_s.include?('Fuel equipment') # some prototype building types model exterior elevators by this name
          ext_light.remove
        end
      end

      exterior_lights = standard.model_add_typical_exterior_lights(model, args['exterior_lighting_zone'].chars[0].to_i, args['onsite_parking_fraction'])
      exterior_lights.each do |k, v|
        runner.registerInfo("Adding Exterior Lights named #{v.exteriorLightsDefinition.name} with design level of #{v.exteriorLightsDefinition.designLevel} * #{OpenStudio.toNeatString(v.multiplier, 0, true)}.")
      end
    end

    # add_exhaust
    if args['add_exhaust']

      # remove exhaust objects
      if args['remove_objects']
        model.getFanZoneExhausts.each(&:remove)
      end

      zone_exhaust_fans = standard.model_add_exhaust(model, args['kitchen_makeup']) # second argument is strategy for finding makeup zones for exhaust zones
      zone_exhaust_fans.each do |k, v|
        max_flow_rate_ip = OpenStudio.convert(k.maximumFlowRate.get, 'm^3/s', 'cfm').get
        if v.key?(:zone_mixing)
          zone_mixing = v[:zone_mixing]
          mixing_source_zone_name = zone_mixing.sourceZone.get.name
          mixing_design_flow_rate_ip = OpenStudio.convert(zone_mixing.designFlowRate.get, 'm^3/s', 'cfm').get
          runner.registerInfo("Adding #{OpenStudio.toNeatString(max_flow_rate_ip, 0, true)} (cfm) of exhaust to #{k.thermalZone.get.name}, with #{OpenStudio.toNeatString(mixing_design_flow_rate_ip, 0, true)} (cfm) of makeup air from #{mixing_source_zone_name}")
        else
          runner.registerInfo("Adding #{OpenStudio.toNeatString(max_flow_rate_ip, 0, true)} (cfm) of exhaust to #{k.thermalZone.get.name}")
        end
      end
    end

    # add service water heating demand and supply
    if args['add_swh']

      # remove water use equipment and water use connections
      if args['remove_objects']
        # TODO: - remove plant loops used for service water heating
        model.getWaterUseEquipments.each(&:remove)
        model.getWaterUseConnectionss.each(&:remove)
      end

      # Infer the SWH type
      if args['swh_src'] == 'Inferred'
        if args['htg_src'] == 'NaturalGas' || args['htg_src'] == 'DistrictHeating'
          args['swh_src'] = 'NaturalGas' # If building has gas service, probably uses natural gas for SWH
        elsif args['htg_src'] == 'Electricity'
          args['swh_src'] == 'Electricity' # If building is doing space heating with electricity, probably used for SWH
        elsif args['htg_src'] == 'DistrictAmbient'
          args['swh_src'] == 'HeatPump' # If building has district ambient loop, it is fancy and probably uses HPs for SWH
        else
          args['swh_src'] = nil # Use inferences built into OpenStudio Standards for each building and space type
        end
      end

      typical_swh = standard.model_add_typical_swh(model, water_heater_fuel: args['swh_src'])
      midrise_swh_loops = []
      stripmall_swh_loops = []
      typical_swh.each do |loop|
        if loop.name.get.include?('MidriseApartment')
          midrise_swh_loops << loop
        elsif loop.name.get.include?('RetailStripmall')
          stripmall_swh_loops << loop
        else
          water_use_connections = []
          loop.demandComponents.each do |component|
            next if !component.to_WaterUseConnections.is_initialized
            water_use_connections << component
          end
          runner.registerInfo("Adding #{loop.name} to the building. It has #{water_use_connections.size} water use connections.")
        end
      end
      if !midrise_swh_loops.empty?
        runner.registerInfo("Adding #{midrise_swh_loops.size} MidriseApartment service water heating loops.")
      end
      if !stripmall_swh_loops.empty?
        runner.registerInfo("Adding #{stripmall_swh_loops.size} RetailStripmall service water heating loops.")
      end
    end

    # TODO: - when add methods below add bool to enable/disable them with default value to true

    # add daylight controls, need to perform a sizing run for 2010
    if args['template'] == '90.1-2010' || args['template'] == 'ComStock 90.1-2010'
      if standard.model_run_sizing_run(model, "#{Dir.pwd}/SRvt") == false
        log_messages_to_runner(runner, debug = true)
        return false
      end
    end
    standard.model_add_daylighting_controls(model)

    # add refrigeration
    if args['add_refrigeration']

      # remove refrigeration equipment
      if args['remove_objects']
        model.getRefrigerationSystems.each(&:remove)
      end

      # Add refrigerated cases and walkins
      standard.model_add_typical_refrigeration(model, primary_bldg_type)

    end

    # TODO: - add slab modeling and slab insulation

    # TODO: - fuel customization for cooking and laundry
    # works by switching some fraction of electric loads to gas if requested (assuming base load is electric)

    # add thermostats
    if args['add_thermostat']

      # remove thermostats
      if args['remove_objects']
        model.getThermostatSetpointDualSetpoints.each(&:remove)
      end

      model.getSpaceTypes.each do |space_type|
        # create thermostat schedules
        # apply internal load schedules
        # the last bool test it to make thermostat schedules. They are added to the model but not assigned
        standard.space_type_apply_internal_load_schedules(space_type, false, false, false, false, false, false, true)

        # identify thermal thermostat and apply to zones (apply_internal_load_schedules names )
        model.getThermostatSetpointDualSetpoints.each do |thermostat|
          next if !thermostat.name.to_s.include?(space_type.name.to_s)
          runner.registerInfo("Assigning #{thermostat.name} to thermal zones with #{space_type.name} assigned.")
          space_type.spaces.each do |space|
            next if !space.thermalZone.is_initialized
            space.thermalZone.get.setThermostatSetpointDualSetpoint(thermostat)
          end
          next
        end
      end
    end

    # add hvac system
    if args['add_hvac']

      # remove HVAC objects
      if args['remove_objects']
        standard.model_remove_prm_hvac(model)
      end

      case args['system_type']
      when 'Inferred'

        # Get the hvac delivery type enum
        hvac_delivery = case args['hvac_delivery_type']
                        when 'Forced Air'
                          'air'
                        when 'Hydronic'
                          'hydronic'
                        end

        # Group the zones by occupancy type.  Only split out non-dominant groups if their total area exceeds the limit.
        sys_groups = standard.model_group_zones_by_type(model, OpenStudio.convert(20_000, 'ft^2', 'm^2').get)

        # For each group, infer the HVAC system type.
        sys_groups.each do |sys_group|
          # Infer the primary system type
          # runner.registerInfo("template = #{args['template']}, climate_zone = #{climate_zone}, occ_type = #{sys_group['type']}, hvac_delivery = #{hvac_delivery}, htg_src = #{args['htg_src']}, clg_src = #{args['clg_src']}, area_ft2 = #{sys_group['area_ft2']}, num_stories = #{sys_group['stories']}")
          sys_type, central_htg_fuel, zone_htg_fuel, clg_fuel = standard.model_typical_hvac_system_type(model,
                                                                                                        climate_zone,
                                                                                                        sys_group['type'],
                                                                                                        hvac_delivery,
                                                                                                        args['htg_src'],
                                                                                                        args['clg_src'],
                                                                                                        OpenStudio.convert(sys_group['area_ft2'], 'ft^2', 'm^2').get,
                                                                                                        sys_group['stories'])

          # Infer the secondary system type for multizone systems
          sec_sys_type = case sys_type
                         when 'PVAV Reheat', 'VAV Reheat'
                           'PSZ-AC'
                         when 'PVAV PFP Boxes', 'VAV PFP Boxes'
                           'PSZ-HP'
                         else
                           sys_type # same as primary system type
                         end

          # Group zones by story
          story_zone_lists = standard.model_group_zones_by_story(model, sys_group['zones'])

          # On each story, add the primary system to the primary zones
          # and add the secondary system to any zones that are different.
          story_zone_lists.each do |story_group|
            # Differentiate primary and secondary zones, based on
            # operating hours and internal loads (same as 90.1 PRM)
            pri_sec_zone_lists = standard.model_differentiate_primary_secondary_thermal_zones(model, story_group)
            # Add the primary system to the primary zones
            unless standard.model_add_hvac_system(model, sys_type, central_htg_fuel, zone_htg_fuel, clg_fuel, pri_sec_zone_lists['primary'])
              runner.registerError("HVAC system type '#{sys_type}' not recognized. Check input system type argument against Model.hvac.rb for valid hvac system type names.")
              return false
            end
            # Add the secondary system to the secondary zones (if any)
            if !pri_sec_zone_lists['secondary'].empty?
              unless standard.model_add_hvac_system(model, sec_sys_type, central_htg_fuel, zone_htg_fuel, clg_fuel, pri_sec_zone_lists['secondary'])
                runner.registerError("HVAC system type '#{sys_type}' not recognized. Check input system type argument against Model.hvac.rb for valid hvac system type names.")
                return false
              end
            end
          end
        end

      else # HVAC system_type specified

        # Group the zones by occupancy type.  Only split out non-dominant groups if their total area exceeds the limit.
        sys_groups = standard.model_group_zones_by_type(model, OpenStudio.convert(20_000, 'ft^2', 'm^2').get)
        sys_groups.each do |sys_group|
          # Group the zones by story
          story_groups = standard.model_group_zones_by_story(model, sys_group['zones'])

          # Add the user specified HVAC system for each story.
          # Single-zone systems will get one per zone.
          story_groups.each do |zones|
            model.add_cbecs_hvac_system(standard, args['system_type'], zones)
          end
        end
      end
    end

    # hours of operation
    if args['modify_wkdy_op_hrs'] || args['modify_wknd_op_hrs']
      # Infer the current hours of operation schedule for the building
      op_sch = standard.model_infer_hours_of_operation_building(model)

      # Convert existing schedules in the model to parametric schedules based on current hours of operation
      standard.model_setup_parametric_schedules(model)

      # Create start and end times from start time and duration supplied
      wkdy_start_time = nil
      wkdy_end_time = nil
      wknd_start_time = nil
      wknd_end_time = nil
      # weekdays
      if args['modify_wkdy_op_hrs']
        wkdy_start_time = OpenStudio::Time.new(0, wkdy_op_hrs_start_time_hr, wkdy_op_hrs_start_time_min, 0)
        wkdy_end_time = wkdy_start_time + OpenStudio::Time.new(0, wkdy_op_hrs_duration_hr, wkdy_op_hrs_duration_min, 0)
      end
      # weekends
      if args['modify_wknd_op_hrs']
        wknd_start_time = OpenStudio::Time.new(0, wknd_op_hrs_start_time_hr, wknd_op_hrs_start_time_min, 0)
        wknd_end_time = wknd_start_time + OpenStudio::Time.new(0, wknd_op_hrs_duration_hr, wknd_op_hrs_duration_min, 0)
      end

      # Modify hours of operation, using weekdays values for all weekdays and weekend values for Saturday and Sunday
      standard.schedule_ruleset_set_hours_of_operation(op_sch,
                                                       wkdy_start_time: wkdy_start_time,
                                                       wkdy_end_time: wkdy_end_time,
                                                       sat_start_time: wknd_start_time,
                                                       sat_end_time: wknd_end_time,
                                                       sun_start_time: wknd_start_time,
                                                       sun_end_time: wknd_end_time)

      # Apply new operating hours to parametric schedules to make schedules in model reflect modified hours of operation
      parametric_schedules = standard.model_apply_parametric_schedules(model, error_on_out_of_order: false)
      runner.registerInfo("Updated #{parametric_schedules.size} schedules with new hours of operation.")
    end

    # set hvac controls and efficiencies (this should be last model articulation element)
    if args['add_hvac']
      # set additional properties for building
      props = model.getBuilding.additionalProperties
      props.setFeature('hvac_system_type',"#{args['system_type']}")

      case args['system_type']
        when 'Ideal Air Loads'

        else
          # Set the heating and cooling sizing parameters
          standard.model_apply_prm_sizing_parameters(model)

          # Perform a sizing run
          if standard.model_run_sizing_run(model, "#{Dir.pwd}/SR1") == false
            log_messages_to_runner(runner, debug = true)
            return false
          end

          # If there are any multizone systems, reset damper positions
          # to achieve a 60% ventilation effectiveness minimum for the system
          # following the ventilation rate procedure from 62.1
          standard.model_apply_multizone_vav_outdoor_air_sizing(model)

          # Apply the prototype HVAC assumptions
          standard.model_apply_prototype_hvac_assumptions(model, primary_bldg_type, climate_zone)

          # Apply the HVAC efficiency standard
          standard.model_apply_hvac_efficiency_standard(model, climate_zone)
      end
    end

    # add internal mass
    if args['add_internal_mass']

      if args['remove_objects']
        model.getSpaceLoads.each do |instance|
          next unless instance.to_InternalMass.is_initialized
          instance.remove
        end
      end

      # add internal mass to conditioned spaces; needs to happen after thermostats are applied
      standard.model_add_internal_mass(model, primary_bldg_type)
    end

    # set unmet hours tolerance
    unmet_hrs_tol_r = args['unmet_hours_tolerance']
    unmet_hrs_tol_k = OpenStudio.convert(unmet_hrs_tol_r, 'R', 'K').get
    tolerances = model.getOutputControlReportingTolerances
    tolerances.setToleranceforTimeHeatingSetpointNotMet(unmet_hrs_tol_k)
    tolerances.setToleranceforTimeCoolingSetpointNotMet(unmet_hrs_tol_k)

    # remove everything but spaces, zones, and stub space types (extend as needed for additional objects, may make bool arg for this)
    if args['remove_objects']
      model.purgeUnusedResourceObjects
      objects_after_cleanup = initial_objects - model.getModelObjects.size
      if objects_after_cleanup > 0
        runner.registerInfo("Removing #{objects_after_cleanup} objects from model")
      end
    end

    # report final condition of model
    runner.registerFinalCondition("The building finished with #{model.getModelObjects.size} objects.")

    # log messages to info messages
    log_messages_to_runner(runner, debug = false)

    return true
  end
end

# register the measure to be used by the application
CreateTypicalBuildingFromModel.new.registerWithApplication
