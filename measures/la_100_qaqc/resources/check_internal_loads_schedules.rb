# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

module OsLib_QAQC
# Check the schedules against template prototypes
#
# @param std [Standard] target standard, Class Standard from openstudio-standards
# @param min_pass_pct [Double] threshold for throwing an error for percent difference
# @param max_pass_pct [Double] threshold for throwing an error for percent difference
  def check_internal_loads_schedules(category, target_standard, min_pass_pct: 0.2, max_pass_pct: 0.2, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Schedules')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check schedules for lighting, ventilation, occupant density, plug loads, and equipment based on DOE reference building schedules in terms of full load hours per year.')

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    std = Standard.build(target_standard)

    begin
      # loop through all space types used in the model
      @model.getSpaceTypes.each do |space_type|
        next if space_type.floorArea <= 0

        # load in standard info for this space type
        data = std.space_type_get_standards_data(space_type)

        if data.nil? || data.empty?

          # skip if all spaces using this space type are plenums
          all_spaces_plenums = true
          space_type.spaces.each do |space|
          unless std.space_plenum?(space)
              all_spaces_plenums = false
            break
            end
          end

        unless all_spaces_plenums
            check_elems << OpenStudio::Attribute.new('flag', "Unexpected standards type for #{space_type.name}, can't validate schedules.")
          end

          next
        end

        # temp model to hold schedules to check
        model_temp = OpenStudio::Model::Model.new

        # check lighting schedules
        data['lighting_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['lighting_per_area'])
        if target_ip.to_f > 0
          schedule_target = std.model_add_schedule(model_temp, data['lighting_schedule'])
          if !schedule_target
            check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['lighting_schedule']} in standards json.")
          elsif !schedule_target.to_ScheduleRuleset.is_initialized
            check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule." )
          else
            schedule_target = schedule_target.to_ScheduleRuleset.get
            # loop through and test individual load instances
            target_hrs = std.schedule_ruleset_annual_equivalent_full_load_hrs(schedule_target)
            space_type.lights.each do |load_inst|
              inst_sch_check = generate_load_insc_sch_check_attribute(target_hrs, load_inst, space_type, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
              if inst_sch_check then check_elems << inst_sch_check end
            end

          end
        end

        # check electric equipment schedules
        data['electric_equipment_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['electric_equipment_per_area'])
        if target_ip.to_f > 0
          schedule_target = std.model_add_schedule(model_temp, data['electric_equipment_schedule'])
          if !schedule_target
            check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['electric_equipment_schedule']} in standards json.")
          elsif !schedule_target.to_ScheduleRuleset.is_initialized
            check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule." )
          else
            schedule_target = schedule_target.to_ScheduleRuleset.get
            # loop through and test individual load instances
            target_hrs = std.schedule_ruleset_annual_equivalent_full_load_hrs(schedule_target)

            space_type.electricEquipment.each do |load_inst|
              inst_sch_check = generate_load_insc_sch_check_attribute(target_hrs, load_inst, space_type, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
              if inst_sch_check then check_elems << inst_sch_check end
            end
          end
        end

        # check gas equipment schedules
      # @todo - update measure test to with space type to check this
        data['gas_equipment_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['gas_equipment_per_area'])
        if target_ip.to_f > 0
          schedule_target = std.model_add_schedule(model_temp, data['gas_equipment_schedule'])
          if !schedule_target
            check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['gas_equipment_schedule']} in standards json.")
          elsif !schedule_target.to_ScheduleRuleset.is_initialized
            check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule." )
          else
          schedule_target = schedule_target.to_ScheduleRuleset.get
            # loop through and test individual load instances
            target_hrs = std.schedule_ruleset_annual_equivalent_full_load_hrs(schedule_target)
            space_type.gasEquipment.each do |load_inst|
              inst_sch_check = generate_load_insc_sch_check_attribute(target_hrs, load_inst, space_type, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
              if inst_sch_check then check_elems << inst_sch_check end
            end
          end
        end

        # check occupancy schedules
        data['occupancy_per_area'].nil? ? (target_ip = 0.0) : (target_ip = data['occupancy_per_area'])
        if target_ip.to_f > 0
          schedule_target = std.model_add_schedule(model_temp, data['occupancy_schedule'])
          if !schedule_target
            check_elems << OpenStudio::Attribute.new('flag', "Didn't find schedule named #{data['occupancy_schedule']} in standards json.")
          elsif !schedule_target.to_ScheduleRuleset.is_initialized
            check_elems << OpenStudio::Attribute.new('flag', "Schedule named #{schedule_target.name} is a #{schedule_target.class}, not a ScheduleRuleset schedule." )
          else
          schedule_target = schedule_target.to_ScheduleRuleset.get
            # loop through and test individual load instances
            target_hrs = std.schedule_ruleset_annual_equivalent_full_load_hrs(schedule_target)
            space_type.people.each do |load_inst|
              inst_sch_check = generate_load_insc_sch_check_attribute(target_hrs, load_inst, space_type, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
              if inst_sch_check then check_elems << inst_sch_check end
            end

          end
        end

      # @todo: check ventilation schedules
      # if objects are in the model should they just be always on schedule, or have a 8760 annual equivalent value
      # oa_schedule should not exist, or if it does shoudl be always on or have 8760 annual equivalent value
        if space_type.designSpecificationOutdoorAir.is_initialized
          oa = space_type.designSpecificationOutdoorAir.get
          if oa.outdoorAirFlowRateFractionSchedule.is_initialized
          # @todo: update measure test to check this
            target_hrs = 8760
            inst_sch_check = generate_load_insc_sch_check_attribute(target_hrs, oa, space_type, std: std, min_pass_pct: min_pass_pct, max_pass_pct: max_pass_pct)
            if inst_sch_check then check_elems << inst_sch_check end
          end
        end

        # notes
        # current logic only looks at 8760 values and not design days
      # when multiple instances of a type currently check every schedule by itself. In future could do weighted avgerage merge
        # not looking at infiltration schedules
        # not looking at luminaires
        # not looking at space loads, only loads at space type
        # only checking schedules where standard shows non zero load value
        # model load for space type where standards doesn't have one wont throw flag about mis-matched schedules
      end

      # warn if there are spaces in model that don't use space type unless they appear to be plenums
      @model.getSpaces.sort.each do |space|
        next if std.space_plenum?(space)
        if !space.spaceType.is_initialized
          check_elems << OpenStudio::Attribute.new('flag', "#{space.name} doesn't have a space type assigned, can't validate schedules.")
        end
      end
    rescue StandardError => e
      # brief description of ruby error
      check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

      # backtrace of ruby error for diagnostic use
      if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
    end

    # add check_elms to new attribute
    check_elem = OpenStudio::Attribute.new('check', check_elems)

    return check_elem
    # note: registerWarning and registerValue will be added for checks downstream using os_lib_reporting_qaqc.rb
  end

  # code for each load instance for different load types will pass through here
  # will return nill or a single attribute
  def generate_load_insc_sch_check_attribute(target_hrs, load_inst, space_type, std: nil, min_pass_pct: 0.2, max_pass_pct: 0.2)
    if std.nil?
      std = Standard.build('90.1-2013')
    end

    # get schedule
    if (load_inst.class.to_s == 'OpenStudio::Model::People') && load_inst.numberofPeopleSchedule.is_initialized
      schedule_inst = load_inst.numberofPeopleSchedule.get
    elsif (load_inst.class.to_s == 'OpenStudio::Model::DesignSpecificationOutdoorAir') && load_inst.outdoorAirFlowRateFractionSchedule.is_initialized
      schedule_inst = load_inst.outdoorAirFlowRateFractionSchedule .get
    elsif load_inst.schedule.is_initialized
      schedule_inst = load_inst.schedule.get
    else
      return OpenStudio::Attribute.new('flag', "#{load_inst.name} in #{space_type.name} doesn't have a schedule assigned.")
    end

    # get annual equiv for model schedule
    if schedule_inst.to_ScheduleRuleset.is_initialized
      inst_hrs = std.schedule_ruleset_annual_equivalent_full_load_hrs(schedule_inst.to_ScheduleRuleset.get)
    elsif schedule_inst.to_ScheduleConstant.is_initialized
      inst_hrs = std.schedule_constant_annual_equivalent_full_load_hrs(schedule_inst.to_ScheduleConstant.get)
    else
      return OpenStudio::Attribute.new('flag', "#{schedule_inst.name} isn't a Ruleset or Constant schedule. Can't calculate annual equivalent full load hours.")
    end

    # check instance against target
    if inst_hrs < target_hrs * (1.0 - min_pass_pct)
      return OpenStudio::Attribute.new('flag', "#{inst_hrs.round} annual equivalent full load hours for #{schedule_inst.name} in #{space_type.name} is more than #{min_pass_pct * 100} (%) below the typical value of #{target_hrs.round} hours from the DOE Prototype building.")
    elsif inst_hrs > target_hrs * (1.0 + max_pass_pct)
      return OpenStudio::Attribute.new('flag', "#{inst_hrs.round} annual equivalent full load hours for #{schedule_inst.name} in #{space_type.name}  is more than #{max_pass_pct * 100} (%) above the typical value of #{target_hrs.round} hours DOE Prototype building.")
    end

    # will get to this if no flag was thrown
    return false
  end
end
