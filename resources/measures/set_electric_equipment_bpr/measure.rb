# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class SetElectricEquipmentBPR < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Set Electric Equipment BPR'
  end

  # human readable description
  def description
    return ''
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Find all of the electronic equipment schedules in the building, and adjust to a user-specified base-to-peak ratio (BPR).'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Boolean argument indicating whether the weekday BPR is implemented
    modify_wkdy_bpr = OpenStudio::Measure::OSArgument.makeBoolArgument('modify_wkdy_bpr', true)
    modify_wkdy_bpr.setDefaultValue(false)
    args << modify_wkdy_bpr

    # Double argument to assign weekday BPR
    wkdy_bpr = OpenStudio::Measure::OSArgument.makeDoubleArgument('wkdy_bpr', true)
    wkdy_bpr.setDefaultValue(0.5)
    args << wkdy_bpr

    # Boolean argument indicating whether the weekend BPR is implemented
    modify_wknd_bpr = OpenStudio::Measure::OSArgument.makeBoolArgument('modify_wknd_bpr', true)
    modify_wknd_bpr.setDefaultValue(false)
    args << modify_wknd_bpr

    # Choice argument to select which weekend BPR to implement
    wknd_bpr = OpenStudio::Measure::OSArgument.makeDoubleArgument('wknd_bpr', true)
    wknd_bpr.setDefaultValue(0.5)
    args << wknd_bpr

    return args
  end

  # Method to find schedule transition points and adjust base values based on specified BPR.
  def set_sch_bpr(runner, day_sch, bpr, modify_wknd_bpr = nil, new_wkdy_base = nil)
    # skip schedules that are a constant value throughout the day
    if day_sch.values.length == 1
      runner.registerWarning("Rule '#{day_sch.name}' is a constant value throughout the day and won't be altered by this measure.")
      return 1
    end

    vals = day_sch.values
    times = day_sch.times
    peak = vals.max
    base = vals.min
    new_base = bpr * peak
    # if the new wknd base value is higher than the wkdy base value, adjust it
    if modify_wknd_bpr && (new_wkdy_base < new_base)
      new_base = new_wkdy_base
    end
    sf = (new_base - base) / (peak - base)
    new_vals = []
    new_times = []
    # if the new base value is greater than the peak, shift whole schedule up
    if peak < new_base
      new_vals = vals + (new_base - base)
      new_times = times
    else
      vals.zip(times).each_with_index do |val_time, j|
        val = val_time[0]
        time = val_time[1]
        new_val = ((peak - val) * sf) + val
        if new_val < 0.0
          new_val = 0.0
        end
        new_vals << new_val
        new_times << time
      end
    end

    # set new time/value pairs in schedule
    day_sch.clearValues
    new_vals.zip(new_times).each do |val, time|
      day_sch.addValue(time, val)
    end
    return day_sch.values.min
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    unless runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables
    modify_wkdy_bpr = runner.getBoolArgumentValue('modify_wkdy_bpr', user_arguments)
    wkdy_bpr = runner.getDoubleArgumentValue('wkdy_bpr', user_arguments)
    modify_wknd_bpr = runner.getBoolArgumentValue('modify_wknd_bpr', user_arguments)
    wknd_bpr = runner.getDoubleArgumentValue('wknd_bpr', user_arguments)

    # return not applicable if the user-specified BPR is 'NA' for weekend and weekday schedules
    if !modify_wkdy_bpr && !modify_wknd_bpr
      runner.registerAsNotApplicable("BPR is set to 'NA' for weekdays and weekends. This measure is not applicable.")
      return false
    end

    original_equip_schs = []
    selected_equip_instances = []
    # loop through space types
    model.getSpaceTypes.each do |space_type|
      # skip if not used in model
      next if space_type.spaces.empty?

      # confirm space type maps to a recognized standards type
      next unless space_type.standardsBuildingType.is_initialized
      next unless space_type.standardsSpaceType.is_initialized

      standards_building_type = space_type.standardsBuildingType.get
      standards_space_type = space_type.standardsSpaceType.get
      space_type_hash = {}
      space_type_hash[space_type] = [standards_building_type,
                                     standards_space_type]

      # get all electric equipment schedules in space types
      space_type.electricEquipment.each do |equip|
        selected_equip_instances << equip
        if equip.schedule.is_initialized
          equip_sch = equip.schedule.get
          original_equip_schs << equip_sch
        end
      end
    end

    # return not applicable if the model has no electric equipment schedules
    if original_equip_schs.empty?
      runner.registerAsNotApplicable('There are no electric equipment schedules in the model. This measure is not applicable.')
      return false
    end

    # loop through the unique list of electric equipment schedules, adjusting peak value based on user-specified BPR
    original_equip_new_schs = {}
    original_equip_schs.uniq.each do |equip_sch|
      # guard clause for ScheduleRulesets
      unless equip_sch.to_ScheduleRuleset.is_initialized
        runner.registerWarning("Schedule '#{equip_sch.name}' isn't a ScheduleRuleset object and won't be altered by this measure.")
        next
      end

      # guard clause for already altered schedules
      if original_equip_new_schs.key?(equip_sch)
        next
      end

      # adjust schedule to meet user-specified BPR value
      new_equip_sch = equip_sch.clone(model).to_ScheduleRuleset.get
      new_equip_sch.setName("#{equip_sch.name} BPR Adjusted")
      new_equip_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
      original_equip_new_schs[equip_sch] = new_equip_sch
      new_equip_sch.to_ScheduleRuleset.get

      if modify_wkdy_bpr
        new_wkdy_base_values = []
        # adjust default day schedules
        if new_equip_sch.scheduleRules.empty?
          runner.registerWarning("Schedule '#{new_equip_sch.name}' applies to all days.  It has been treated as a Weekday schedule.")
        end
        new_wkdy_base_values << set_sch_bpr(runner, new_equip_sch.defaultDaySchedule, wkdy_bpr)

        # adjust weekdays
        new_equip_sch.scheduleRules.each do |sch_rule|
          if sch_rule.applyMonday || sch_rule.applyTuesday || sch_rule.applyWednesday || sch_rule.applyThursday || sch_rule.applyFriday
            new_wkdy_base_values << set_sch_bpr(runner, sch_rule.daySchedule, wkdy_bpr)
          end
        end
      end
      # find minimum weekday base value
      min_wkdy_base_value = new_wkdy_base_values.min

      if modify_wknd_bpr
        # adjust weekends
        new_equip_sch.scheduleRules.each do |sch_rule|
          if sch_rule.applySaturday || sch_rule.applySunday
            if sch_rule.applyMonday || sch_rule.applyTuesday || sch_rule.applyWednesday || sch_rule.applyThursday || sch_rule.applyFriday
              runner.registerWarning("Rule '#{sch_rule.name}' for schedule '#{new_equip_sch.name}' applies to both Weekends and Weekdays.  It has been treated as a Weekday schedule.")
            else
              set_sch_bpr(runner, sch_rule.daySchedule, wknd_bpr, modify_wknd_bpr = modify_wknd_bpr, new_wkdy_base = min_wkdy_base_value)
            end
          end
        end
      end
    end

    # loop through all electric equipment instances, replacing old electric equipment schedules with the BPR-adjusted schedules
    selected_equip_instances.each do |equip|
      if equip.schedule.empty?
        runner.registerWarning("There was no schedule assigned for the electric equipment object named '#{equip.name}. No schedule was added.")
      else
        old_equip_sch = equip.schedule.get
        equip.setSchedule(original_equip_new_schs[old_equip_sch])
        runner.registerInfo("Schedule for the electric equipment object named '#{equip.name}' was adjusted during base hours.")
      end
    end
    return true
  end
end

# register the measure to be used by the application
SetElectricEquipmentBPR.new.registerWithApplication
