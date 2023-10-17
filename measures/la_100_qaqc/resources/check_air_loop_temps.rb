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
  # Check the air loop and zone operational vs. sizing temperatures and make sure everything is coordinated.
  # This identifies problems caused by sizing to one set of conditions and operating at a different set.
  #
  # @param max_sizing_temp_delta [Double] threshold for throwing an error for design sizing temperatures
  # @param max_operating_temp_delta [Double] threshold for throwing an error on operating temperatures
  def check_air_loop_temps(category, max_sizing_temp_delta: 2.0, max_operating_temp_delta: 5.0, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Air System Temperatures')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check that air system sizing and operation temperatures are coordinated.')

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    # get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    @sql.availableEnvPeriods.each do |env_pd|
      env_type = @sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
          break
        end
      end
    end

    # only try to get the annual timeseries if an annual simulation was run
    if ann_env_pd.nil?
      check_elems << OpenStudio::Attribute.new('flag', 'Cannot find the annual simulation run period, cannot check equipment part load ratios.')
      return check_elems
    end

    begin
      @model.getAirLoopHVACs.sort.each do |air_loop|
        supply_outlet_node_name = air_loop.supplyOutletNode.name.to_s
        design_cooling_sat = air_loop.sizingSystem.centralCoolingDesignSupplyAirTemperature
        design_cooling_sat = OpenStudio.convert(design_cooling_sat, 'C', 'F').get
        design_heating_sat = air_loop.sizingSystem.centralHeatingDesignSupplyAirTemperature
        design_heating_sat = OpenStudio.convert(design_heating_sat, 'C', 'F').get

        # check if the system is a unitary system
        is_unitary_system = air_loop_hvac_unitary_system?(air_loop)
        is_direct_evap = air_loop_hvac_direct_evap?(air_loop)

        if is_unitary_system && !is_direct_evap
          unitary_system_name = nil
          unitary_system_type = '<unspecified>'
          unitary_min_temp_f = nil
          unitary_max_temp_f = nil
          air_loop.supplyComponents.each do |component|
            obj_type = component.iddObjectType.valueName.to_s
            case obj_type
            when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
              unitary_system_name = component.name.to_s
              unitary_system_type = obj_type
              unitary_system_temps = unitary_system_min_max_value(component)
              unitary_min_temp_f = unitary_system_temps[0]
              unitary_max_temp_f = unitary_system_temps[1]
            end
          end
          # set expected minimums for operating temperatures
          expected_min = unitary_min_temp_f.nil? ? design_cooling_sat : [design_cooling_sat, unitary_min_temp_f].min
          expected_max = unitary_max_temp_f.nil? ? design_heating_sat : [design_heating_sat, unitary_max_temp_f].max
        else
          # get setpoint manager
          spm_name = nil
          spm_type = '<unspecified>'
          spm_min_temp_f = nil
          spm_max_temp_f = nil
          @model.getSetpointManagers.each do |spm|
            if spm.setpointNode.is_initialized
              spm_node = spm.setpointNode.get
              if spm_node.name.to_s == supply_outlet_node_name
                spm_name = spm.name
                spm_type = spm.iddObjectType.valueName.to_s
                spm_temps_f = setpoint_manager_min_max_value(spm)
                spm_min_temp_f = spm_temps_f[0]
                spm_max_temp_f = spm_temps_f[1]
                break
              end
            end
          end

          # check setpoint manager temperatures against design temperatures
          if spm_min_temp_f
            if (spm_min_temp_f - design_cooling_sat).abs > max_sizing_temp_delta
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_cooling_sat.round(1)}F design cooling supply air temperature, but the setpoint manager operates down to #{spm_min_temp_f.round(1)}F." )
            end
          end
          if spm_max_temp_f
            if (spm_max_temp_f - design_heating_sat).abs > max_sizing_temp_delta
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_heating_sat.round(1)}F design heating supply air temperature, but the setpoint manager operates up to #{spm_max_temp_f.round(1)}F." )
            end
          end

          # set expected minimums for operating temperatures
          expected_min = spm_min_temp_f.nil? ? design_cooling_sat : [design_cooling_sat, spm_min_temp_f].min
          expected_max = spm_max_temp_f.nil? ? design_heating_sat : [design_heating_sat, spm_max_temp_f].max

          # check zone sizing temperature against air loop design temperatures
          air_loop.thermalZones.each do |zone|
            # if this zone has a reheat terminal, get the reheat temp for comparison
            reheat_op_f = nil
            reheat_zone = false
            zone.equipment.each do |equip|
              obj_type = equip.iddObjectType.valueName.to_s
              case obj_type
              when 'OS_AirTerminal_SingleDuct_ConstantVolume_Reheat'
                term = equip.to_AirTerminalSingleDuctConstantVolumeReheat.get
                reheat_op_f = OpenStudio.convert(term.maximumReheatAirTemperature, 'C', 'F').get
                reheat_zone = true
              when 'OS_AirTerminal_SingleDuct_VAV_HeatAndCool_Reheat'
                term = equip.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.get
                reheat_op_f = OpenStudio.convert(term.maximumReheatAirTemperature, 'C', 'F').get
                reheat_zone = true
              when 'OS_AirTerminal_SingleDuct_VAV_Reheat'
                term = equip.to_AirTerminalSingleDuctVAVReheat.get
                reheat_op_f = OpenStudio.convert(term.maximumReheatAirTemperature, 'C', 'F').get
                reheat_zone = true
              when 'OS_AirTerminal_SingleDuct_ParallelPIU_Reheat'
                # reheat_op_f = # Not an OpenStudio input
                reheat_zone = true
              when 'OS_AirTerminal_SingleDuct_SeriesPIU_Reheat'
                # reheat_op_f = # Not an OpenStudio input
                reheat_zone = true
              end
            end

            # get the zone heating and cooling SAT for sizing
            sizing_zone = zone.sizingZone
            zone_siz_htg_f = OpenStudio.convert(sizing_zone.zoneHeatingDesignSupplyAirTemperature, 'C', 'F').get
            zone_siz_clg_f = OpenStudio.convert(sizing_zone.zoneCoolingDesignSupplyAirTemperature, 'C', 'F').get

            # check cooling temperatures
            if (design_cooling_sat - zone_siz_clg_f).abs > max_sizing_temp_delta
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_cooling_sat.round(1)}F design cooling supply air temperature but the sizing for zone #{zone.name} uses a cooling supply air temperature of #{zone_siz_clg_f.round(1)}F." )
            end

            # check heating temperatures
            if reheat_zone && reheat_op_f
              if (reheat_op_f - zone_siz_htg_f).abs > max_sizing_temp_delta
                check_elems << OpenStudio::Attribute.new('flag', "Minor Error: For zone '#{zone.name}', the reheat air temperature is set to #{reheat_op_f.round(1)}F, but the sizing for the zone is done with a heating supply air temperature of #{zone_siz_htg_f.round(1)}F." )
              end
            elsif reheat_zone && !reheat_op_f
              # reheat zone but no reheat temperature available from terminal object
            elsif (design_heating_sat - zone_siz_htg_f).abs > max_sizing_temp_delta
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: Air loop '#{air_loop.name}' sizing uses a #{design_heating_sat.round(1)}F design heating supply air temperature but the sizing for zone #{zone.name} uses a heating supply air temperature of #{zone_siz_htg_f.round(1)}F." )
            end
          end
        end

        # get supply air temperatures for supply outlet node
        supply_temp_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Temperature', supply_outlet_node_name)
        if supply_temp_timeseries.empty?
          check_elems << OpenStudio::Attribute.new('flag', "Warning: No supply node temperature timeseries found for '#{air_loop.name}'" )
          next
        else
          # convert to ruby array
          temperatures = []
          supply_temp_vector = supply_temp_timeseries.get.values
          for i in (0..supply_temp_vector.size - 1)
            temperatures << supply_temp_vector[i]
          end
        end

        # get supply air flow rates for supply outlet node
        supply_flow_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Standard Density Volume Flow Rate', supply_outlet_node_name)
        if supply_flow_timeseries.empty?
          check_elems << OpenStudio::Attribute.new('flag', "Warning: No supply node temperature timeseries found for '#{air_loop.name}'" )
          next
        else
          # convert to ruby array
          flowrates = []
          supply_flow_vector = supply_flow_timeseries.get.values
          for i in (0..supply_flow_vector.size - 1)
            flowrates << supply_flow_vector[i]
          end
        end
        # check reasonableness of supply air temperatures when supply air flow rate is operating
        flow_tolerance = OpenStudio.convert(10.0, 'cfm', 'm^3/s').get
        operating_temperatures = temperatures.select.with_index { |_t, k| flowrates[k] > flow_tolerance }
        operating_temperatures = operating_temperatures.map { |t| (t * 1.8 + 32.0) }

        next if operating_temperatures.empty?

        runtime_fraction = operating_temperatures.size.to_f / temperatures.size
        temps_out_of_bounds = operating_temperatures.select { |t| ((t < 40.0) || (t > 110.0) || ((t + max_operating_temp_delta) < expected_min) || ((t - max_operating_temp_delta) > expected_max)) }

        next if temps_out_of_bounds.empty?

        min_op_temp_f = temps_out_of_bounds.min
        max_op_temp_f = temps_out_of_bounds.max
        # avg_F = temps_out_of_bounds.inject(:+).to_f / temps_out_of_bounds.size
        err = []
        err << "Major Error:"
        err << "Expected supply air temperatures out of bounds for air loop '#{air_loop.name}'"
        err << "with #{design_cooling_sat.round(1)}F design cooling SAT"
        err << "and #{design_heating_sat.round(1)}F design heating SAT."
        unless is_unitary_system && !is_direct_evap
          err << "Air loop setpoint manager '#{spm_name}' of type '#{spm_type}' with a"
          err << "#{spm_min_temp_f.round(1)}F minimum setpoint temperature and"
          err << "#{spm_max_temp_f.round(1)}F maximum setpoint temperature."
        end
        if is_unitary_system && !is_direct_evap
          err << "Unitary system '#{unitary_system_name}' of type '#{unitary_system_type}' with"
          temp_str = unitary_min_temp_f.nil? ? "no" : "#{unitary_min_temp_f.round(1)}F"
          err << "#{temp_str} minimum setpoint temperature and"
          temp_str = unitary_max_temp_f.nil? ? "no" : "#{unitary_max_temp_f.round(1)}F"
          err << "#{temp_str} maximum setpoint temperature."
        end
        err << "Out of #{operating_temperatures.size}/#{temperatures.size} (#{(runtime_fraction * 100.0).round(1)}%) operating supply air temperatures"
        err << "#{temps_out_of_bounds.size}/#{operating_temperatures.size} (#{((temps_out_of_bounds.size.to_f / operating_temperatures.size) * 100.0).round(1)}%)"
        err << "are out of bounds with #{min_op_temp_f.round(1)}F min and #{max_op_temp_f.round(1)}F max."
        check_elems << OpenStudio::Attribute.new('flag', err.join(' ').gsub(/\n/, "") )
      end
    rescue StandardError => e
      # brief description of ruby error
      check_elems << OpenStudio::Attribute.new('flag', "Major Error: Error prevented QAQC check from running (#{e}).")

      # backtrace of ruby error for diagnostic use
      if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
    end

    # add check_elms to new attribute
    check_elem = OpenStudio::Attribute.new('check', check_elems)

    return check_elem
    # note: registerWarning and registerValue will be added for checks downstream using os_lib_reporting_qaqc.rb
  end

  # Get the min and max setpoint values for a setpoint manager
  #
  # @param spm [<OpenStudio::Model::SetpointManager>] OpenStudio SetpointManager object
  # @return [Array] An array of doubles [minimum temperature, maximum temperature] in degrees Fahrenheit
  def setpoint_manager_min_max_value(spm)
    # use @standard to not build each time
    std = Standard.build('90.1-2013') # unused; just to access methods
    # Determine the min and max design temperatures
    loop_op_min_f = nil
    loop_op_max_f = nil
    obj_type = spm.iddObjectType.valueName.to_s
    case obj_type
    when 'OS_SetpointManager_Scheduled'
      sch = spm.to_SetpointManagerScheduled.get.schedule
      if sch.to_ScheduleRuleset.is_initialized
        min_c = std.schedule_ruleset_annual_min_max_value(sch.to_ScheduleRuleset.get)['min']
        max_c = std.schedule_ruleset_annual_min_max_value(sch.to_ScheduleRuleset.get)['max']
      elsif sch.to_ScheduleConstant.is_initialized
        min_c = std.schedule_constant_annual_min_max_value(sch.to_ScheduleConstant.get)['min']
        max_c = std.schedule_constant_annual_min_max_value(sch.to_ScheduleConstant.get)['max']
      else
        OpenStudio::logFree(OpenStudio::Error, 'openstudio.model.Model', "Could not find min and max values for #{obj_type} Setpoint Manager.")
      end
      loop_op_min_f = OpenStudio.convert(min_c, 'C', 'F').get
      loop_op_max_f = OpenStudio.convert(max_c, 'C', 'F').get
    when 'OS_SetpointManager_SingleZone_Reheat'
      spm = spm.to_SetpointManagerSingleZoneReheat.get
      loop_op_min_f = OpenStudio.convert(spm.minimumSupplyAirTemperature, 'C', 'F').get
      loop_op_max_f = OpenStudio.convert(spm.maximumSupplyAirTemperature, 'C', 'F').get
    when 'OS_SetpointManager_Warmest'
      spm = spm.to_SetpointManagerWarmest.get
      loop_op_min_f = OpenStudio.convert(spm.minimumSetpointTemperature, 'C', 'F').get
      loop_op_max_f = OpenStudio.convert(spm.maximumSetpointTemperature, 'C', 'F').get
    when 'OS_SetpointManager_WarmestTemperatureFlow'
      spm = spm.to_SetpointManagerWarmestTemperatureFlow.get
      loop_op_min_f = OpenStudio.convert(spm.minimumSetpointTemperature, 'C', 'F').get
      loop_op_max_f = OpenStudio.convert(spm.maximumSetpointTemperature, 'C', 'F').get
    when 'OS_SetpointManager_Scheduled_DualSetpoint'
      spm = spm.to_SetpointManagerScheduledDualSetpoint.get
      # Lowest setpoint is minimum of low schedule
      low_sch = spm.lowSetpointSchedule
      unless low_sch.empty?
        low_sch = low_sch.get
        min_c = nil
        if low_sch.to_ScheduleRuleset.is_initialized
          min_c = std.schedule_ruleset_annual_min_max_value(low_sch.to_ScheduleRuleset.get)['min']
        elsif low_sch.to_ScheduleConstant.is_initialized
          min_c = std.schedule_constant_annual_min_max_value(low_sch.to_ScheduleConstant.get)['min']
        else
          OpenStudio::logFree(OpenStudio::Error, 'openstudio.model.Model', "Could not find min and max values for #{obj_type} Setpoint Manager.")
        end
        loop_op_min_f = OpenStudio.convert(min_c, 'C', 'F').get unless min_c.nil?
      end

      # highest setpoint it maximum of high schedule
      high_sch = spm.highSetpointSchedule
      unless high_sch.empty?
        high_sch = high_sch.get
        max_c = nil
        if high_sch.to_ScheduleRuleset.is_initialized
          max_c = std.schedule_ruleset_annual_min_max_value(high_sch.to_ScheduleRuleset.get)['max']
        elsif high_sch.to_ScheduleConstant.is_initialized
          max_c = std.schedule_constant_annual_min_max_value(high_sch.to_ScheduleConstant.get)['max']
        else
          OpenStudio::logFree(OpenStudio::Error, 'openstudio.model.Model', "Could not find min and max values for #{obj_type} Setpoint Manager.")
        end
        loop_op_max_f = OpenStudio.convert(max_c, 'C', 'F').get unless max_c.nil?
      end
    when 'OS_SetpointManager_OutdoorAirReset'
      spm = spm.to_SetpointManagerOutdoorAirReset.get
      temp_1_f = OpenStudio.convert(spm.setpointatOutdoorHighTemperature, 'C', 'F').get
      temp_2_f = OpenStudio.convert(spm.setpointatOutdoorLowTemperature, 'C', 'F').get
      loop_op_min_f = [temp_1_f, temp_2_f].min
      loop_op_max_f = [temp_1_f, temp_2_f].max
    when 'OS_SetpointManager_FollowOutdoorAirTemperature'
      spm = spm.to_SetpointManagerFollowOutdoorAirTemperature.get
      loop_op_min_f = OpenStudio.convert(spm.minimumSetpointTemperature, 'C', 'F').get
      loop_op_max_f = OpenStudio.convert(spm.maximumSetpointTemperature, 'C', 'F').get
    else
      OpenStudio::logFree(OpenStudio::Error, 'openstudio.model.Model', "Could not find min and max values for #{obj_type} Setpoint Manager.")
    end

    return [loop_op_min_f, loop_op_max_f]
  end


  # Returns whether air loop HVAC is a direct evaporative system
  #
  # @param air_loop [<OpenStudio::Model::AirLoopHVAC>] OpenStudio AirLoopHVAC object
  # @return [Bool] returns true if successful, false if not
  def air_loop_hvac_direct_evap?(air_loop)
    # check if direct evap
    is_direct_evap = false
    air_loop.supplyComponents.each do |component|
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial'
        is_direct_evap = true
      end
    end
    return is_direct_evap
  end

  # Returns whether air loop HVAC is a unitary system
  #
  # @param air_loop [<OpenStudio::Model::AirLoopHVAC>] OpenStudio AirLoopHVAC object
  # @return [Bool] returns true if successful, false if not
  def air_loop_hvac_unitary_system?(air_loop)
    # check if unitary system
    is_unitary_system = false
    air_loop.supplyComponents.each do |component|
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        is_unitary_system = true
      end
    end
    return is_unitary_system
  end

  # Returns the unitary system minimum and maximum design temperatures
  #
  # # @param unitary_system [<OpenStudio::Model::ModelObject>] OpenStudio ModelObject object
  # @return [Array] An array of doubles [minimum temperature, maximum temperature] in degrees Fahrenheit
  def unitary_system_min_max_value(unitary_system)
    min_temp = nil
    max_temp = nil
    # Get the object type
    obj_type = unitary_system.iddObjectType.valueName.to_s
    case obj_type
    when 'OS_AirLoopHVAC_UnitarySystem'
      unitary_system = unitary_system.to_AirLoopHVACUnitarySystem.get
      if unitary_system.useDOASDXCoolingCoil
        min_temp = OpenStudio.convert(unitary_system.dOASDXCoolingCoilLeavingMinimumAirTemperature, 'C', 'F').get
      end
      if unitary_system.maximumSupplyAirTemperature.is_initialized
        max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperature.get, 'C', 'F').get
      end
    when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
      unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
      if unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.is_initialized
        max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.get, 'C', 'F').get
      end
    when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
      unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
      if unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.is_initialized
        max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.get, 'C', 'F').get
      end
    when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
      unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
      min_temp = OpenStudio.convert(unitary_system.minimumOutletAirTemperatureDuringCoolingOperation, 'C', 'F').get
      max_temp = OpenStudio.convert(unitary_system.maximumOutletAirTemperatureDuringHeatingOperation, 'C', 'F').get
    end

    return [min_temp, max_temp]
  end

end
