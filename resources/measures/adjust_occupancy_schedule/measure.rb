# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'openstudio-standards'

# require all .rb files in resources folder
Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }


# start the measure
class AdjustOccupancySchedule < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'adjust_occupancy_schedule'
  end

  # human readable description
  def description
    return 'Adjusts People occupancy schedules to change total occupant count'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adjusts People schedule so that peak occupancy is a user-input fraction of existing schedule values'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for peak occupancy fraction
    peak_occ_frac = OpenStudio::Measure::OSArgument.makeDoubleArgument('peak_occ_frac', true)
    peak_occ_frac.setDisplayName('Peak Occupancy Fraction')
    peak_occ_frac.setDefaultValue(0.6)
    args << peak_occ_frac

    # apply/not apply measure
    apply_measure = OpenStudio::Ruleset::OSArgument.makeBoolArgument('apply_measure', true)
    apply_measure.setDisplayName('Apply Measure')
    apply_measure.setDefaultValue(true)
    args << apply_measure

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign argument to variables
    peak_occ_frac = runner.getDoubleArgumentValue('peak_occ_frac', user_arguments)
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)

    # return if measure not applicable
    if !apply_measure
      runner.registerAsNotApplicable('Measure not applied')
      return true
    end

    total_occ = 0
    all_sch_info = []

    # get schedules from all people loads
    model.getPeoples.each do |ppl|
      # gather schedule info
      sch_info = {area: 0, ppl_nom: 0}
      num_sch = ppl.numberofPeopleSchedule.get
      load_def = ppl.peopleDefinition
      sch_info[:sch] = num_sch
      sch_info[:name] = num_sch.name.get
      sch_info[:area] += load_def.floorArea
      sch_info[:ppl_nom] += load_def.getNumberOfPeople(load_def.floorArea)
      sch_info.merge!(OsLib_Schedules.getMinMaxAnnualProfileValue(model, num_sch).transform_keys(&:to_sym))
      all_sch_info << sch_info
    end

    # get unique schedule names
    sch_names = all_sch_info.map{|hash| hash.select{|k,_| k == :name}}.uniq

    # calculate total nominal and schedule-adjusted occupancy
    tot_ppl_nom = all_sch_info.inject(0){|sum,h| sum + h[:ppl_nom]}
    tot_ppl_adj = all_sch_info.inject(0){|sum,h| sum + (h[:ppl_nom] * h[:max])}

    # report initial occupancy values
    runner.registerInitialCondition("#{sch_names.size} Unique occupancy schedules found. Initial total nominal occupancy: #{tot_ppl_nom}, initial peak schedule-adjusted occupancy: #{tot_ppl_adj}.")

    # loop through people schedules and apply adjustment
    runner.registerInfo("Reducing occupancy schedule values by #{peak_occ_frac * 100}%. Design sizing schedule values will remain unchanged.")

    sch_names.each do |h|
      sch_name = h[:name]
      schedule = model.getScheduleRulesetByName(sch_name).get
      # append reduced percentage to schedule name
      schedule.setName(sch_name + " #{peak_occ_frac * 100}%")
      # apply reduction
      schedule = OsLib_Schedules.simpleScheduleValueAdjust(model, schedule, peak_occ_frac, 'Multiplier')
    end

    # report final peak occupancy
    final_info = []
    model.getPeoples.each do |ppl|
      sch_info = {}
      sch_info.merge!(OsLib_Schedules.getMinMaxAnnualProfileValue(model, ppl.numberofPeopleSchedule.get).transform_keys(&:to_sym))
      sch_info[:ppl_nom] = ppl.peopleDefinition.getNumberOfPeople(ppl.peopleDefinition.floorArea)
      final_info << sch_info
    end

    final_ppl_nom = final_info.inject(0){|sum,h| sum + h[:ppl_nom]}
    final_ppl_adj = final_info.inject(0){|sum,h| sum + (h[:ppl_nom] * h[:max])}

    runner.registerFinalCondition("Final total nominal occupancy: #{final_ppl_nom}; final peak schedule-adjusted occupancy: #{final_ppl_adj}.")

    return true
  end
end

# register the measure to be used by the application
AdjustOccupancySchedule.new.registerWithApplication
