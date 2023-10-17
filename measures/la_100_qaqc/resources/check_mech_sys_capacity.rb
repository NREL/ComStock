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
  # Check mechanical equipment capacity against rules of thumb sizing
  #
  # @param target_standard [Standard] target standard, Class Standard from openstudio-standards
  def check_mech_sys_capacity(category, target_standard, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Capacity')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check HVAC capacity against ASHRAE rules of thumb for chiller max flow rate, air loop max flow rate, air loop cooling capciaty, and zone heating capcaity. Zone heating check will skip thermal zones without any exterior exposure, and thermal zones that are not conditioned.')

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    std = Standard.build(target_standard)

    # Sizing benchmarks.  Each option has a target value, min and max fractional tolerance, and units.
    # In the future climate zone specific targets may be in standards
    sizing_benchmarks = {}
    sizing_benchmarks['chiller_max_flow_rate'] = { 'min_error' => 1.5, 'min_warning' => 2.0, 'max_warning' => 3.0, 'max_error' => 3.5, 'units' => 'gal/ton*min' }
    sizing_benchmarks['air_loop_max_flow_rate'] = { 'min_error' => 0.2, 'min_warning' => 0.5, 'max_warning' => 2.0, 'max_error' => 4.0, 'units' => 'cfm/ft^2' }
    sizing_benchmarks['air_loop_cooling_capacity'] = { 'min_error' => 200.0, 'min_warning' => 300.0, 'max_warning' => 1500.0, 'max_error' => 2000.0, 'units' => 'ft^2/ton' }
    sizing_benchmarks['zone_heating_capacity'] = { 'min_error' => 4.0, 'min_warning' => 8.0, 'max_warning' => 30.0, 'max_error' => 60.0, 'units' => 'Btu/ft^2*h' }

    begin
      # check max flow rate of chillers in model
      @model.getPlantLoops.sort.each do |plant_loop|
        # next if no chiller on plant loop
        chillers = []
        plant_loop.supplyComponents.each do |sc|
          if sc.to_ChillerElectricEIR.is_initialized
            chillers << sc.to_ChillerElectricEIR.get
          end
        end
        next if chillers.empty?

        # gather targets for chiller capacity
        chiller_max_flow_rate_min_error = sizing_benchmarks['chiller_max_flow_rate']['min_error']
        chiller_max_flow_rate_min_warning = sizing_benchmarks['chiller_max_flow_rate']['min_warning']
        chiller_max_flow_rate_max_warning = sizing_benchmarks['chiller_max_flow_rate']['max_warning']
        chiller_max_flow_rate_max_error = sizing_benchmarks['chiller_max_flow_rate']['max_error']
        chiller_max_flow_rate_units_ip = options['chiller_max_flow_rate']['units']

        # get capacity of loop (not individual chiller but entire loop)
        total_cooling_capacity_w = std.plant_loop_total_cooling_capacity(plant_loop)
        total_cooling_capacity_ton = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/h').get / 12_000.0

        # get the max flow rate (not individual chiller)
        maximum_loop_flow_rate = std.plant_loop_find_maximum_loop_flow_rate(plant_loop)
        maximum_loop_flow_rate_ip = OpenStudio.convert(maximum_loop_flow_rate, 'm^3/s', 'gal/min').get

        if total_cooling_capacity_ton < 0.01
          check_elems <<  OpenStudio::Attribute.new('flag', "Cooling capacity for #{plant_loop.name.get} is too small for flow rate #{maximum_loop_flow_rate_ip.round(2)} gal/min." )
        end

        # calculate the flow per tons of cooling
        model_flow_rate_per_ton_cooling_ip = maximum_loop_flow_rate_ip / total_cooling_capacity_ton

        # check flow rate per capacity
        if model_flow_rate_per_ton_cooling_ip < chiller_max_flow_rate_min_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is below #{chiller_max_flow_rate_min_error.round(2)} #{chiller_max_flow_rate_units_ip}." )
        elsif model_flow_rate_per_ton_cooling_ip < chiller_max_flow_rate_min_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is below #{chiller_max_flow_rate_min_warning.round(2)} #{chiller_max_flow_rate_units_ip}." )
        elsif model_flow_rate_per_ton_cooling_ip > chiller_max_flow_rate_max_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is above #{chiller_max_flow_rate_max_warning.round(2)} #{chiller_max_flow_rate_units_ip}." )
        elsif model_flow_rate_per_ton_cooling_ip > chiller_max_flow_rate_max_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_flow_rate_per_ton_cooling_ip.round(2)} #{chiller_max_flow_rate_units_ip} for #{plant_loop.name.get} is above #{chiller_max_flow_rate_max_error.round(2)} #{chiller_max_flow_rate_units_ip}." )
        end
      end

      # loop through air loops to get max flow rate and cooling capacity.
      @model.getAirLoopHVACs.sort.each do |air_loop|
        # skip DOAS systems for now
        sizing_system = air_loop.sizingSystem
        next if sizing_system.typeofLoadtoSizeOn.to_s == 'VentilationRequirement'

        # gather argument sizing_benchmarks for air_loop_max_flow_rate checks
        air_loop_max_flow_rate_min_error = sizing_benchmarks['air_loop_max_flow_rate']['min_error']
        air_loop_max_flow_rate_min_warning = sizing_benchmarks['air_loop_max_flow_rate']['min_warning']
        air_loop_max_flow_rate_max_warning = sizing_benchmarks['air_loop_max_flow_rate']['max_warning']
        air_loop_max_flow_rate_max_error = sizing_benchmarks['air_loop_max_flow_rate']['max_error']
        air_loop_max_flow_rate_units_ip = sizing_benchmarks['air_loop_max_flow_rate']['units']

        # get values from model for air loop checks
        floor_area_served = std.air_loop_hvac_floor_area_served(air_loop)
        design_supply_air_flow_rate = std.air_loop_hvac_find_design_supply_air_flow_rate(air_loop)

        # check max flow rate of air loops in the model
        model_normalized_flow_rate_si = design_supply_air_flow_rate / floor_area_served
        model_normalized_flow_rate_ip = OpenStudio.convert(model_normalized_flow_rate_si, 'm^3/m^2*s', air_loop_max_flow_rate_units_ip).get
        if model_normalized_flow_rate_ip < air_loop_max_flow_rate_min_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is below #{air_loop_max_flow_rate_min_error.round(2)} #{air_loop_max_flow_rate_units_ip}." )
        elsif model_normalized_flow_rate_ip < air_loop_max_flow_rate_min_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is below #{air_loop_max_flow_rate_min_warning.round(2)} #{air_loop_max_flow_rate_units_ip}." )
        elsif model_normalized_flow_rate_ip > air_loop_max_flow_rate_max_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Warning: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is above #{air_loop_max_flow_rate_max_warning.round(2)} #{air_loop_max_flow_rate_units_ip}." )
        elsif model_normalized_flow_rate_ip > air_loop_max_flow_rate_max_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Error: Flow Rate of #{model_normalized_flow_rate_ip.round(2)} #{air_loop_max_flow_rate_units_ip} for #{air_loop.name.get} is above #{air_loop_max_flow_rate_max_error.round(2)} #{air_loop_max_flow_rate_units_ip}." )
        end
      end

      # loop through air loops to get max flow rate and cooling capacity.
      @model.getAirLoopHVACs.sort.each do |air_loop|
        # check if DOAS, don't check airflow or cooling capacity if it is
        sizing_system = air_loop.sizingSystem
        next if sizing_system.typeofLoadtoSizeOn.to_s == 'VentilationRequirement'

        # gather argument options for air_loop_cooling_capacity checks
        air_loop_cooling_capacity_min_error = sizing_benchmarks['air_loop_cooling_capacity']['min_error']
        air_loop_cooling_capacity_min_warning = sizing_benchmarks['air_loop_cooling_capacity']['min_warning']
        air_loop_cooling_capacity_max_warning = sizing_benchmarks['air_loop_cooling_capacity']['max_warning']
        air_loop_cooling_capacity_max_error = sizing_benchmarks['air_loop_cooling_capacity']['max_error']
        air_loop_cooling_capacity_units_ip = sizing_benchmarks['air_loop_cooling_capacity']['units']

        # check cooling capacity of air loops in the model
        floor_area_served = std.air_loop_hvac_floor_area_served(air_loop)
        capacity = std.air_loop_hvac_total_cooling_capacity(air_loop)
        model_normalized_capacity_si = capacity / floor_area_served
        model_normalized_capacity_ip = OpenStudio.convert(model_normalized_capacity_si, 'W/m^2', 'Btu/ft^2*h').get / 12_000.0

        # want to display in tons/ft^2 so invert number and display for checks
        model_tons_per_area_ip = 1.0 / model_normalized_capacity_ip
        if model_tons_per_area_ip < air_loop_cooling_capacity_min_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is below #{air_loop_cooling_capacity_min_error.round} #{air_loop_cooling_capacity_units_ip}." )
        elsif model_tons_per_area_ip < air_loop_cooling_capacity_min_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is below #{air_loop_cooling_capacity_min_warning.round} #{air_loop_cooling_capacity_units_ip}." )
        elsif model_tons_per_area_ip > air_loop_cooling_capacity_max_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is above #{air_loop_cooling_capacity_max_warning.round} #{air_loop_cooling_capacity_units_ip}." )
        elsif model_tons_per_area_ip > air_loop_cooling_capacity_max_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Cooling Capacity of #{model_tons_per_area_ip.round} #{air_loop_cooling_capacity_units_ip} for #{air_loop.name.get} is above #{air_loop_cooling_capacity_max_error.round} #{air_loop_cooling_capacity_units_ip}." )
        end
      end

      # check heating capacity of thermal zones in the model with exterior exposure
      report_name = 'HVACSizingSummary'
      table_name = 'Zone Sensible Heating'
      column_name = 'User Design Load per Area'
      min_error = sizing_benchmarks['zone_heating_capacity']['min_error']
      min_warning = sizing_benchmarks['zone_heating_capacity']['min_warning']
      max_warning = sizing_benchmarks['zone_heating_capacity']['max_warning']
      max_error = sizing_benchmarks['zone_heating_capacity']['max_error']
      units_ip = sizing_benchmarks['zone_heating_capacity']['units']

      @model.getThermalZones.sort.each do |thermal_zone|
        next if thermal_zone.canBePlenum
        next if thermal_zone.exteriorSurfaceArea == 0.0
        # check actual against target
        query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='#{report_name}' and TableName='#{table_name}' and RowName= '#{thermal_zone.name.get.upcase}' and ColumnName= '#{column_name}'"
        results = @sql.execAndReturnFirstDouble(query)
        model_zone_heating_capacity_ip = OpenStudio.convert(results.to_f, 'W/m^2', units_ip).get
        if model_zone_heating_capacity_ip < min_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is below #{min_error.round(1)} Btu/ft^2*h." )
        elsif model_zone_heating_capacity_ip < min_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is below #{min_warning.round(1)} Btu/ft^2*h." )
        elsif model_zone_heating_capacity_ip > max_warning
          check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is above #{max_warning.round(1)} Btu/ft^2*h." )
        elsif model_zone_heating_capacity_ip > max_error
          check_elems <<  OpenStudio::Attribute.new('flag', "Heating Capacity of #{model_zone_heating_capacity_ip.round(2)} Btu/ft^2*h for #{thermal_zone.name.get} is above #{max_error.round(1)} Btu/ft^2*h." )
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
