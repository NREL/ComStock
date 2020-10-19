# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'
require 'csv'
require 'fileutils'
require 'open3'
require 'rbconfig'
require "#{File.dirname(__FILE__)}/resources/weather"

#start the measure
class TimeseriesCSVExport < OpenStudio::Measure::ReportingMeasure

  def os
    @os ||= (
      host_os = RbConfig::CONFIG['host_os']
      case host_os
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        :windows
      when /darwin|mac os/
        :macosx
      when /linux/
        :linux
      when /solaris|bsd/
        :unix
      else
        raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
      end
    )
  end

  # human readable name
  def name
    return "Timeseries CSV Export"
  end

  # human readable description
  def description
    return "Exports all available hourly timeseries enduses to csv, and uses them for utility bill calculations."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Exports all available hourly timeseries enduses to csv, and uses them for utility bill calculations."
  end

  def fuel_types
    fuel_types = ['Electricity',
                  'Gas',
                  'DistrictCooling',
                  'DistrictHeating',
                  'Water',
                  'FuelOil#1',
                  'Propane']
    return fuel_types
  end

  def end_uses
    end_uses = ['Heating',
                'Cooling',
                'InteriorLights',
                'ExteriorLights',
                'InteriorEquipment',
                'ExteriorEquipment',
                'Fans',
                'Pumps',
                'HeatRejection',
                'Humidifier',
                'HeatRecovery',
                'WaterSystems',
                'Refrigeration',
                'Generators',
                'Facility']
    return end_uses
  end

  def end_use_subcats
    end_use_subcats = ['ResPublicArea:InteriorEquipment:Electricity',
                       'ResPublicArea:InteriorLights:Electricity',
                       'Elevators:InteriorEquipment:Electricity']
  end

  def output_vars
    output_vars = ['Zone Mean Air Temperature',
                   'Zone Mean Air Humidity Ratio',
                   'Fan Runtime Fraction']

    return output_vars
  end

  # define the arguments that the user will input
  def arguments()
    args = OpenStudio::Measure::OSArgumentVector.new

    #make an argument for the frequency
    reporting_frequency_chs = OpenStudio::StringVector.new
    reporting_frequency_chs << "Timestep"
    reporting_frequency_chs << "Hourly"
    reporting_frequency_chs << "Daily"
    reporting_frequency_chs << "Monthly"
    reporting_frequency_chs << "RunPeriod"
    arg = OpenStudio::Measure::OSArgument::makeChoiceArgument('reporting_frequency', reporting_frequency_chs, true)
    arg.setDisplayName("Reporting Frequency")
    arg.setDefaultValue("Hourly")
    args << arg

    #make an argument for including optional output variables
    arg = OpenStudio::Measure::OSArgument::makeBoolArgument("inc_output_variables", true)
    arg.setDisplayName("Include Output Variables")
    arg.setDefaultValue(false)
    args << arg

    return args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    reporting_frequency = runner.getStringArgumentValue("reporting_frequency",user_arguments)
    inc_output_variables = runner.getBoolArgumentValue("inc_output_variables",user_arguments)

    # Request the output for each end use/fuel type combination
    end_uses.each do |end_use|
      fuel_types.each do |fuel_type|
        variable_name = if end_use == 'Facility'
                  "#{fuel_type}:#{end_use}"
                else
                  "#{end_use}:#{fuel_type}"
                end
        result << OpenStudio::IdfObject.load("Output:Meter,#{variable_name},#{reporting_frequency};").get
      end
    end

    # Request the output for each end use subcategory/end use/fuel type combination
    end_use_subcats.each do |subcat|
      result << OpenStudio::IdfObject.load("Output:Meter,#{subcat},#{reporting_frequency};").get
    end

    # Request the output for each variable
    if inc_output_variables
      runner.registerInfo("Requesting Output Variables")
      output_vars.each do |output_var|
        result << OpenStudio::IdfObject.load("Output:Variable,*,#{output_var},#{reporting_frequency};").get
        runner.registerInfo("Requesting Output:Variable,#{output_var},#{reporting_frequency};")
      end
    end

    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return false
    end

    # Assign the user inputs to variables
    reporting_frequency = runner.getStringArgumentValue("reporting_frequency",user_arguments)
    inc_output_variables = runner.getBoolArgumentValue("inc_output_variables",user_arguments)

    # Define run directory location
    run_dir_typical = File.absolute_path(File.join(Dir.pwd, 'run'))
    run_dir_comstock = File.absolute_path(File.join(Dir.pwd, '..'))
    if File.exist?(run_dir_typical)
      run_dir = run_dir_typical
      runner.registerInfo("run_dir = #{run_dir}")
    elsif File.exist?(run_dir_comstock)
      run_dir = run_dir_comstock
      runner.registerInfo("run_dir = #{run_dir}")
    else
      runner.registerError("Could not find directory with EnergyPlus output, cannont extract timeseries results")
      return false
    end

    # Write the file that defines the unit conversions
    convert_txt_path = File.join(run_dir, 'convert.txt')
    File.open(convert_txt_path, 'w') do |f|
      # electricity
      f.puts('!Electricity')
      f.puts('conv,J,kWh,2.777778E-07,0')
      f.puts('wild,elec,J,kWh')
      # natural gas
      f.puts('!Natural Gas')
      f.puts('conv,J,kBtu,9.484517E-07,0')
      f.puts('wild,gas,J,kBtu')
      # water
      f.puts('!Water')
      f.puts('conv,m3,gal,2.641720E+02,0')
    end

    # Write the RVI file, which defines the CSV columns requested
    rvi_path = File.join(run_dir, 'var_request.rvi')
    enduse_timeseries_name = 'enduse_timeseries.csv'
    File.open(rvi_path,'w') do |f|
      f.puts('ip.eso') # convertESOMTR always uses this name
      f.puts(enduse_timeseries_name)

      # End Use/Fuel Type
      end_uses.each do |end_use|
        fuel_types.each do |fuel_type|
          variable_name = if end_use == 'Facility'
                            "#{fuel_type}:#{end_use}"
                          else
                            "#{end_use}:#{fuel_type}"
                          end
          f.puts(variable_name)
        end
      end

      # End Use Subcategories
      end_use_subcats.each do |subcat|
        f.puts(subcat)
      end

      # Optionally request timeseries
      if inc_output_variables
        output_vars.each do |output_var|
          f.puts(output_var)
        end
      end
      f.puts('0') # end-of-file marker
    end

    # Copy the necessary executables to the run directory
    start_time = Time.new
    resources_dir = File.absolute_path(File.join(__dir__, 'resources'))
    runner.registerInfo("resources_dir = #{resources_dir}")

    # Copy convertESOMTR
    convert_eso_name = if os == :windows
                         'convertESOMTR.exe'
                       elsif os == :linux
                         'convertESOMTR'
                       elsif os == :macosx
                         'convertESOMTR.osx' # Made up extension to differentiate from linux
                       end
    orig_convert_eso_path = File.join(resources_dir, convert_eso_name)
    convert_eso_path = File.join(run_dir, convert_eso_name)
    FileUtils.cp(orig_convert_eso_path, convert_eso_path)

    # Copy ReadVarsESO
    readvars_eso_name = if os == :windows
                         'ReadVarsESO.exe'
                       elsif os == :linux
                         'ReadVarsESO'
                       elsif os == :macosx
                         'ReadVarsESO.osx' # Made up extension to differentiate from linux
                       end
    orig_readvars_eso_path = File.join(resources_dir, readvars_eso_name)
    readvars_eso_path = File.join(run_dir, readvars_eso_name)
    FileUtils.cp(orig_readvars_eso_path, readvars_eso_path)    

    # Copy libraries (OSX only)
    if os == :macosx
      ['libgcc_s.1.dylib', 'libgfortran.5.dylib', 'libquadmath.0.dylib'].each do |dylib|
        FileUtils.cp(File.join(resources_dir, dylib), File.join(run_dir, dylib))    
      end
    end
    end_time = Time.new
    runner.registerInfo("Copying executables took #{end_time - start_time} seconds")

    # Call convertESOMTR
    start_time = Time.new
    command = "#{convert_eso_path}"
    stdout_str, stderr_str, status = Open3.capture3(command, chdir: run_dir)
    if status.success?
      runner.registerInfo("Successfully ran convertESOMTR: #{command}")
    else
      runner.registerError("Error running convertESOMTR: #{command}")
      runner.registerError("stdout: #{stdout_str}")
      runner.registerError("stderr: #{stderr_str}")
      return false
    end
    end_time = Time.new
    runner.registerInfo("Running convertESOMTR took #{end_time - start_time} seconds")

    # Call ReadVarsESO
    start_time = Time.new
    command = "#{readvars_eso_path} #{File.basename(rvi_path)} #{reporting_frequency} Unlimited FixHeader"
    stdout_str, stderr_str, status = Open3.capture3(command, chdir: run_dir)
    if status.success?
      runner.registerInfo("Successfully ran convertESOMTR: #{command}")
    else
      runner.registerError("Error running convertESOMTR: #{command}")
      runner.registerError("stdout: #{stdout_str}")
      runner.registerError("stderr: #{stderr_str}")
      return false
    end
    end_time = Time.new
    runner.registerInfo("Running ReadVarsESO took #{end_time - start_time} seconds")

    return true
  end
end

# register the measure to be used by the application
TimeseriesCSVExport.new.registerWithApplication
