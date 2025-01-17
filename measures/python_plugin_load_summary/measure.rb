# ComStock, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class PythonPluginLoadSummary < OpenStudio::Measure::ModelMeasure

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

  # define what happens when the measure is run
  def run(model, runner, usr_args)

    # call the parent class method
    super(model, runner, usr_args)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(model), usr_args)

    # define necessary E+ output variables
    outputs = [
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

    # add outputs, fix frequency at runperiod
    # python plugin just needs variable to exist in the idf
    # setting to minimum frequency reduces runtime overhead
    outputs.each do |o|
      model.getThermalZones.each do |z|
        out_var = OpenStudio::Model::OutputVariable.new(o, model)
        out_var.setKeyValue(z.name.get)
        out_var.setReportingFrequency('RunPeriod')
      end
    end

    # get path for python script
    py_dir = ''
    runner.workflow.absoluteFilePaths.each do |ap|
      if ap.to_s[-15, 15] == 'generated_files'
        py_dir = ap
      end
    end

    # write python script
    File.open("#{py_dir}/in.py", 'w') do |f|
      f.puts('from pyenergyplus.plugin import EnergyPlusPlugin')
      f.puts('')
      f.puts('class LoadSummary(EnergyPlusPlugin):')
      f.puts('')
      f.puts('    def __init__(self):')
      f.puts('')
      f.puts('        super().__init__()')
      f.puts('        self.need_to_get_handles = True')
      f.puts('')
      outputs.each do |o|
        on = o.downcase.gsub(' ', '_')
        model.getThermalZones.each do |z|
          zn = z.name.get.downcase.gsub(' ', '_').gsub('-', '_')
          f.puts("        self.#{on}_#{zn}_hndl = None")
        end
      end
      f.puts('')
      f.puts('    def get_handles(self, state):')
      f.puts('')
      outputs.each do |o|
        on = o.downcase.gsub(' ', '_')
        model.getThermalZones.each do |z|
          zn = z.name.get.downcase.gsub(' ', '_').gsub('-', '_')
          pp = 'self.api.exchange.get_variable_handle'
          f.puts("        self.#{on}_#{zn}_hndl = #{pp}(")
          f.puts('            state,')
          f.puts("            \'#{o}\',")
          f.puts("            \'#{z.name.get}\'")
          f.puts('        )')
          f.puts('')
        end
      end
      f.puts('')
      f.puts('        self.need_to_get_handles = False')
      f.puts('')
      f.puts('    def on_end_of_zone_timestep_before_zone_reporting(self, state) -> int:')
      f.puts('')
      f.puts('        if self.need_to_get_handles:')
      f.puts('            self.get_handles(state)')
      f.puts('')
      outputs.each do |o|
        on = o.downcase.gsub(' ', '_')
        model.getThermalZones.each do |z|
          zn = z.name.get.downcase.gsub(' ', '_').gsub('-', '_')
          pp = 'self.api.exchange.get_variable_value'
          f.puts("        self.#{on}_#{zn} = #{pp}(")
          f.puts('            state,')
          f.puts("            self.#{on}_#{zn}_hndl")
          f.puts('        )')
          f.puts('')
        end
      end
      f.puts('        return 0')
    end

    # get python script as external file
    py_path = runner.workflow.findFile("#{py_dir}/in.py")
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

    return true
  end

end

# this allows the measure to be use by the application
PythonPluginLoadSummary.new.registerWithApplication
