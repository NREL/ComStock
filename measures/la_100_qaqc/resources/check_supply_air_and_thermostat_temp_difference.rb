# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
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
  # Check for excess simulataneous heating and cooling
  #
  # @param max_delta [Double] threshold for throwing an error for temperature difference
  def check_supply_air_and_thermostat_temp_difference(category, target_standard, max_delta: 2.0, name_only: false)
    # G3.1.2.9 requires a 20 degree F delta between supply air temperature and zone temperature.
    target_clg_delta = 20.0

    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Supply and Zone Air Temperature')
    check_elems << OpenStudio::Attribute.new('category', category)
    if @utility_name.nil?
      check_elems << OpenStudio::Attribute.new('description', "Check if fans modeled to ASHRAE 90.1 2013 Section G3.1.2.9 requirements. Compare the supply air temperature for each thermal zone against the thermostat setpoints. Throw flag if temperature difference excedes threshold of #{target_clg_delta}F plus the selected tolerance.")
    else
      check_elems << OpenStudio::Attribute.new('description', "Check if fans modeled to ASHRAE 90.1 2013 Section G3.1.2.9 requirements. Compare the supply air temperature for each thermal zone against the thermostat setpoints. Throw flag if temperature difference excedes threshold set by #{@utility_name}.")
    end

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
      # loop through thermal zones
      @model.getThermalZones.sort.each do |thermal_zone|
        # skip plenums
        next if std.thermal_zone_plenum?(thermal_zone)

        # populate thermostat ranges
        model_clg_min = nil
        if thermal_zone.thermostatSetpointDualSetpoint.is_initialized

          thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
          if thermostat.coolingSetpointTemperatureSchedule.is_initialized

            clg_sch = thermostat.coolingSetpointTemperatureSchedule.get
            schedule_values = nil
            if clg_sch.to_ScheduleRuleset.is_initialized
               schedule_values = std.schedule_ruleset_annual_min_max_value(clg_sch.to_ScheduleRuleset.get)
            elsif clg_sch.to_ScheduleConstant.is_initialized
              schedule_values = std.schedule_constant_annual_min_max_value(clg_sch.to_ScheduleConstant.get)
            end

            unless schedule_values.nil?
              model_clg_min = schedule_values['min']
            end
          end

        else
          # go to next zone if not conditioned
          next

        end

        # flag if there is setpoint schedule can't be inspected (isn't ruleset)
        if model_clg_min.nil?
          check_elems << OpenStudio::Attribute.new('flag', "Can't inspect thermostat schedules for #{thermal_zone.name}")
        else

          # get supply air temps from thermal zone sizing
          sizing_zone = thermal_zone.sizingZone
          clg_supply_air_temp = sizing_zone.zoneCoolingDesignSupplyAirTemperature

          # convert model values to IP
          model_clg_min_ip = OpenStudio.convert(model_clg_min, 'C', 'F').get
          clg_supply_air_temp_ip = OpenStudio.convert(clg_supply_air_temp, 'C', 'F').get

          # check supply air against zone temperature (only check against min setpoint, assume max is night setback)
          if model_clg_min_ip - clg_supply_air_temp_ip > target_clg_delta + max_delta
            check_elems << OpenStudio::Attribute.new('flag', "For #{thermal_zone.name} the delta temp between the cooling supply air temp of #{clg_supply_air_temp_ip.round(2)} (F) and the minimum thermostat cooling temp of #{model_clg_min_ip.round(2)} (F) is more than #{max_delta} (F) larger than the expected delta of #{target_clg_delta} (F)")
          elsif model_clg_min_ip - clg_supply_air_temp_ip < target_clg_delta - max_delta
            check_elems << OpenStudio::Attribute.new('flag', "For #{thermal_zone.name} the delta temp between the cooling supply air temp of #{clg_supply_air_temp_ip.round(2)} (F) and the minimum thermostat cooling temp of #{model_clg_min_ip.round(2)} (F) is more than #{max_delta} (F) smaller than the expected delta of #{target_clg_delta} (F)")
          end

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
end
