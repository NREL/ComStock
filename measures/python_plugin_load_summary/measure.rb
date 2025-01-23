# ComStock, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'erb'

# start the measure
class PythonPluginLoadSummary < OpenStudio::Measure::ReportingMeasure

  # human readable name
  def name
    return 'Python Plugin Loads Summary'
  end

  # human readable description
  def description
    return 'Breaks out the building load and HVAC by end-use'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Uses the Python plugin to report the load and HVAC by component'
  end

  # define the arguments that the user will input
  def arguments(model = nil)

    # create empty argument vector to add arguments to
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  def energyPlusOutputRequests(runner, usr_args)

    # call the parent class method
    super(runner, usr_args)

    # define idf object vector
    result = OpenStudio::IdfObjectVector.new

    # get the model and zones
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model')
      return result
    end
    model = model.get
    zones = model.getThermalZones

    # use the built-in error checking
    unless runner.validateUserArguments(arguments(model), usr_args)
      return false
    end

    # define necessary e+ output variables
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

    # trim to one output for testing
    out_vars = ['Zone People Convective Heating Energy']

    # add outputs, fix frequency at runperiod
    # python plugin just needs variable to exist in the idf
    # setting to minimum frequency reduces runtime overhead
    out_vars.each do |o|
      zones.each do |z|
        n = z.name.get
        result << OpenStudio::IdfObject.load(
          "Output:Variable,#{n},#{o},RunPeriod;"
        ).get
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
    renderer = ERB.new(template)
    py_out = renderer.result(binding)

    # write python script to resources directory
    File.open("#{rsrcs}/in.py", 'w') do |f|
      f << py_out
      # make sure data is written to the disk one way or the other
      begin
        f.fsync
      rescue StandardError
        f.flush
      end
    end

    # get python script as external file
    py_path = runner.workflow.findFile("#{rsrcs}/in.py")
    if py_path.is_initialized
        py_file = OpenStudio::Model::ExternalFile::getExternalFile(
          model,
          py_path.get.to_s
        ).get
    else
      runner.registerError("Did not find #{py_path}")
      return false
    end

    # add python plugin instance
    py_inst = OpenStudio::Model::PythonPluginInstance.new(
      py_file,
      'LoadSummary'
    )
    py_inst.setName('Load Summary')

    # add python plugin instance
    result << OpenStudio::IdfObject.load(
      'PythonPlugin:Instance,Load Summary,No,in,LoadSummary;'
    ).get

    # set python site packages base on ruby platform
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
    result << OpenStudio::IdfObject.load(
      "PythonPlugin:SearchPaths,Py Paths,Yes,Yes,No,#{pckg},#{rsrcs};"
    ).get

    result
  end

  # define what happens when the measure is run
  def run(runner, usr_args)

    # call the parent class method
    super(runner, usr_args)

    return true
  end

end

# this allows the measure to be use by the application
PythonPluginLoadSummary.new.registerWithApplication
