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
  # Check primary plant loop heating and cooling equipment capacity against coil loads to find equipment that is significantly oversized or undersized.
  #
  # @param target_standard [Standard] target standard, Class Standard from openstudio-standards
  # @param max_pct_delta [Double] threshold for throwing an error for percent difference
  def check_plant_cap(category, target_standard, max_pct_delta: 0.3, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Plant Capacity')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check that plant equipment capacity matches loads.')

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
      # Check the heating and cooling capacity of the plant loops against their coil loads
      @model.getPlantLoops.sort.each do |plant_loop|
        # Heating capacity
        htg_cap_w = std.plant_loop_total_heating_capacity(plant_loop)

        # Cooling capacity
        clg_cap_w = std.plant_loop_total_cooling_capacity(plant_loop)

        # Sum the load for each coil on the loop
        htg_load_w = 0.0
        clg_load_w = 0.0
        plant_loop.demandComponents.each do |dc|
          obj_type = dc.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_Coil_Heating_Water'
            coil = dc.to_CoilHeatingWater.get
            if coil.ratedCapacity.is_initialized
              htg_load_w += coil.ratedCapacity.get
            elsif coil.autosizedRatedCapacity.is_initialized
              htg_load_w += coil.autosizedRatedCapacity.get
            end
          when 'OS_Coil_Cooling_Water'
            coil = dc.to_CoilCoolingWater.get
            if coil.autosizedDesignCoilLoad.is_initialized
              clg_load_w += coil.autosizedDesignCoilLoad.get
            end
          end
        end

        # Don't check loops with no loads.  These are probably SWH or non-typical loops that can't be checked by simple methods.
        # Heating
        if htg_load_w > 0
          htg_cap_kbtu_per_hr = OpenStudio.convert(htg_cap_w, 'W', 'kBtu/hr').get.round(1)
          htg_load_kbtu_per_hr = OpenStudio.convert(htg_load_w, 'W', 'kBtu/hr').get.round(1)
          if ((htg_cap_w - htg_load_w) / htg_cap_w).abs > max_pct_delta
            check_elems << OpenStudio::Attribute.new('flag', "For #{plant_loop.name}, the total heating capacity of #{htg_cap_kbtu_per_hr} kBtu/hr is more than #{(max_pct_delta * 100.0).round(2)}% different from the combined coil load of #{htg_load_kbtu_per_hr} kBtu/hr.  This could indicate significantly oversized or undersized equipment.")
          end
        end

        # Cooling
        if clg_load_w > 0
          clg_cap_tons = OpenStudio.convert(clg_cap_w, 'W', 'ton').get.round(1)
          clg_load_tons = OpenStudio.convert(clg_load_w, 'W', 'ton').get.round(1)
          if ((clg_cap_w - clg_load_w) / clg_cap_w).abs > max_pct_delta
            check_elems << OpenStudio::Attribute.new('flag', "For #{plant_loop.name}, the total cooling capacity of #{clg_load_tons} tons is more than #{(max_pct_delta * 100.0).round(2)}% different from the combined coil load of #{clg_load_tons} tons.  This could indicate significantly oversized or undersized equipment.")
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
