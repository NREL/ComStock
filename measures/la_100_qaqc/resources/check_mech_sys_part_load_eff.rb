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
  # Check the mechanical system part load efficiencies against a standard
  #
  # @param target_standard [Standard] target standard, Class Standard from openstudio-standards
  # @param min_pass_pct [Double] threshold for throwing an error for percent difference
  # @param max_pass_pct [Double] threshold for throwing an error for percent difference
  def check_mech_sys_part_load_eff(category, target_standard, min_pass_pct: 0.3, max_pass_pct: 0.3, name_only: false)
    component_type_array = ['ChillerElectricEIR', 'CoilCoolingDXSingleSpeed', 'CoilCoolingDXTwoSpeed', 'CoilHeatingDXSingleSpeed']

    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Mechanical System Part Load Efficiency')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', "Check 40% and 80% part load efficency against #{target_standard} for the following compenent types: #{component_type_array.join(', ')}. Checking EIR Function of Part Load Ratio curve for chiller and EIR Function of Flow Fraction for DX coils.")

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    std = Standard.build(target_standard)

    # @todo: add in check for VAV fan
    begin
      # @todo: dynamically generate a list of possible options from the standards json
      chiller_air_cooled_condenser_types = ['WithCondenser', 'WithoutCondenser']
      chiller_water_cooled_compressor_types = ['Reciprocating', 'Scroll', 'Rotary Screw', 'Centrifugal']
      absorption_types = ['Single Effect', 'Double Effect Indirect Fired', 'Double Effect Direct Fired']

      # check getChillerElectricEIRs objects (will also have curve check in different script)
      @model.getChillerElectricEIRs.sort.each do |component|
        # get curve and evaluate
        electric_input_to_cooling_output_ratio_function_of_PLR = component.electricInputToCoolingOutputRatioFunctionOfPLR
        curve_40_pct = electric_input_to_cooling_output_ratio_function_of_PLR.evaluate(0.4)
        curve_80_pct = electric_input_to_cooling_output_ratio_function_of_PLR.evaluate(0.8)

        # find ac properties
        search_criteria = std.chiller_electric_eir_find_search_criteria(component)

        # extend search_criteria for absorption_type
        absorption_types.each do |absorption_type|
          if component.name.to_s.include?(absorption_type)
            search_criteria['absorption_type'] = absorption_type
            next
          end
        end
        # extend search_criteria for condenser type or compressor type
        if search_criteria['cooling_type'] == 'AirCooled'
          chiller_air_cooled_condenser_types.each do |condenser_type|
            if component.name.to_s.include?(condenser_type)
              search_criteria['condenser_type'] = condenser_type
              next
            end
          end
          # if no match and also no absorption_type then issue warning
          if !search_criteria.key?('condenser_type') || search_criteria['condenser_type'].nil?
            if !search_criteria.key?('absorption_type') || search_criteria['absorption_type'].nil?
              check_elems <<  OpenStudio::Attribute.new('flag', "Can't find unique search criteria for #{component.name}. #{search_criteria}")
              next # don't go past here
            end
          end
        elsif search_criteria['cooling_type'] == 'WaterCooled'
          chiller_air_cooled_condenser_types.each do |compressor_type|
            if component.name.to_s.include?(compressor_type)
              search_criteria['compressor_type'] = compressor_type
              next
            end
          end
          # if no match and also no absorption_type then issue warning
          if !search_criteria.key?('compressor_type') || search_criteria['compressor_type'].nil?
            if !search_criteria.key?('absorption_type') || search_criteria['absorption_type'].nil?
              check_elems <<  OpenStudio::Attribute.new('flag', "Can't find unique search criteria for #{component.name}. #{search_criteria}")
              next # don't go past here
            end
          end
        end

        # lookup chiller
        capacity_w = std.chiller_electric_eir_find_capacity(component)
        capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get
        chlr_props = std.model_find_object(std.standards_data['chillers'], search_criteria, capacity_tons, Date.today)
        if chlr_props.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Didn't find chiller for #{component.name}. #{search_criteria}")
          next # don't go past here in loop if can't find curve
        end

        # temp model to hold temp curve
        model_temp = OpenStudio::Model::Model.new

        # create temp curve
        target_curve_name = chlr_props['eirfplr']
        if target_curve_name.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target eirfplr curve for #{component.name}")
          next # don't go past here in loop if can't find curve
        end
        temp_curve = std.model_add_curve(model_temp, target_curve_name)

        target_curve_40_pct = temp_curve.evaluate(0.4)
        target_curve_80_pct = temp_curve.evaluate(0.8)

        # check curve at two points
        if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        end
        if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        end
      end

      # check getCoilCoolingDXSingleSpeeds objects (will also have curve check in different script)
      @model.getCoilCoolingDXSingleSpeeds.sort.each do |component|
        # get curve and evaluate
        eir_function_of_flow_fraction_curve = component.energyInputRatioFunctionOfFlowFractionCurve
        curve_40_pct = eir_function_of_flow_fraction_curve.evaluate(0.4)
        curve_80_pct = eir_function_of_flow_fraction_curve.evaluate(0.8)

        # find ac properties
        search_criteria = std.coil_dx_find_search_criteria(component)
        capacity_w = std.coil_cooling_dx_single_speed_find_capacity(component)
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        if std.coil_dx_heat_pump?(component)
          ac_props = std.model_find_object(std.standards_data['heat_pumps'], search_criteria, capacity_btu_per_hr, Date.today)
        else
          ac_props = std.model_find_object(std.standards_data['unitary_acs'], search_criteria, capacity_btu_per_hr, Date.today)
        end

        # temp model to hold temp curve
        model_temp = OpenStudio::Model::Model.new

        # create temp curve
        target_curve_name = ac_props['cool_eir_fflow']
        if target_curve_name.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target cool_eir_fflow curve for #{component.name}")
          next # don't go past here in loop if can't find curve
        end
        temp_curve = std.model_add_curve(model_temp, target_curve_name)
        target_curve_40_pct = temp_curve.evaluate(0.4)
        target_curve_80_pct = temp_curve.evaluate(0.8)

        # check curve at two points
        if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        end
        if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        end
      end

      # check CoilCoolingDXTwoSpeed objects (will also have curve check in different script)
      @model.getCoilCoolingDXTwoSpeeds.sort.each do |component|
        # get curve and evaluate
        eir_function_of_flow_fraction_curve = component.energyInputRatioFunctionOfFlowFractionCurve
        curve_40_pct = eir_function_of_flow_fraction_curve.evaluate(0.4)
        curve_80_pct = eir_function_of_flow_fraction_curve.evaluate(0.8)

        # find ac properties
        search_criteria = std.coil_dx_find_search_criteria(component)
        capacity_w = std.coil_cooling_dx_two_speed_find_capacity(component)
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        ac_props = std.model_find_object(std.standards_data['unitary_acs'], search_criteria, capacity_btu_per_hr, Date.today)

        # temp model to hold temp curve
        model_temp = OpenStudio::Model::Model.new

        # create temp curve
        target_curve_name = ac_props['cool_eir_fflow']
        if target_curve_name.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target cool_eir_flow curve for #{component.name}")
          next # don't go past here in loop if can't find curve
        end
        temp_curve = std.model_add_curve(model_temp, target_curve_name)
        target_curve_40_pct = temp_curve.evaluate(0.4)
        target_curve_80_pct = temp_curve.evaluate(0.8)

        # check curve at two points
        if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        end
        if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        end
      end

      # check CoilCoolingDXTwoSpeed objects (will also have curve check in different script)
      @model.getCoilHeatingDXSingleSpeeds.sort.each do |component|
        # get curve and evaluate
        eir_function_of_flow_fraction_curve = component.energyInputRatioFunctionofFlowFractionCurve # why lowercase of here but not in CoilCoolingDX objects
        curve_40_pct = eir_function_of_flow_fraction_curve.evaluate(0.4)
        curve_80_pct = eir_function_of_flow_fraction_curve.evaluate(0.8)

        # find ac properties
        search_criteria = std.coil_dx_find_search_criteria(component)
        capacity_w = std.coil_heating_dx_single_speed_find_capacity(component)
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        ac_props = std.model_find_object(std.standards_data['heat_pumps_heating'], search_criteria, capacity_btu_per_hr, Date.today)
        if ac_props.nil?
          target_curve_name = nil
        else
          target_curve_name = ac_props['heat_eir_fflow']
        end

        # temp model to hold temp curve
        model_temp = OpenStudio::Model::Model.new

        # create temp curve
        if target_curve_name.nil?
          check_elems <<  OpenStudio::Attribute.new('flag', "Can't find target curve for #{component.name}")
          next # don't go past here in loop if can't find curve
        end
        temp_curve = std.model_add_curve(model_temp, target_curve_name)

        # Ensure that the curve was found in standards before attempting to evaluate
        if temp_curve.nil?
          check_elems << OpenStudio::Attribute.new('flag', "Can't find coefficients of curve called #{target_curve_name} for #{component.name}, cannot check part-load performance.")
          next
        end

        target_curve_40_pct = temp_curve.evaluate(0.4)
        target_curve_80_pct = temp_curve.evaluate(0.8)

        # check curve at two points
        if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        end
        if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        end
      end

      # check
      @model.getFanVariableVolumes.sort.each do |component|
        # skip if not on multi-zone system.
        if component.airLoopHVAC.is_initialized
          airloop = component.airLoopHVAC.get

          next unless airloop.thermalZones.size > 1.0
        end

        # skip of brake horsepower is 0
        next if std.fan_brake_horsepower(component) == 0.0

        # temp model for use by temp model and target curve
        model_temp = OpenStudio::Model::Model.new

        # get coeficents for fan
        model_fan_coefs = []
        model_fan_coefs << component.fanPowerCoefficient1.get
        model_fan_coefs << component.fanPowerCoefficient2.get
        model_fan_coefs << component.fanPowerCoefficient3.get
        model_fan_coefs << component.fanPowerCoefficient4.get
        model_fan_coefs << component.fanPowerCoefficient5.get

        # make model curve
        model_curve = OpenStudio::Model::CurveQuartic.new(model_temp)
        model_curve.setCoefficient1Constant(model_fan_coefs[0])
        model_curve.setCoefficient2x(model_fan_coefs[1])
        model_curve.setCoefficient3xPOW2(model_fan_coefs[2])
        model_curve.setCoefficient4xPOW3(model_fan_coefs[3])
        model_curve.setCoefficient5xPOW4(model_fan_coefs[4])
        curve_40_pct = model_curve.evaluate(0.4)
        curve_80_pct = model_curve.evaluate(0.8)

        # get target coefs
        target_fan = OpenStudio::Model::FanVariableVolume.new(model_temp)
        std.fan_variable_volume_set_control_type(target_fan, 'Multi Zone VAV with VSD and Static Pressure Reset')

        # get coeficents for fan
        target_fan_coefs = []
        target_fan_coefs << target_fan.fanPowerCoefficient1.get
        target_fan_coefs << target_fan.fanPowerCoefficient2.get
        target_fan_coefs << target_fan.fanPowerCoefficient3.get
        target_fan_coefs << target_fan.fanPowerCoefficient4.get
        target_fan_coefs << target_fan.fanPowerCoefficient5.get

        # make model curve
        target_curve = OpenStudio::Model::CurveQuartic.new(model_temp)
        target_curve.setCoefficient1Constant(target_fan_coefs[0])
        target_curve.setCoefficient2x(target_fan_coefs[1])
        target_curve.setCoefficient3xPOW2(target_fan_coefs[2])
        target_curve.setCoefficient4xPOW3(target_fan_coefs[3])
        target_curve.setCoefficient5xPOW4(target_fan_coefs[4])
        target_curve_40_pct = target_curve.evaluate(0.4)
        target_curve_80_pct = target_curve.evaluate(0.8)

        # check curve at two points
        if curve_40_pct < target_curve_40_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        elsif curve_40_pct > target_curve_40_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 40% of #{curve_40_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_40_pct.round(2)} for #{target_standard}.")
        end
        if curve_80_pct < target_curve_80_pct * (1.0 - min_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{min_pass_pct * 100} % below the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
        elsif curve_80_pct > target_curve_80_pct * (1.0 + max_pass_pct)
          check_elems <<  OpenStudio::Attribute.new('flag', "The curve value at 80% of #{curve_80_pct.round(2)} for #{component.name} is more than #{max_pass_pct * 100} % above the typical value of #{target_curve_80_pct.round(2)} for #{target_standard}.")
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
