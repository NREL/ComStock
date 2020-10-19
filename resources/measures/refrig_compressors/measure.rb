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

require 'json'

# start the measure
class RefrigCompressors < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'refrig_compressors'
  end

  # human readable description
  def description
    return 'This measure substitutes refrigeration compressor curves with more efficient ones.'
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measures looks for refrigeration compressors, checks the efficiency level and changes the curves with more efficient ones.
            - It starts looping through each refrigeration system.
            - For each of them it checks if it is Low Temperature or Medium Temperature, checking the operating temperature of a refrigeration case or walkin.
            - It checks what is the refrigerant for the system. This measure works only for the following refrigerants: 507, 404a, R22.
            - It extracts the compressors from the JSON file, corresponding to the appropriate system type (LT/MT) and refrigerant.
            - The following compressors were employed (https://climate.emerson.com/online-product-information/OPIServlet):
                  MT:  404 -> Copeland ZS33KAE-PFV (single phase, 200/240 V, 60HZ)
                       507 -> Copeland ZS33KAE-PFV (single phase, 200/240 V, 60HZ)
                       R22 -> Copeland CS18K6E-PFV (single phase, 200/240 V, 60HZ)
                  LT:  404 -> Copeland RFT32C1E-CAV (single phase, 200/240 V, 60HZ)
                       507 -> Copeland ZF15K4E-PFV (single phase, 200/240 V, 60HZ)
                       R22 -> Copeland LAHB-0311-CAB (single phase, 200/240 V, 60HZ)
               The EER for each compressor is listed in the JSON file.
            - Then the current compressors listed in the model are analyzed. The EERs are calculated and the average EER for the whole compressor rack is calculated.
            - If the average current EER is lower than the referenced EER in the JSON file, the compressors in the system are stripped away.
            - The total compressor capacity is calculated and the proper number of new, more efficient compressors is added to the system.
            - The EER and the total compressor capacities are calculated using power and capacity curves at the rating conditions (http://www.ahrinet.org/App_Content/ahri/files/STANDARDS/AHRI/AHRI_Standard_540_I-P_and_SI_2015.pdf)."
  end

  def curve_calculation(model, power_or_capacity_curve, t_c, t_e)
    c1 = power_or_capacity_curve.coefficient1Constant
    c2 = power_or_capacity_curve.coefficient2x
    c3 = power_or_capacity_curve.coefficient3xPOW2
    c4 = power_or_capacity_curve.coefficient4y
    c5 = power_or_capacity_curve.coefficient5yPOW2
    c6 = power_or_capacity_curve.coefficient6xTIMESY
    c7 = power_or_capacity_curve.coefficient7xPOW3
    c8 = power_or_capacity_curve.coefficient8yPOW3
    c9 = power_or_capacity_curve.coefficient9xPOW2TIMESY
    c10 = power_or_capacity_curve.coefficient10xTIMESYPOW2
    power_or_capacity = c1 + c2 * t_e + c3 * (t_e**2) + c4 * t_c + c5 * (t_c**2) + c6 * (t_e * t_c) + c7 * (t_e**3) + c8 * (t_c**3) + c9 * t_c * (t_e**2) + c10 * t_e * (t_c**2)
    return power_or_capacity
  end

  def build_compressor_object(model, compressor_data, system_name, return_gas_temp_ip)
    curve_power = OpenStudio::Model::CurveBicubic.new(model)
    curve_power.setName(system_name + ' power')

    curve_power.setCoefficient1Constant(compressor_data['power']['c1'])
    curve_power.setCoefficient2x(compressor_data['power']['c2'])
    curve_power.setCoefficient3xPOW2(compressor_data['power']['c3'])
    curve_power.setCoefficient4y(compressor_data['power']['c4'])
    curve_power.setCoefficient5yPOW2(compressor_data['power']['c5'])
    curve_power.setCoefficient6xTIMESY(compressor_data['power']['c6'])
    curve_power.setCoefficient7xPOW3(compressor_data['power']['c7'])
    curve_power.setCoefficient8yPOW3(compressor_data['power']['c8'])
    curve_power.setCoefficient9xPOW2TIMESY(compressor_data['power']['c9'])
    curve_power.setCoefficient10xTIMESYPOW2(compressor_data['power']['c10'])
    curve_power.setMinimumValueofx(compressor_data['power']['minX'])
    curve_power.setMaximumValueofx(compressor_data['power']['maxX'])
    curve_power.setMinimumValueofy(compressor_data['power']['minY'])
    curve_power.setMaximumValueofy(compressor_data['power']['maxY'])
    curve_power.setInputUnitTypeforX(compressor_data['power']['typex'])
    curve_power.setInputUnitTypeforY(compressor_data['power']['typey'])
    curve_power.setOutputUnitType(compressor_data['power']['typeoutput'])

    curve_capacity = OpenStudio::Model::CurveBicubic.new(model)
    curve_capacity.setName(system_name + ' capacity')
    curve_capacity.setCoefficient1Constant(compressor_data['capacity']['c1'])
    curve_capacity.setCoefficient2x(compressor_data['capacity']['c2'])
    curve_capacity.setCoefficient3xPOW2(compressor_data['capacity']['c3'])
    curve_capacity.setCoefficient4y(compressor_data['capacity']['c4'])
    curve_capacity.setCoefficient5yPOW2(compressor_data['capacity']['c5'])
    curve_capacity.setCoefficient6xTIMESY(compressor_data['capacity']['c6'])
    curve_capacity.setCoefficient7xPOW3(compressor_data['capacity']['c7'])
    curve_capacity.setCoefficient8yPOW3(compressor_data['capacity']['c8'])
    curve_capacity.setCoefficient9xPOW2TIMESY(compressor_data['capacity']['c9'])
    curve_capacity.setCoefficient10xTIMESYPOW2(compressor_data['capacity']['c10'])
    curve_capacity.setMinimumValueofx(compressor_data['capacity']['minX'])
    curve_capacity.setMaximumValueofx(compressor_data['capacity']['maxX'])
    curve_capacity.setMinimumValueofy(compressor_data['capacity']['minY'])
    curve_capacity.setMaximumValueofy(compressor_data['capacity']['maxY'])
    curve_capacity.setInputUnitTypeforX(compressor_data['capacity']['typex'])
    curve_capacity.setInputUnitTypeforY(compressor_data['capacity']['typey'])
    curve_capacity.setOutputUnitType(compressor_data['capacity']['typeoutput'])

    # build compressor
    compressor = OpenStudio::Model::RefrigerationCompressor.new(model)
    compressor.setName(system_name)
    compressor.setRefrigerationCompressorPowerCurve(curve_power)
    compressor.setRefrigerationCompressorCapacityCurve(curve_capacity)
    compressor.setRatedReturnGasTemperature(OpenStudio.convert(return_gas_temp_ip, 'F', 'C').get)

    return compressor
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if model.getRefrigerationSystems.empty?
      runner.registerAsNotApplicable('No refrigeration systems are present in the model.')
      return false
    end

    # temperature to distinguish low temperature from medium temperature
    system_threshold_temperature_f = 14.0
    evaporator_temperature_f = 20.0
    evaporator_temperature_c = OpenStudio.convert(evaporator_temperature_f, 'F', 'C').get
    condenser_temperature_f = 110.0
    condenser_temperature_c = OpenStudio.convert(condenser_temperature_f, 'F', 'C').get
    total_cooling_load_w = 0.0
    systems_modified = []
    model.getRefrigerationSystems.each do |system|
      refrigerant = system.refrigerationSystemWorkingFluidType

      # check the temperature of the system
      if system.cases[0]
        operating_temperature_c = system.cases[0].caseOperatingTemperature
      else
        operating_temperature_c = system.walkins[0].operatingTemperature
      end

      # define the system type
      if operating_temperature_c < OpenStudio.convert(system_threshold_temperature_f, 'F', 'C').get
        system_type = 'LT'
      else
        system_type = 'MT'
      end

      case refrigerant
        when 'R507', '507', 'R507a', '507a'
          compressor_type = system_type + '_507'
        when 'R404', '404', 'R404a', '404a'
          compressor_type = system_type + '_404'
        when 'R22', '22'
          compressor_type = system_type + '_R22'
        else
          next
      end

      # Define return gas T
      if compressor_type == 'MT_R22' || compressor_type == 'LT_404'
        return_gas_temperature_f = 40.0
      else
        return_gas_temperature_f = 65.0
      end

      compressors_data = JSON.parse(File.read(File.dirname(__FILE__) + '/resources/curves.json'))
      compressor_for_this_system = compressors_data[compressor_type]
      reference_rated_eer = compressor_for_this_system['EER'].to_f
      reference_compressor = build_compressor_object(model, compressor_for_this_system, compressor_type, return_gas_temperature_f)
      reference_rated_power_w = curve_calculation(model, reference_compressor.refrigerationCompressorPowerCurve, condenser_temperature_c, evaporator_temperature_c)
      reference_rated_capacity_btuh = curve_calculation(model, reference_compressor.refrigerationCompressorCapacityCurve, condenser_temperature_c, evaporator_temperature_c)

      system_eer = []
      system_capacity = []
      system.compressors.each do |compressor|
        power_in_w = curve_calculation(model, compressor.refrigerationCompressorPowerCurve, condenser_temperature_c, evaporator_temperature_c)
        capacity_in_btuh = curve_calculation(model, compressor.refrigerationCompressorCapacityCurve, condenser_temperature_c, evaporator_temperature_c)
        system_capacity << capacity_in_btuh
        capacity_in_w = OpenStudio.convert(capacity_in_btuh, 'Btu/h', 'W').get
        current_compressor_eer_si = capacity_in_w / power_in_w
        system_eer << current_compressor_eer_si
      end
      mean_current_eer = system_eer.inject { |sum, el| sum + el }.to_f / system_eer.size

      if mean_current_eer < reference_rated_eer
        number_of_compressors_to_displace = (system_capacity.inject(0) { |sum, x| sum + x } / reference_rated_capacity_btuh).floor
        system.removeAllCompressors
        i = 0
        while i < number_of_compressors_to_displace
          new_compressor = reference_compressor.clone.to_RefrigerationCompressor.get
          new_compressor.setName(new_compressor.name.get + '_' + i.to_s)
          system.addCompressor(new_compressor)
          i += 1
        end
        systems_modified << system

        # get system cooling load
        system.cases.each do |ref_case|
          total_cooling_load_w += ref_case.ratedTotalCoolingCapacityperUnitLength * ref_case.caseLength
        end
        system.walkins.each do |walkin|
          total_cooling_load_w += walkin.ratedCoilCoolingCapacity
        end
        mean_current_eer_btuh_per_w = OpenStudio.convert(mean_current_eer, 'W', 'Btu/h').get
        reference_rated_eer_btuh_per_w = OpenStudio.convert(reference_rated_eer, 'W', 'Btu/h').get
        runner.registerInfo("The compressors originally in the model had an EER = #{mean_current_eer_btuh_per_w.round(3)} Btu/hr-W (average for the whole compressor rack).")
        runner.registerInfo("The new compressors have an EER = #{reference_rated_eer_btuh_per_w.round(3)} Btu/hr-W.")
      end
    end

    if systems_modified.empty?
      runner.registerAsNotApplicable('No refrigeration compressors has been changed, because the compressors in the model are already efficient or the the refrigerant is not 507, 404a or R22.')
      return false
    end

    total_cooling_load_tons = OpenStudio.convert(total_cooling_load_w, 'W', 'ton').get
    runner.registerFinalCondition("#{systems_modified.size} systems have meed modified with more efficient compressors.")
    runner.registerValue('refrig_compressor_ton_refrigeration', total_cooling_load_tons, 'ton')

    return true
  end
end

# register the measure to be used by the application
RefrigCompressors.new.registerWithApplication
