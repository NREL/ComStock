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
  # @param max_pass_pct [Double] threshold for throwing an error for percent difference
  def check_simultaneous_heating_and_cooling(category, max_pass_pct: 0.1, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Simultaneous Heating and Cooling')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check for simultaneous heating and cooling by looping through all Single Duct VAV Reheat Air Terminals and analyzing hourly data when there is a cooling load. ')

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    begin
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
        check_elems << OpenStudio::Attribute.new('flag', 'Cannot find the annual simulation run period, cannot determine simultaneous heating and cooling.')
        return check_elem
      end

      # For each VAV reheat terminal, calculate
      # the annual total % reheat hours.
      @model.getAirTerminalSingleDuctVAVReheats.sort.each do |term|
        # Reheat coil heating rate
        rht_coil = term.reheatCoil
        key_value =  rht_coil.name.get.to_s.upcase # must be in all caps.
        time_step = 'Hourly' # "Zone Timestep", "Hourly", "HVAC System Timestep"
        variable_name = 'Heating Coil Heating Rate'
        variable_name_alt = 'Heating Coil Air Heating Rate'
        rht_rate_ts = @sql.timeSeries(ann_env_pd, time_step, variable_name, key_value) # key value would go at the end if we used it.

        # try and alternate variable name
        if rht_rate_ts.empty?
          rht_rate_ts = @sql.timeSeries(ann_env_pd, time_step, variable_name_alt, key_value) # key value would go at the end if we used it.
        end

        if rht_rate_ts.empty?
          check_elems << OpenStudio::Attribute.new('flag', "Heating Coil (Air) Heating Rate Timeseries not found for #{key_value}.")
        else

          rht_rate_ts = rht_rate_ts.get.values
          # Put timeseries into array
          rht_rate_vals = []
          for i in 0..(rht_rate_ts.size - 1)
            rht_rate_vals << rht_rate_ts[i]
          end

          # Zone Air Terminal Sensible Heating Rate
          key_value = "ADU #{term.name.get.to_s.upcase}" # must be in all caps.
          time_step = 'Hourly' # "Zone Timestep", "Hourly", "HVAC System Timestep"
          variable_name = 'Zone Air Terminal Sensible Cooling Rate'
          clg_rate_ts = @sql.timeSeries(ann_env_pd, time_step, variable_name, key_value) # key value would go at the end if we used it.
          if clg_rate_ts.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Zone Air Terminal Sensible Cooling Rate Timeseries not found for #{key_value}.")
          else

            clg_rate_ts = clg_rate_ts.get.values
            # Put timeseries into array
            clg_rate_vals = []
            for i in 0..(clg_rate_ts.size - 1)
              clg_rate_vals << clg_rate_ts[i]
            end

            # Loop through each timestep and calculate the hourly
            # % reheat value.
            ann_rht_hrs = 0
            ann_clg_hrs = 0
            ann_pcts = []
            rht_rate_vals.zip(clg_rate_vals).each do |rht_w, clg_w|
              # Skip hours with no cooling (in heating mode)
              next if clg_w == 0
              pct_overcool_rht = rht_w / (rht_w + clg_w)
              ann_rht_hrs += pct_overcool_rht # implied * 1hr b/c hrly results
              ann_clg_hrs += 1
              ann_pcts << pct_overcool_rht.round(3)
            end

            # Calculate annual % reheat hours
            ann_pct_reheat = ((ann_rht_hrs / ann_clg_hrs) * 100).round(1)

            # Compare to limit
            if ann_pct_reheat > max_pass_pct * 100.0
              check_elems << OpenStudio::Attribute.new('flag', "#{term.name} has #{ann_pct_reheat}% overcool-reheat, which is greater than the limit of #{max_pass_pct * 100.0}%. This terminal is in cooling mode for #{ann_clg_hrs} hours of the year.")
            end

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
