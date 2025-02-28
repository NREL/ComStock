# ComStock, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'erb'

# start the measure
class PythonPluginLoadSummary < OpenStudio::Measure::EnergyPlusMeasure

  # human readable name
  def name
    return 'Python Plugin Loads Summary'
  end

  # human readable description
  def description
    return 'Breaks out the building load and HVAC energy by end-use'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Python plugin to report building load and HVAC energy by component'
  end

  # define the arguments that the user will input
  def arguments(ws)

    # create empty argument vector to add arguments to
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(ws, runner, usr_args)

    # call the parent class method
    super(ws, runner, usr_args)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(ws), usr_args)

    # define necessary energyplus output variables
    out_vars = [
      # internal gains, convective
      ['Zone People Convective Heating Energy', 'people_gain'],
      ['Zone Lights Convective Heating Energy', 'lighting_gain'],
      ['Zone Electric Equipment Convective Heating Energy', 'equipment_gain'],
      ['Zone Gas Equipment Convective Heating Energy', 'equipment_gain'],
      ['Zone Hot Water Equipment Convective Heating Energy', 'equipment_gain'],
      ['Zone Other Equipment Convective Heating Energy', 'equipment_gain'],
      # internal gains, radiant
      ['Zone People Radiant Heating Energy', 'people_gain'],
      ['Zone Lights Radiant Heating Energy', 'lighting_gain'],
      ['Zone Electric Equipment Radiant Heating Energy', 'equipment_gain'],
      ['Zone Gas Equipment Radiant Heating Energy', 'equipment_gain'],
      ['Zone Hot Water Equipment Radiant Heating Energy', 'equipment_gain'],
      ['Zone Other Equipment Radiant Heating Energy', 'equipment_gain'],
      # refrigeration
      ['Refrigeration Zone Case and Walk In Total Sensible Cooling Energy', 'equipment_gain'],
      # infiltration gain/loss
      ['Zone Infiltration Sensible Heat Gain Energy', 'infiltration'],
      ['Zone Infiltration Sensible Heat Loss Energy', 'infiltration'],
      # ventilation gain/loss
      ['Zone Mechanical Ventilation Heating Load Increase Energy', 'ventilation'],
      ['Zone Mechanical Ventilation Cooling Load Decrease Energy', 'ventilation'],
      # air transfer
      ['Zone Air Heat Balance Interzone Air Transfer Rate', ''],
      ['Zone Exhaust Air Sensible Heat Transfer Rate', ''],
      ['Zone Exfiltration Sensible Heat Transfer Rate', ''],
      # surface convection
      ['Surface Inside Face Convection Heat Gain Energy', ''],
      # windows
      ['Zone Windows Total Heat Gain Energy', 'windows_conduction'],
      ['Zone Windows Total Transmitted Solar Radiation Energy', 'windows_solar'],
      ['Zone Windows Total Heat Loss Energy', 'windows_conduction'],
      # zone air heat balance
      ['Zone Air Heat Balance Internal Convective Heat Gain Rate', ''],
      ['Zone Air Heat Balance Surface Convection Rate', ''],
      ['Zone Air Heat Balance Interzone Air Transfer Rate', ''],
      ['Zone Air Heat Balance Outdoor Air Transfer Rate', ''],
      ['Zone Air Heat Balance Air Energy Storage Rate', ''],
      ['Zone Air Heat Balance System Air Transfer Rate', ''],
      ['Zone Air Heat Balance System Convective Heat Gain Rate', ''],
      # zone total gains
      ['Zone Total Internal Radiant Heating Rate', ''],
      ['Zone Total Internal Convective Heating Rate', ''],
      ['Zone Total Internal Latent Gain Rate', ''],
      ['Zone Total Internal Total Heating Rate', '']
    ]

    # define building operating modes
    op_modes = ['heating', 'cooling', 'floating']

    # define python plugin global variables
    py_vars = [
      'people_gain',
      'lighting_gain',
      'equipment_gain',
      'wall',
      'foundation_wall',
      'roof',
      'floor',
      'ground',
      'windows_conduction',
      'doors_conduction',
      'windows_solar',
      'infiltration',
      'ventilation',
    ]

    # populate array of zone names
    zone_names = []
    ot = 'Zone'
    ws.getObjectsByType(ot.to_IddObjectType).each do |o|
      zone_names << o.getString(0, false).get
    end

    # add outputs, fix frequency at runperiod
    # python plugin just needs variable to exist in the idf
    # setting to minimum frequency reduces runtime overhead
    out_vars.each do |ov|
      zone_names.each do |zn|
        ot = 'Output_Variable'
        no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
        no.setString(0, zn)
        no.setString(1, ov[0])
        no.setString(2, 'RunPeriod')
        ws.addObject(no)
      end
    end

    # define resources path
    rsrcs = "#{File.dirname(__FILE__)}/resources"

    # define template path
    temp_path = "#{rsrcs}/python_plugin.py.erb"

    # read in template
    template = ''
    File.open(temp_path, 'r') do |f|
      template = f.read
    end

    # configure template with variable values
    renderer = ERB.new(template, trim_mode: '-')
    py_out = renderer.result(binding)

    # write python plugin script to resources directory
    File.open("#{rsrcs}/in.py", 'w') do |f|
      f << py_out
      # make sure data is written to the disk one way or the other
      begin
        f.fsync
      rescue StandardError
        f.flush
      end
    end

    # define python site packages base on ruby platform
    pckg = ''
    if (RUBY_PLATFORM =~ /linux/) != nil
      pckg = '/usr/local/lib/python3.8/dist-packages'
    elsif (RUBY_PLATFORM =~ /darwin/) != nil
      lib = '/Library/Frameworks/Python.framework/Versions'
      pckg = "#{lib}/3.8/lib/python3.8/site-packages"
    elsif (RUBY_PLATFORM =~ /cygwin|mswin|mingw|bccwin|wince|emx/) != nil
      home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
      lib = '/AppData/Local/Programs/Python/'
      pckg = "#{home}/#{lib}/Python38/Lib/site-packages"
    end

    # add python plugin search paths
    ot = 'PythonPlugin_SearchPaths'
    no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
    no.setString(0, 'Python Plugin Search Paths')
    no.setString(1, 'Yes')
    no.setString(2, 'Yes')
    no.setString(3, 'No')
    no.setString(4, pckg)
    no.setString(5, rsrcs)
    ws.addObject(no)

    # add python plugin instance
    ot = 'PythonPlugin_Instance'
    no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
    no.setString(0, 'Load Summary')
    no.setString(1, 'No')
    no.setString(2, 'in')
    no.setString(3, 'LoadSummary')
    ws.addObject(no)

    # add python plugin global variables
    ot = 'PythonPlugin_Variables'
    no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
    no.setString(0, 'Python Plugin Variables')
    i = 1
    op_modes.each do |om|
      py_vars.each do |pv|
        no.setString(i, "#{om}_#{pv}")
        i+=1
      end
    end
    ws.addObject(no)

    # add python plugin output variable
    op_modes.each do |om|
      py_vars.each do |pv|
        ot = 'PythonPlugin_OutputVariable'
        no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
        no.setString(0, "#{om}_#{pv}")
        no.setString(1, "#{om}_#{pv}")
        no.setString(2, 'Averaged')
        no.setString(3, 'SystemTimestep')
        no.setString(4, '')
        ws.addObject(no)
        # add corresponding energyplus output variable
        ot = 'Output_Variable'
        no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
        no.setString(0, "#{om}_#{pv}")
        no.setString(1, 'PythonPlugin:OutputVariable')
        no.setString(2, 'Timestep')
        ws.addObject(no)
      end
    end

    return true
  end

end

# this allows the measure to be use by the application
PythonPluginLoadSummary.new.registerWithApplication
