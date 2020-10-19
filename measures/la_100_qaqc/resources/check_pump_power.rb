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
  # Check the pumping power (W/gpm) for each pump in the model to identify unrealistically sized pumps.
  #
  # @param std [Standard] target standard, Class Standard from openstudio-standards
  # @param max_pct_delta [Double] threshold for throwing an error for percent difference
  def check_pump_power(category, target_standard, max_pct_delta: 0.3, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Pump Power')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check that pump power vs flow makes sense.')

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
      # Check each plant loop
      @model.getPlantLoops.sort.each do |plant_loop|
        # Set the expected/typical W/gpm
        loop_type = plant_loop.sizingPlant.loopType
        case loop_type
        when 'Heating'
          expected_w_per_gpm = 19.0
        when 'Cooling'
          expected_w_per_gpm = 22.0
        when 'Condenser'
          expected_w_per_gpm = 19.0
        end

        # Check the W/gpm for each pump on each plant loop
        plant_loop.supplyComponents.each do |component|
          # Get the W/gpm for the pump
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_Pump_ConstantSpeed'
            actual_w_per_gpm = std.pump_rated_w_per_gpm(component.to_PumpConstantSpeed.get)
          when 'OS_Pump_VariableSpeed'
            actual_w_per_gpm = std.pump_rated_w_per_gpm(component.to_PumpVariableSpeed.get)
          when 'OS_HeaderedPumps_ConstantSpeed'
            actual_w_per_gpm = std.pump_rated_w_per_gpm(component.to_HeaderedPumpsConstantSpeed.get)
          when 'OS_HeaderedPumps_VariableSpeed'
            actual_w_per_gpm = std.pump_rated_w_per_gpm(component.to_HeaderedPumpsVariableSpeed.get)
          else
            next # Skip non-pump objects
          end

          # Compare W/gpm to expected/typical values
          if ((expected_w_per_gpm - actual_w_per_gpm) / actual_w_per_gpm).abs > max_pct_delta
            if plant_loop.name.get.to_s.downcase.include? 'service water loop'
              # some service water loops use just water main pressure and have a dummy pump
              check_elems << OpenStudio::Attribute.new('flag', "Warning: For #{component.name} on #{plant_loop.name}, the pumping power is #{actual_w_per_gpm.round(1)} W/gpm." )
            else
              check_elems << OpenStudio::Attribute.new('flag', "For #{component.name} on #{plant_loop.name}, the actual pumping power of #{actual_w_per_gpm.round(1)} W/gpm is more than #{(max_pct_delta * 100.0).round(2)}% different from the expected #{expected_w_per_gpm} W/gpm for a #{loop_type} plant loop." )
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
