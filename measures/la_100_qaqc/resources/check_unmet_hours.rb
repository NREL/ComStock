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
  # Check model unmet hours
  #
  # @param target_standard [Standard] target standard, Class Standard from openstudio-standards
  # @param max_unmet_hrs [Double] threshold for unmet hours reporting
  # @param expect_clg_unmet_hrs [Bool] boolean on whether to expect unmet cooling hours for a model without a cooling system
  # @param expect_htg_unmet_hrs [Bool] boolean on whether to expect unmet heating hours for a model without a heating system
  def check_unmet_hours(category, target_standard, max_unmet_hrs: 550.0, expect_clg_unmet_hrs: false, expect_htg_unmet_hrs: false, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Unmet Hours')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check model unmet hours.')

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
      unmet_heating_hrs = std.model_annual_occupied_unmet_heating_hours(@model)
      unmet_cooling_hrs = std.model_annual_occupied_unmet_cooling_hours(@model)
      unmet_hrs = std.model_annual_occupied_unmet_hours(@model)

      if unmet_hrs
        if unmet_hrs > max_unmet_hrs
          if expect_clg_unmet_hrs && expect_htg_unmet_hrs
            check_elems << OpenStudio::Attribute.new('flag', "Warning: Unmet heating and cooling hours expected.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)})." )
          elsif expect_clg_unmet_hrs && !expect_htg_unmet_hrs && unmet_heating_hrs >= max_unmet_hrs
            check_elems << OpenStudio::Attribute.new('flag', "Major Error: Unmet cooling hours expected, but unmet heating hours exceeds limit of #{max_unmet_hrs}.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)})." )
          elsif expect_clg_unmet_hrs && !expect_htg_unmet_hrs && unmet_heating_hrs < max_unmet_hrs
            check_elems << OpenStudio::Attribute.new('flag', "Warning: Unmet cooling hours expected.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)})." )
          elsif expect_htg_unmet_hrs && !expect_clg_unmet_hrs && unmet_cooling_hrs >= max_unmet_hrs
            check_elems << OpenStudio::Attribute.new('flag', "Major Error: Unmet heating hours expected, but unmet cooling hours exceeds limit of #{max_unmet_hrs}.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)})." )
          elsif expect_htg_unmet_hrs && !expect_clg_unmet_hrs && unmet_cooling_hrs < max_unmet_hrs
            check_elems << OpenStudio::Attribute.new('flag', "Warning: Unmet heating hours expected.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)})." )
          else
            check_elems << OpenStudio::Attribute.new('flag', "Major Error: There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}), more than the limit of #{max_unmet_hrs}." )
          end
        end
      else
        check_elems << OpenStudio::Attribute.new('flag', 'Warning: Could not determine unmet hours; simulation may have failed.' )
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
