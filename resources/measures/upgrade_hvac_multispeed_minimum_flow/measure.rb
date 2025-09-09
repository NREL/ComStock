# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

# see your EnergyPlus installation or the URL below for information on EnergyPlus objects
# http://apps1.eere.energy.gov/buildings/energyplus/pdfs/inputoutputreference.pdf

# see the URL below for information on using life cycle cost objects in OpenStudio
# http://openstudio.nrel.gov/openstudio-life-cycle-examples

# see the URL below for access to C++ documentation on workspace objects (click on "workspace" in the main window to view workspace objects)
# http://openstudio.nrel.gov/sites/openstudio.nrel.gov/files/nv_data/cpp_documentation_it/utilities/html/idf_page.html

# start the measure
class MultispeedMinimumFlow < OpenStudio::Ruleset::WorkspaceUserScript
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Multispeed Minimum Flow'
  end

  # define the arguments that the user will input
  def arguments(workspace)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    return args
  end

  # define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(workspace), user_arguments)
      return false
    end

    type_counts = workspace.objects.group_by { |obj| obj.iddObject.name }
    type_counts.keys.sort.each do |t|
      runner.registerInfo("### DEBUGGING: object type = #{t}, count = #{type_counts[t].size}")
    end

    # get all UnitarySystemPerformance:Multispeed objects in model, if any
    li_multispeed_perf = workspace.getObjectsByType('UnitarySystemPerformance:Multispeed'.to_IddObjectType)

    # check the user_name for reasonableness
    if li_multispeed_perf.empty?
      runner.registerAsNotApplicable('No UnitarySystemPerformance:Multispeed objects found in IDF. Measure is not applicable.')
      return false
    end

    # check if 'multispeed No Load Supply Air Flow Rate Ratio' field is blank
    li_multispeed_perf_objs_to_change = []
    li_multispeed_perf.each do |ms_perf_obj|
      # skip object if 'multispeed No Load Supply Air Flow Rate Ratio' field is populated
      if ms_perf_obj.getDouble(4, false).is_initialized
        runner.registerInfo("Minimum no load flow rate specified for -- #{ms_perf_obj.name} --; this measure will not make model changes to this object.")
      elsif ms_perf_obj.getDouble(5, false).is_initialized && ms_perf_obj.getDouble(6, false).is_initialized
        # determine minimum stage 1 flow ratios for heating and cooling
        htg_spd1_flow_ratio = ms_perf_obj.getDouble(5, true).get
        clg_spd1_min_flow_ratio = ms_perf_obj.getDouble(6, true).get
        min_flow_ratio = [htg_spd1_flow_ratio, clg_spd1_min_flow_ratio].min
        runner.registerInfo("No load minimum flow ratio will be set to #{min_flow_ratio} for -- #{ms_perf_obj.name} --, which matches the minimum of the specified heating or cooling speed 1 airflow ratios.")
        # set flow ratio for no load
        ms_perf_obj.setDouble(4, min_flow_ratio)
        # add to list of changed objects
        li_multispeed_perf_objs_to_change << ms_perf_obj
      else
        runner.registerAsNotApplicable("Multispeed performance object -- #{ms_perf_obj.name} -- does not specify speed 1 heating and cooling flow ratios, and therefore does not provide necessary information to set the no load flow ratio. No model changes will be made to this object.")
      end
    end

    # check if any airflow ratio fields are blank; if so, replace with 0s.
    li_multispeed_perf.each do |ms_perf_obj|
      # get object indices
      num_fields = ms_perf_obj.numFields
      fields_list = (0...(0 + (num_fields - 1)))
      # loop through indicies to replace any 0s
      fields_list.sort.each do |field|
        # replace blanks after position 5 with 1s
        next unless (field >= 5) && !ms_perf_obj.getDouble(field, false).is_initialized

        ms_perf_obj.setDouble(field, 1)
      end
    end

    # reporting initial condition of model
    runner.registerInitialCondition("The building started with #{li_multispeed_perf.size} UnitarySystemPerformance:Multispeed objects which will be assessed for modification.")

    # report final condition
    runner.registerFinalCondition("Of the #{li_multispeed_perf.size} UnitarySystemPerformance:Multispeed objects found in the model, #{li_multispeed_perf_objs_to_change.size} were modified to specify the no load supply air flow ratio as the minimum of the specified heating or cooling speed 1 airflow ratios.")

    return true
  end
end
# this allows the measure to be use by the application
MultispeedMinimumFlow.new.registerWithApplication
