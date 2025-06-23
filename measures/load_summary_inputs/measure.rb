# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'
require 'json'

# start the measure
class LoadSummaryInputs < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'LoadSummaryInputs'
  end

  # human readable description
  def description
    return 'Adds outputs and python plugin script to generate load components'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'MODELER_Adds outputs and python plugin script to generate load components'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define the components that will be used in the load summary
  def components
    [
    'people_gain',
    'light_gain',
    'equip_gain',
    'win_sol',
    'ext_wall',
    'fnd_wall',
    'roof',
    'ext_flr',
    'gnd_flr',
    'win_cond',
    'door',
    'infil',
    'vent'
    ]
  end

  # define the modes that will be used in the load summary
  def modes
    [
      'htg',
      'clg',
      'flt'
    ]
  end

  # define the variables that will be used in the load summary
  def variables_names
    [
      'Zone Air Heat Balance System Air Transfer Rate',
      'Zone Air Heat Balance System Convective Heat Gain Rate',
      'Zone People Convective Heating Energy',
      'Zone People Radiant Heating Energy',
      'Zone Lights Convective Heating Energy',
      'Zone Lights Radiant Heating Energy',
      'Zone Electric Equipment Convective Heating Energy',
      'Zone Electric Equipment Radiant Heating Energy',
      'Zone Gas Equipment Convective Heating Energy',
      'Zone Gas Equipment Radiant Heating Energy',
      'Zone Hot Water Equipment Convective Heating Energy',
      'Zone Hot Water Equipment Radiant Heating Energy',
      'Zone Other Equipment Convective Heating Energy',
      'Zone Other Equipment Radiant Heating Energy',
      'Enclosure Windows Total Transmitted Solar Radiation Energy',
      'Surface Window Inside Face Glazing Net Infrared Heat Transfer Rate',
      'Surface Window Inside Face Shade Net Infrared Heat Transfer Rate',
      'Surface Window Inside Face Gap between Shade and Glazing Zone Convection Heat Gain Rate',
      'Surface Inside Face Convection Heat Gain Energy',
      'Zone Infiltration Sensible Heat Gain Energy',
      'Zone Infiltration Sensible Heat Loss Energy',
      'Zone Mechanical Ventilation Heating Load Increase Energy',
      'Zone Mechanical Ventilation Heating Load Decrease Energy',
      'Zone Mechanical Ventilation Cooling Load Increase Energy',
      'Zone Mechanical Ventilation Cooling Load Decrease Energy',
    ]
  end

  def get_surface_names_areas_by_bc_and_type(zone, boundary_conditions, type)
    surface_info = {}
    zone.spaces.each do |space|
      surfs = space.surfaces.select { |s| boundary_conditions.include? s.outsideBoundaryCondition and s.surfaceType == type }
      surfs.each do |surface|
        surface_info[surface.name.get] = surface.netArea
      end
    end
    surface_info
  end

  def get_subsurface_names_areas_by_type(zone, type)
    subsurface_info = {}
    zone.spaces.each do |space|
      space.surfaces.each do |surface|
        subsurfaces = surface.subSurfaces.select { |s| s.subSurfaceType.downcase.include? type }
        subsurfaces.each do |subsurface|
          subsurface_info[subsurface.name.get] = subsurface.netArea
        end
      end
    end
    subsurface_info
  end

  def get_internal_mass_names_areas(zone)
    internal_mass_info = {}
    zone.spaces.each do |space|
      space.internalMass.each do |internal_mass|
        if internal_mass.surfaceArea.is_initialized
          internal_mass_info[internal_mass.name.get] = internal_mass.surfaceArea.get
        elsif internal_mass.surfaceAreaPerFloorArea.is_initialized
          internal_mass_info[internal_mass.name.get] = internal_mass.surfaceAreaPerFloorArea.get * space.floorArea
        elsif internal_mass.surfaceAreaPerPerson.is_initialized
          internal_mass_info[internal_mass.name.get] = internal_mass.surfaceAreaPerPerson.get * space.numberOfPeople
        end
      end
    end
    internal_mass_info
  end

  def get_surface_info(model)
    surf_h = {}

    model.getThermalZones.sort.each do |zone|
      zone_name = zone.name.get
      surf_h[zone_name] = {}

      surf_h[zone_name]['ext_wall'] = get_surface_names_areas_by_bc_and_type(zone, ['Outdoors'], 'Wall')
      surf_h[zone_name]['fnd_wall'] = get_surface_names_areas_by_bc_and_type(zone, ['Ground', 'GroundFCfactorMethod', 'Foundation'], 'Wall')
      surf_h[zone_name]['roof'] = get_surface_names_areas_by_bc_and_type(zone, ['Outdoors'], 'RoofCeiling')
      surf_h[zone_name]['ext_flr'] = get_surface_names_areas_by_bc_and_type(zone, ['Outdoors'], 'Floor')
      surf_h[zone_name]['gnd_flr'] = get_surface_names_areas_by_bc_and_type(zone, ['Ground', 'GroundFCfactorMethod', 'Foundation'], 'Floor')
      surf_h[zone_name]['win'] = get_subsurface_names_areas_by_type(zone, 'window')
      surf_h[zone_name]['door'] = get_subsurface_names_areas_by_type(zone, 'door')
      surf_h[zone_name]['int_wall'] = get_surface_names_areas_by_bc_and_type(zone, ['Surface', 'Adiabatic'], 'Wall')
      surf_h[zone_name]['int_ceil'] = get_surface_names_areas_by_bc_and_type(zone, ['Surface', 'Adiabatic'], 'RoofCeiling')
      surf_h[zone_name]['int_flr'] = get_surface_names_areas_by_bc_and_type(zone, ['Surface', 'Adiabatic'], 'Floor')
      surf_h[zone_name]['int_mass'] = get_internal_mass_names_areas(zone)
    end

    return surf_h
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # request advanced reporting for window heat gain components
    model.getOutputDiagnostics.addKey('DisplayAdvancedReportVariables')

    # create python plugin variables
    components.each do |component|
      modes.each do |mode|
        # python plugin variables
        py_var = OpenStudio::Model::PythonPluginVariable.new(model)
        py_var.setName("#{component}_#{mode}_glob")

        # python plugin output variables
        py_out_var = OpenStudio::Model::PythonPluginOutputVariable.new(py_var)
        py_out_var.setName("#{component}_#{mode}")
        py_out_var.setTypeofDatainVariable('Summed')
        py_out_var.setUpdateFrequency('ZoneTimestep')
        py_out_var.setUnits('J')


        # add a regular output variable that references it
        out_var = OpenStudio::Model::OutputVariable.new("PythonPlugin:OutputVariable", model)
        out_var.setKeyValue(py_out_var.nameString)
        # out_var.setReportingFrequency('Timestep') # TODO: change to 'RunPeriod' for production
        out_var.setReportingFrequency('RunPeriod')
      end
    end

    # add simulation output variables needed for the plugin
    variables_names.each do |var_name|
      out_var = OpenStudio::Model::OutputVariable.new(var_name, model)
      # out_var.setReportingFrequency('Timestep') # TODO: change to 'RunPeriod' for production
      out_var.setReportingFrequency('RunPeriod')
    end

    # read in the template
    rsrcs = "#{File.dirname(__FILE__)}/resources"
    
    # get surface information
    surf_h = get_surface_info(model)
    surf_h_json = JSON.pretty_generate(surf_h)

    temp_path = "#{rsrcs}/python_plugin.py.erb"

    template = ''
    File.open(temp_path, 'r') do |file|
      template = file.read
    end

    # configure template with variable values
    renderer = ERB.new(template)
    py_out = renderer.result(binding)

    # write the python plugin file to resources dir
    plugin_path = File.join(Dir.pwd, 'python_EMS', 'in.py')
    File.write(plugin_path, py_out)

    external_file = OpenStudio::Model::ExternalFile.getExternalFile(model, plugin_path)
    external_file = external_file.get
    
    # python plugin instance
    python_plugin_instance = OpenStudio::Model::PythonPluginInstance.new(external_file, 'LoadSummary')
    python_plugin_instance.setName('Load Summary')
    python_plugin_instance.setRunDuringWarmupDays(true)

    runner.registerFinalCondition('Load Summary Inputs added successfully.')
    return true
  end
end

# register the measure to be used by the application
LoadSummaryInputs.new.registerWithApplication
