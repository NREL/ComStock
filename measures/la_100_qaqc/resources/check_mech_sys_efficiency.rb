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
  # Check the mechanical system efficiencies against a standard
  #
  # @param target_standard [Standard] target standard, Class Standard from openstudio-standards
  # @param min_pass_pct [Double] threshold for throwing an error for percent difference
  # @param max_pass_pct [Double] threshold for throwing an error for percent difference
  def check_mech_sys_efficiency(category, target_standard, min_pass_pct: 0.3, max_pass_pct: 0.3, name_only: false)
    component_type_array = ['ChillerElectricEIR', 'CoilCoolingDXSingleSpeed', 'CoilCoolingDXTwoSpeed', 'CoilHeatingDXSingleSpeed', 'BoilerHotWater', 'FanConstantVolume', 'FanVariableVolume', 'PumpConstantSpeed', 'PumpVariableSpeed']

    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Efficiency')
    check_elems << OpenStudio::Attribute.new('category', category)

    if target_standard.include?('90.1-2013')
      check_elems << OpenStudio::Attribute.new('description', "Check against #{target_standard} Tables 6.8.1 A-K for the following component types: #{component_type_array.join(', ')}.")
    else
      check_elems << OpenStudio::Attribute.new('description', "Check against #{target_standard} for the following component types: #{component_type_array.join(', ')}.")
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
      # check ChillerElectricEIR objects (will also have curve check in different script)
      @model.getChillerElectricEIRs.sort.each do |component|
        # eff values from model
        reference_COP = component.referenceCOP

        # get eff values from standards (if name doesn't have expected strings find object returns first object of multiple)
        standard_minimum_full_load_efficiency = std.chiller_electric_eir_standard_minimum_full_load_efficiency(component)

        # check actual against target
        if standard_minimum_full_load_efficiency.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target full load efficiency for #{component.name}.")
        elsif reference_COP < standard_minimum_full_load_efficiency * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "COP of #{reference_COP.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_full_load_efficiency.round(2)}.")
        elsif reference_COP > standard_minimum_full_load_efficiency * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "COP  of #{reference_COP.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_full_load_efficiency.round(2)}.")
        end
      end

      # check CoilCoolingDXSingleSpeed objects (will also have curve check in different script)
      @model.getCoilCoolingDXSingleSpeeds.each do |component|
        # eff values from model
        rated_COP = component.ratedCOP.get

        # get eff values from standards
        standard_minimum_cop = std.coil_cooling_dx_single_speed_standard_minimum_cop(component)

        # check actual against target
        if standard_minimum_cop.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
        elsif rated_COP < standard_minimum_cop * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The COP of #{rated_COP.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        elsif rated_COP > standard_minimum_cop * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The COP of  #{rated_COP.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        end
      end

      # check CoilCoolingDXTwoSpeed objects (will also have curve check in different script)
      @model.getCoilCoolingDXTwoSpeeds.sort.each do |component|
        # eff values from model
        rated_high_speed_COP = component.ratedHighSpeedCOP.get
        rated_low_speed_COP = component.ratedLowSpeedCOP.get

        # get eff values from standards
        standard_minimum_cop = std.coil_cooling_dx_two_speed_standard_minimum_cop(component)

        # check actual against target
        if standard_minimum_cop.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
        elsif rated_high_speed_COP < standard_minimum_cop * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The high speed COP of #{rated_high_speed_COP.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        elsif rated_high_speed_COP > standard_minimum_cop * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The high speed COP of  #{rated_high_speed_COP.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        end
        if standard_minimum_cop.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
        elsif rated_low_speed_COP < standard_minimum_cop * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The low speed COP of #{rated_low_speed_COP.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        elsif rated_low_speed_COP > standard_minimum_cop * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The low speed COP of  #{rated_low_speed_COP.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        end
      end

      # check CoilHeatingDXSingleSpeed objects
      # @todo - need to test this once json file populated for this data
      @model.getCoilHeatingDXSingleSpeeds.sort.each do |component|
        # eff values from model
        rated_COP = component.ratedCOP

        # get eff values from standards
        standard_minimum_cop = std.coil_heating_dx_single_speed_standard_minimum_cop(component)

        # check actual against target
        if standard_minimum_cop.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target COP for #{component.name}.")
        elsif rated_COP < standard_minimum_cop * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The COP of #{rated_COP.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_cop.round(2)} for #{target_standard}.")
        elsif rated_COP > standard_minimum_cop * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The COP of  #{rated_COP.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_cop.round(2)}. for #{target_standard}")
        end
      end

      # check BoilerHotWater
      @model.getBoilerHotWaters.sort.each do |component|
        # eff values from model
        nominal_thermal_efficiency = component.nominalThermalEfficiency

        # get eff values from standards
        standard_minimum_thermal_efficiency = std.boiler_hot_water_standard_minimum_thermal_efficiency(component)

        # check actual against target
        if standard_minimum_thermal_efficiency.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target thermal efficiency for #{component.name}.")
        elsif nominal_thermal_efficiency < standard_minimum_thermal_efficiency * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Nominal thermal efficiency of #{nominal_thermal_efficiency.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_thermal_efficiency.round(2)} for #{target_standard}.")
        elsif nominal_thermal_efficiency > standard_minimum_thermal_efficiency * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Nominal thermal efficiency of  #{nominal_thermal_efficiency.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_thermal_efficiency.round(2)} for #{target_standard}.")
        end
      end

      # check FanConstantVolume
      @model.getFanConstantVolumes.sort.each do |component|
        # eff values from model
        motor_eff = component.motorEfficiency

        # get eff values from standards
        motor_bhp = std.fan_brake_horsepower(component)
        standard_minimum_motor_efficiency_and_size = std.fan_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

        # check actual against target
        if standard_minimum_motor_efficiency_and_size.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}." )
        elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        end
      end

      # check FanVariableVolume
      @model.getFanVariableVolumes.sort.each do |component|
        # eff values from model
        motor_eff = component.motorEfficiency

        # get eff values from standards
        motor_bhp = std.fan_brake_horsepower(component)
        standard_minimum_motor_efficiency_and_size = std.fan_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

        # check actual against target
        if standard_minimum_motor_efficiency_and_size.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}." )
        elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        end
      end

      # check PumpConstantSpeed
      @model.getPumpConstantSpeeds.sort.each do |component|
        # eff values from model
        motor_eff = component.motorEfficiency

        # get eff values from standards
        motor_bhp = std.pump_brake_horsepower(component)
        next if motor_bhp == 0.0
        standard_minimum_motor_efficiency_and_size = std.pump_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

        # check actual against target
        if standard_minimum_motor_efficiency_and_size.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}." )
        elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        end
      end

      # check PumpVariableSpeed
      @model.getPumpVariableSpeeds.sort.each do |component|
        # eff values from model
        motor_eff = component.motorEfficiency

        # get eff values from standards
        motor_bhp = std.pump_brake_horsepower(component)
        next if motor_bhp == 0.0
        standard_minimum_motor_efficiency_and_size = std.pump_standard_minimum_motor_efficiency_and_size(component, motor_bhp)[0]

        # check actual against target
        if standard_minimum_motor_efficiency_and_size.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target motor efficiency for #{component.name}." )
        elsif motor_eff < standard_minimum_motor_efficiency_and_size * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
        elsif motor_eff > standard_minimum_motor_efficiency_and_size * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "Motor efficiency of #{motor_eff.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the expected value of #{standard_minimum_motor_efficiency_and_size.round(2)} for #{target_standard}.")
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
