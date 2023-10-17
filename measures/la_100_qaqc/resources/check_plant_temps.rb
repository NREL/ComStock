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
  # Check the plant loop operational vs. sizing temperatures and make sure everything is coordinated.
  # This identifies problems caused by sizing to one set of conditions and operating at a different set.
  #
  # @param max_sizing_temp_delta [Double] threshold for throwing an error for design sizing temperatures
  # @param max_operating_temp_delta [Double] threshold for throwing an error on operating temperatures
  def check_plant_temps(category, max_sizing_temp_delta: 2.0, max_operating_temp_delta: 5.0, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Plant Loop Temperatures')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check that plant loop sizing and operation temperatures are coordinated.')

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
      # Check each plant loop in the model
      @model.getPlantLoops.sort.each do |plant_loop|
        supply_outlet_node_name = plant_loop.supplyOutletNode.name.to_s
        design_supply_temperature = plant_loop.sizingPlant.designLoopExitTemperature
        design_supply_temperature = OpenStudio.convert(design_supply_temperature, 'C', 'F').get
        design_temperature_difference = plant_loop.sizingPlant.loopDesignTemperatureDifference
        design_temperature_difference = OpenStudio.convert(design_temperature_difference, 'K', 'R').get

        # get min and max temperatures from setpoint manager
        spm_name = ''
        spm_type = '<unspecified>'
        spm_min_temp_f = nil
        spm_max_temp_f = nil
        spms = plant_loop.supplyOutletNode.setpointManagers
        unless spms.empty?
          spm = spms[0] # assume first setpoint manager is only setpoint manager
          spm_name = spm.name
          spm_type = spm.iddObjectType.valueName.to_s
          spm_temps_f = setpoint_manager_min_max_value(spm)
          spm_min_temp_f = spm_temps_f[0]
          spm_max_temp_f = spm_temps_f[1]
        end

        # check setpoint manager temperatures against design temperatures
        case plant_loop.sizingPlant.loopType
        when 'Heating'
          if spm_max_temp_f
            if (spm_max_temp_f - design_supply_temperature).abs > max_sizing_temp_delta
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: #{plant_loop.name} sizing uses a #{design_supply_temperature.round(1)}F supply water temperature, but the setpoint manager operates up to #{spm_max_temp_f.round(1)}F." )
            end
          end
        when 'Cooling'
          if spm_min_temp_f
            if (spm_min_temp_f - design_supply_temperature).abs > max_sizing_temp_delta
              check_elems << OpenStudio::Attribute.new('flag', "Minor Error: #{plant_loop.name} sizing uses a #{design_supply_temperature.round(1)}F supply water temperature, but the setpoint manager operates down to #{spm_min_temp_f.round(1)}F." )
            end
          end
        end

        # get supply water temperatures for supply outlet node
        supply_temp_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Temperature', supply_outlet_node_name)
        if supply_temp_timeseries.empty?
          check[:items] << { type: 'warning', msg: "No supply node temperature timeseries found for '#{plant_loop.name}'" }
          next
        else
          # convert to ruby array
          temperatures = []
          supply_temp_vector = supply_temp_timeseries.get.values
          for i in (0..supply_temp_vector.size - 1)
            temperatures << supply_temp_vector[i]
          end
        end

        # get supply water flow rates for supply outlet node
        supply_flow_timeseries = @sql.timeSeries(ann_env_pd, 'Timestep', 'System Node Standard Density Volume Flow Rate', supply_outlet_node_name)
        if supply_flow_timeseries.empty?
          check_elems << OpenStudio::Attribute.new('flag', "Warning: No supply node temperature timeseries found for '#{plant_loop.name}'" )
          next
        else
          # convert to ruby array
          flowrates = []
          supply_flow_vector = supply_flow_timeseries.get.values
          for i in (0..supply_flow_vector.size - 1)
            flowrates << supply_flow_vector[i].to_f
          end
        end

        # check reasonableness of supply water temperatures when supply water flow rate is operating
        operating_temperatures = temperatures.select.with_index { |_t, k| flowrates[k] > 1e-8 }
        operating_temperatures = operating_temperatures.map { |t| (t * 1.8 + 32.0) }

        if operating_temperatures.empty?
          check_elems << OpenStudio::Attribute.new('flag', "Warning: Flowrates are all zero in supply node timeseries for '#{plant_loop.name}'" )
          next
        end

        runtime_fraction = operating_temperatures.size.to_f / temperatures.size.to_f
        temps_out_of_bounds = []
        case plant_loop.sizingPlant.loopType
        when 'Heating'
          design_return_temperature = design_supply_temperature - design_temperature_difference
          expected_max = spm_max_temp_f.nil? ? design_supply_temperature : [design_supply_temperature, spm_max_temp_f].max
          expected_min = spm_min_temp_f.nil? ? design_return_temperature : [design_return_temperature, spm_min_temp_f].min
          temps_out_of_bounds = (operating_temperatures.select { |t| (((t + max_operating_temp_delta) < expected_min) || ((t - max_operating_temp_delta) > expected_max)) } )
        when 'Cooling'
          design_return_temperature = design_supply_temperature + design_temperature_difference
          expected_max = spm_max_temp_f.nil? ? design_return_temperature : [design_return_temperature, spm_max_temp_f].max
          expected_min = spm_min_temp_f.nil? ? design_supply_temperature : [design_supply_temperature, spm_min_temp_f].min
          temps_out_of_bounds = (operating_temperatures.select { |t| (((t + max_operating_temp_delta) < expected_min) || ((t - max_operating_temp_delta) > expected_max)) } )
        when 'Condenser'
          design_return_temperature = design_supply_temperature + design_temperature_difference
          expected_max = spm_max_temp_f.nil? ? design_return_temperature : [design_return_temperature, spm_max_temp_f].max
          temps_out_of_bounds = (operating_temperatures.select { |t| ((t < 35.0) || (t > 100.0) || ((t - max_operating_temp_delta) > expected_max)) } )
        end

        next if temps_out_of_bounds.empty?

        min_op_temp_f = temps_out_of_bounds.min
        max_op_temp_f = temps_out_of_bounds.max
        # avg_F = temps_out_of_bounds.inject(:+).to_f / temps_out_of_bounds.size
        spm_min_temp_f = spm_min_temp_f.round(1) unless spm_min_temp_f.nil?
        spm_max_temp_f = spm_max_temp_f.round(1) unless spm_max_temp_f.nil?
        err = []
        err << "Major Error:"
        err << "Expected supply water temperatures out of bounds for"
        err << "#{plant_loop.sizingPlant.loopType} plant loop '#{plant_loop.name}'"
        err << "with a #{design_supply_temperature.round(1)}F design supply temperature and"
        err << "#{design_return_temperature.round(1)}F design return temperature and"
        err << "a setpoint manager '#{spm_name}' of type '#{spm_type}' with a"
        err << "#{spm_min_temp_f}F minimum setpoint temperature and"
        err << "#{spm_max_temp_f}F maximum setpoint temperature."
        err << "Out of #{operating_temperatures.size}/#{temperatures.size} (#{(runtime_fraction * 100.0).round(1)}%) operating supply water temperatures"
        err << "#{temps_out_of_bounds.size}/#{operating_temperatures.size} (#{((temps_out_of_bounds.size.to_f / operating_temperatures.size) * 100.0).round(1)}%)"
        err << "are out of bounds with #{min_op_temp_f.round(1)}F min and #{max_op_temp_f.round(1)}F max."
        check_elems << OpenStudio::Attribute.new('flag', err.join(' ').gsub(/\n/, ""))
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
