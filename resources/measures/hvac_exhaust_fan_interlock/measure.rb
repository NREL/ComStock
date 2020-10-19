# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/


require_relative 'resources/Standards.ScheduleRuleset'
require_relative 'resources/Standards.ScheduleConstant'

# start the measure
class ExhaustFanInterlock < OpenStudio::Ruleset::ModelUserScript

  # human readable name
  def name
    return "Exhaust Fan Interlock"
  end

  # human readable description
  def description
    return "Exhaust fans that are not aligned with schedule of operations of the companion supply fan can impact the airflows of central air handlers by decreasing the flow of return air and sometimes increasing the outdoor air flow rate. A common operational practice is to interlock (or align) the operations of any exhaust fans with the companion system used to condition and pressurize a space. This measure examines all Fan:ZoneExhaust objects present in a model and coordinates the availability of the exhaust fan with the system supply fan. "
  end

  # human readable description of modeling approach
  def modeler_description
    return "For any thermal zones having zone equipment objects of type Fan:ZoneExhaust, this energy efficiency measure (EEM) maps the schedule used to define the availability of the associated Air Loop to the Availability Schedule attribute of the zone exhaust fan object. "
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    return args
  end

  # Method to decide whether or not to change the exhaust fan schedule,
  # in case the new schedule is less aggressive than the existing schedule.
  def compare_eflh(runner, old_sch, new_sch)
    if old_sch.to_ScheduleRuleset.is_initialized
      old_sch = old_sch.to_ScheduleRuleset.get
    elsif old_sch.to_ScheduleConstant.is_initialized
      old_sch = old_sch.to_ScheduleConstant.get
    else
      runner.registerWarning("Can only calculate equivalent full load hours for ScheduleRuleset or ScheduleConstant schedules. #{old_sch.name} is neither.")
      return false
    end

    if new_sch.to_ScheduleRuleset.is_initialized
      new_sch = new_sch.to_ScheduleRuleset.get
    elsif new_sch.to_ScheduleConstant.is_initialized
      new_sch = new_sch.to_ScheduleConstant.get
    else
      runner.registerWarning("Can only calculate equivalent full load hours for ScheduleRuleset or ScheduleConstant schedules. #{new_sch.name} is neither.")
      return false
    end

    new_eflh = new_sch.annual_equivalent_full_load_hrs
    old_eflh = old_sch.annual_equivalent_full_load_hrs
    if new_eflh < old_eflh
      runner.registerInfo("The new exhaust fan schedule, #{new_sch.name} (#{new_eflh.round} EFLH) is more aggressive than the existing schedule #{old_sch.name} (#{old_eflh.round} EFLH).")
      return true
    elsif new_eflh == old_eflh
      runner.registerWarning("The existing exhaust fan schedule, #{old_sch.name} (#{old_eflh.round} EFLH), is equally as aggressive as the new occupancy-tracking schedule #{new_sch.name} (#{new_eflh.round} EFLH).  Not applying new schedule.")
      return false
    elsif
      runner.registerWarning("The existing exhaust fan schedule, #{old_sch.name} (#{old_eflh.round} EFLH), is more aggressive than the new occupancy-tracking schedule #{new_sch.name} (#{new_eflh.round} EFLH).  Not applying new schedule.")
      return false
    end
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if model.getFanZoneExhausts.empty?
      runner.registerAsNotApplicable('The model does not contain exhaust fans.')
      return false
    end

    # assigning the arrays
    air_loops =[]
    exhaust_fans = []
    changed_sch_array_true = []
    changed_sch_array_false = []

    # Loop through all air loops in model
    model.getAirLoopHVACs.each do |air_loop|
      airloops_availability_sch = air_loop.availabilitySchedule
      air_loop.thermalZones.each do |eqip_zn|
        eqip_zn.equipment.each do |exh_fan|
          # Check to see if ZoneHVACEquipment object type = Exhaust Fan, if so map to variable and store in object array
          if exh_fan.to_FanZoneExhaust.is_initialized
            fan_exhaust = exh_fan.to_FanZoneExhaust.get
            exhaust_fans << fan_exhaust
            # Check to see if Exhaust Fan Object has an availability schedule already defined
            if fan_exhaust.availabilitySchedule.is_initialized
              fan_exh_avail_sch = fan_exhaust.availabilitySchedule.get
              # Don't make a change if the schedules are already the same
              if fan_exh_avail_sch == airloops_availability_sch
                runner.registerInfo("Availability Schedule for OS:FanZoneExhaust named: '#{fan_exhaust.name}' was already identical to the HVAC operation schedule, no change was made.")
                changed_sch_array_false << changed_sch
                next
              end
              # Only change the schedule if the new schedules is more aggressive than the existing schedule
              if compare_eflh(runner, fan_exh_avail_sch, airloops_availability_sch)
                #Set availability schedule for current fan exhaust object. NOTE: boolean set method returns true if successful
                changed_sch = fan_exhaust.setAvailabilitySchedule(airloops_availability_sch)
                runner.registerInfo("Availability Schedule for OS:FanZoneExhaust named: '#{fan_exhaust.name}' has been changed to '#{airloops_availability_sch.name}' from '#{fan_exh_avail_sch.name}'.")
                if changed_sch == true
                  changed_sch_array_true << changed_sch
                else
                  changed_sch_array_false << changed_sch
                end
              else
                changed_sch_array_false << changed_sch
              end
            end
          end
        end
      end
    end

    # report initial condition of model
    runner.registerInitialCondition("The initial model contained #{exhaust_fans.length} 'Fan:ZoneExhaust' object for which this measure is applicable.")
    hvac_exh_fan_interlock_num_fans = changed_sch_array_true.length
    # report final condition of model
    runner.registerFinalCondition("The Availability Schedules for #{changed_sch_array_true.length} 'Fan:ZoneExhaust' schedule(s) were altered to match the availability schedules of supply fans. The number of unchanged 'Fan: ZoneExhaust' object(s) = #{changed_sch_array_false.length}.")
    runner.registerValue('hvac_exh_fan_interlock_num_fans', hvac_exh_fan_interlock_num_fans)

    return true
  end
end

# register the measure to be used by the application
ExhaustFanInterlock.new.registerWithApplication
