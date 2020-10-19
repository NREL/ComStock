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

require 'erb'

# start the measure
class ScoutEquipmentCopCalculation < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    return 'Scout Equipment Cop Calculation'
  end

  # human readable description
  def description
    return 'Calculates the annualized efficiency for heating, cooling, ventilation, water heating, and refrigeration equipment in the model. '
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This method calculates the annualized coefficient of performance (Btu out / Btu in) of equipment in the model from the annual simulation.  This is used in Scout as the equipment efficiency for the technology competition categories.'
  end

  # define the arguments that the user will input
  def arguments
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # use the built-in error checking
    # if !runner.validateUserArguments(arguments(), user_arguments)
    #   return false
    # end

    # log variable names
    out_var_names = []

    # HVAC equipment
    out_var_names << 'Boiler Heating Energy'
    out_var_names << 'Boiler Gas Energy'
    out_var_names << 'Chiller Evaporator Cooling Energy'
    out_var_names << 'Chiller Electric Energy'
    out_var_names << 'Cooling Coil Total Cooling Energy'
    out_var_names << 'Cooling Coil Electric Energy'
    out_var_names << 'Heating Coil Heating Energy'
    out_var_names << 'Heating Coil Electric Energy'
    out_var_names << 'Heating Coil Gas Energy'
    out_var_names << 'VRF Heat Pump COP'
    out_var_names << 'VRF Heat Pump Cooling COP'
    out_var_names << 'VRF Heat Pump Heating COP'
    out_var_names << 'VRF Heat Pump Cooling Electric Energy'
    out_var_names << 'VRF Heat Pump Heating Electric Energy'
    # out_var_names << 'Cooling Tower Fan Electric Energy'
    # out_var_names << 'Cooling Tower Fan Electric Power'
    # out_var_names << 'Cooling Tower Heat Transfer Rate'
    # out_var_names << 'Zone Water to Air Heat Pump Total Cooling Energy'
    # out_var_names << 'Zone Water to Air Heat Pump Total Heating Energy'
    # out_var_names << 'Zone Water to Air Heat Pump Electric Energy'

    # water heaters
    out_var_names << 'Water Heater Heating Energy'
    out_var_names << 'Water Heater Gas Energy'
    out_var_names << 'Water Heater Electric Energy'

    # refrigeration equipment
    out_var_names << 'Refrigeration System Total Compressor Electric Energy'
    out_var_names << 'Refrigeration System Total Transferred Load Heat Transfer Energy'
    out_var_names << 'Refrigeration System Total Cases and Walk Ins Heat Transfer Energy'
    out_var_names << 'Refrigeration Compressor Electric Energy'
    out_var_names << 'Refrigeration Compressor Heat Transfer Energy'
    out_var_names << 'Refrigeration System Condenser Heat Transfer Energy'
    out_var_names << 'Refrigeration System Condenser Fan Electric Energy'

    # request the variables
    out_var_names.each do |out_var_name|
      request = OpenStudio::IdfObject.load("Output:Variable,*,#{out_var_name},timestep;").get
      result << request
      runner.registerInfo("Adding output variable for '#{out_var_name}' reporting timestep")
    end

    return result
  end

  # convert openstudio vector to ruby array
  def to_ruby_array(os_vector)
    values = []
    for i in (0..os_vector.size - 1)
      values << os_vector[i]
    end
    return values
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return false
    end

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    sql = runner.lastEnergyPlusSqlFile
    if sql.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sql = sql.get
    model.setSqlFile(sql)

    # Get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
        end
      end
    end

    if ann_env_pd == false
      runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
      return false
    end

    # export out annualized heating and cooling efficiencies for HVAC equipment
    unless model.getBoilerHotWaters.empty?
      total_boiler_heating_energy = 0
      total_boiler_gas_energy = 0
      model.getBoilerHotWaters.each do |boiler|
        total_boiler_heating_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Boiler Heating Energy', boiler.name.to_s).get.values).inject(:+)
        total_boiler_gas_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Boiler Gas Energy', boiler.name.to_s).get.values).inject(:+)
      end
      if total_boiler_gas_energy.zero?
        runner.registerWarning('Boiler hot water gas energy is zero.')
      else
        average_cop = total_boiler_heating_energy / total_boiler_gas_energy
        runner.registerInfo("Boiler hot water average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('boiler_hot_water_average_cop', average_cop, '')
      end
    end

    unless model.getChillerElectricEIRs.empty?
      total_chiller_evaporator_cooling_energy = 0
      total_chiller_electric_energy = 0
      model.getChillerElectricEIRs.each do |chiller|
        total_chiller_evaporator_cooling_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Chiller Evaporator Cooling Energy', chiller.name.to_s).get.values).inject(:+)
        total_chiller_electric_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Chiller Electric Energy', chiller.name.to_s).get.values).inject(:+)
      end
      if total_chiller_electric_energy.zero?
        runner.registerWarning('Chiller electric energy is zero.')
      else
        average_cop = total_chiller_evaporator_cooling_energy / total_chiller_electric_energy
        runner.registerInfo("Chiller average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('chiller_average_cop', average_cop, '')
      end
    end

    unless model.getCoilCoolingDXSingleSpeeds.empty? && model.getCoilCoolingDXTwoSpeeds.empty?
      total_cooling_coil_cooling_energy = 0
      total_cooling_coil_electric_energy = 0
      model.getCoilCoolingDXSingleSpeeds.each do |coil|
        total_cooling_coil_cooling_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Cooling Coil Total Cooling Energy', coil.name.to_s).get.values).inject(:+)
        total_cooling_coil_electric_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Cooling Coil Electric Energy', coil.name.to_s).get.values).inject(:+)
      end
      model.getCoilCoolingDXSingleSpeeds.each do |coil|
        total_cooling_coil_cooling_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Cooling Coil Electric Energy', coil.name.to_s).get.values).inject(:+)
        total_cooling_coil_electric_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Cooling Coil Electric Energy', coil.name.to_s).get.values).inject(:+)
      end
      if total_cooling_coil_electric_energy.zero?
        runner.registerWarning('DX cooling coil electric energy is zero.')
      else
        average_cop = total_cooling_coil_cooling_energy / total_cooling_coil_electric_energy
        runner.registerInfo("DX cooling coil average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('dx_cooling_coil_average_cop', average_cop, '')
      end
    end

    unless model.getCoilHeatingDXSingleSpeeds.empty?
      total_heating_coil_heating_energy = 0
      total_heating_coil_electric_energy = 0
      model.getCoilHeatingDXSingleSpeeds.each do |coil|
        total_heating_coil_heating_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Heating Coil Heating Energy', coil.name.to_s).get.values).inject(:+)
        total_heating_coil_electric_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Heating Coil Electric Energy', coil.name.to_s).get.values).inject(:+)
      end
      if total_heating_coil_electric_energy.zero?
        runner.registerWarning('DX heating coil electric energy is zero.')
      else
        average_cop = total_heating_coil_heating_energy / total_heating_coil_electric_energy
        runner.registerInfo("DX heating coil average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('dx_heating_coil_average_cop', average_cop, '')
      end
    end

    unless model.getCoilHeatingGass.empty?
      total_heating_coil_heating_energy = 0
      total_heating_coil_gas_energy = 0
      model.getCoilHeatingGass.each do |coil|
        total_heating_coil_heating_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Heating Coil Heating Energy', coil.name.to_s).get.values).inject(:+)
        total_heating_coil_gas_energy += to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'Heating Coil Gas Energy', coil.name.to_s).get.values).inject(:+)
      end
      if total_heating_coil_gas_energy.zero?
        runner.registerWarning('Gas heating coil gas energy is zero.')
      else
        average_cop = total_heating_coil_heating_energy / total_heating_coil_gas_energy
        runner.registerInfo("Gas heating coil average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('gas_heating_coil_average_cop', average_cop, '')
      end
    end

    unless model.getAirConditionerVariableRefrigerantFlows.empty?
      total_vrf_cooling_energy = 0
      total_vrf_heating_energy = 0
      total_vrf_cooling_electric_energy = 0
      total_vrf_heating_electric_energy = 0
      model.getAirConditionerVariableRefrigerantFlows.each do |vrf|
        vrf_cooling_cop = to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'VRF Heat Pump Cooling COP', vrf.name.to_s).get.values)
        vrf_heating_cop = to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'VRF Heat Pump Heating COP', vrf.name.to_s).get.values)
        vrf_cooling_electric_energy = to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'VRF Heat Pump Cooling Electric Energy', vrf.name.to_s).get.values)
        vrf_heating_electric_energy = to_ruby_array(sql.timeSeries(ann_env_pd, 'Timestep', 'VRF Heat Pump Heating Electric Energy', vrf.name.to_s).get.values)
        vrf_cooling_energy = vrf_cooling_cop.zip(vrf_cooling_electric_energy).map { |x, y| x * y }
        vrf_heating_energy = vrf_heating_cop.zip(vrf_heating_electric_energy).map { |x, y| x * y }
        total_vrf_cooling_energy += vrf_cooling_energy.inject(:+)
        total_vrf_heating_energy += vrf_heating_energy.inject(:+)
        total_vrf_cooling_electric_energy += vrf_cooling_electric_energy.inject(:+)
        total_vrf_heating_electric_energy += vrf_heating_electric_energy.inject(:+)
      end
      if total_vrf_cooling_electric_energy.zero?
        runner.registerWarning('VRF cooling electric energy is zero.')
      else
        average_cop = total_vrf_cooling_energy / total_vrf_cooling_electric_energy
        runner.registerInfo("VRF cooling average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('vrf_cooling_average_cop', average_cop, '')
      end
      if total_vrf_heating_electric_energy.zero?
        runner.registerWarning('VRF heating electric energy is zero.')
      else
        average_cop = total_vrf_heating_energy / total_vrf_heating_electric_energy
        runner.registerInfo("VRF heating average COP (Btu out / Btu in) is #{average_cop}")
        runner.registerValue('vrf_heating_average_cop', average_cop, '')
      end
    end

    # close the sql file
    sql.close

    return true
  end
end

# register the measure to be used by the application
ScoutEquipmentCopCalculation.new.registerWithApplication
