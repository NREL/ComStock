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
      'Zone People Convective Heating Energy',
      'Zone Lights Convective Heating Energy',
      'Zone Electric Equipment Convective Heating Energy',
      'Zone Gas Equipment Convective Heating Energy',
      'Zone Hot Water Equipment Convective Heating Energy',
      'Zone Other Equipment Convective Heating Energy',
      # internal gains, radiant
      'Zone People Radiant Heating Energy',
      'Zone Lights Radiant Heating Energy',
      'Zone Electric Equipment Radiant Heating Energy',
      'Zone Gas Equipment Radiant Heating Energy',
      'Zone Hot Water Equipment Radiant Heating Energy',
      'Zone Other Equipment Radiant Heating Energy',
      # refrigeration
      'Refrigeration Zone Case and Walk In Total Sensible Cooling Energy',
      # infiltration gain/loss
      'Zone Infiltration Sensible Heat Gain Energy',
      'Zone Infiltration Sensible Heat Loss Energy',
      # ventilation gain/loss
      'Zone Mechanical Ventilation Heating Load Increase Energy',
      'Zone Mechanical Ventilation Cooling Load Decrease Energy',
      # air transfer
      'Zone Air Heat Balance Interzone Air Transfer Rate',
      'Zone Exhaust Air Sensible Heat Transfer Rate',
      'Zone Exfiltration Sensible Heat Transfer Rate',
      # surface convections
      'Surface Inside Face Convection Heat Gain Energy',
      # windows
      'Zone Windows Total Heat Gain Energy',
      'Zone Windows Total Transmitted Solar Radiation Energy',
      'Zone Windows Total Heat Loss Energy',
      # zone air heat balance
      'Zone Air Heat Balance Internal Convective Heat Gain Rate',
      'Zone Air Heat Balance Surface Convection Rate',
      'Zone Air Heat Balance Interzone Air Transfer Rate',
      'Zone Air Heat Balance Outdoor Air Transfer Rate',
      'Zone Air Heat Balance Air Energy Storage Rate',
      'Zone Air Heat Balance System Air Transfer Rate',
      'Zone Air Heat Balance System Convective Heat Gain Rate',
      # zone total gains
      'Zone Total Internal Radiant Heating Rate',
      'Zone Total Internal Convective Heating Rate',
      'Zone Total Internal Latent Gain Rate',
      'Zone Total Internal Total Heating Rate'
    ]

    # trim to a few outputs for testing
    # todo: remove this
    # out_vars = [
    #   'Zone Lights Convective Heating Energy',
    #   'Zone Lights Radiant Heating Energy'
    # ]

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
        no.setString(1, ov)
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

    # define python plugin global variables
    # todo: complete, right now temporary for testing
    py_vars = [
      'conv_int_gains',
      'rad_int_gains'
    ]

    # add python plugin global variables
    ot = 'PythonPlugin_Variables'
    no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
    no.setString(0, 'Python Plugin Variables')
    i = 1
    py_vars.each do |v|
      no.setString(i, v)
      i+=1
    end
    ws.addObject(no)

    # add python plugin output variable
    py_vars.each do |pv|
      ot = 'PythonPlugin_OutputVariable'
      no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
      no.setString(0, pv)
      no.setString(1, pv)
      no.setString(2, 'Averaged')
      no.setString(3, 'SystemTimestep')
      no.setString(4, '')
      ws.addObject(no)
      # add corresponding energyplus output variable
      ot = 'Output_Variable'
      no = OpenStudio::IdfObject.new(ot.to_IddObjectType)
      no.setString(0, pv)
      no.setString(1, 'PythonPlugin:OutputVariable')
      no.setString(2, 'Timestep')
      ws.addObject(no)
    end

    return true
  end

end

# this allows the measure to be use by the application
PythonPluginLoadSummary.new.registerWithApplication
