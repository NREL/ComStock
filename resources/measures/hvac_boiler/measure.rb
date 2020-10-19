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

# dependencies
require 'openstudio-standards'

# start the measure
class HVACBoiler < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'hvac_boiler'
  end

  # human readable description
  def description
    return 'This measure gets an AFUE from the user, it compares it with current boilers in the model and increases the boilers AFUE in case it is lower than the chosen one.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure gets a value from the use, it loops through each boiler, it gets the thermal efficiency of each boiler.
            It is assumed AFUE = ThermalEfficiency, as indicated in the OpenStudio Standards.
            For each boiler, If the chosen AFUE is higher than the current boiler thermal efficiency, the latter is upgraded with the chosen AFUE.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << '81 (2019 Code Compliant Boiler)'
    choices << '83 (High Efficiency Boiler)'
    choices << '94 (Condensing Efficiency Boiler)'
    afue = OpenStudio::Measure::OSArgument.makeChoiceArgument('afue', choices, true)
    afue.setDisplayName('Annual Fuel Use Efficiency')
    afue.setDefaultValue('94 (Condensing Efficiency Boiler)')
    args << afue

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if model.getBoilerHotWaters.empty?
      runner.registerAsNotApplicable('Model does not contain boilers.')
      return false
    end

    # standard template
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    # assign the user inputs to variables
    afue_user_string = runner.getStringArgumentValue('afue', user_arguments)
    case afue_user_string
      when '81 (2019 Code Compliant Boiler)'
        afue_user = 0.81
      when '83 (High Efficiency Boiler)'
        afue_user = 0.83
      when '94 (Condensing Efficiency Boiler)'
        afue_user = 0.94
    end

    # condensing boiler loop temperatures
    condensing_loop_temp_f = 140
    condensing_loop_temp_c = OpenStudio.convert(condensing_loop_temp_f, 'F', 'C').get

    boilers_upgraded = []
    total_boiler_capacity_w = 0
    run_sizing = false
    model.getBoilerHotWaters.each do |boiler|
      next unless boiler.fuelType == 'NaturalGas'
      existing_efficiency = boiler.nominalThermalEfficiency
      case afue_user
        when afue_user <= existing_efficiency
          runner.registerInfo("Boiler #{boiler.name} existing efficiency #{existing_efficiency.round(2)} is greater than selected AFUE #{afue_user_string}.")
        else
          boiler.setNominalThermalEfficiency(afue_user)
          runner.registerInfo("Boiler #{boiler.name} existing AFUE changed from #{existing_efficiency.round(2)} to #{afue_user}.")
          boilers_upgraded << boiler

          # change loop design temperature if it is a condensing boiler
          if afue_user > 0.9
            runner.registerInfo("Boiler #{boiler.name} is a condensing boiler. Changing plant loop, setpoint manager, and hot water coil design sizing temperatures to #{condensing_loop_temp_f.round} F.")
            run_sizing = true
            plant_loop = boiler.plantLoop.get

            # plant sizing
            plant_loop.sizingPlant.setDesignLoopExitTemperature(condensing_loop_temp_c)
            dsgn_temp_delt_k = plant_loop.sizingPlant.loopDesignTemperatureDifference
            dsgn_return_temp_c = condensing_loop_temp_c - dsgn_temp_delt_k

            # replace setpoint manager
            plant_loop.supplyOutletNode.setpointManagers.each(&:remove)
            hw_temp_sch = std.model_add_constant_schedule_ruleset(model,
                                                                  condensing_loop_temp_c,
                                                                  name = "#{plant_loop.name} Temp - #{condensing_loop_temp_f.round(0)}F")
            hw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hw_temp_sch)
            hw_stpt_manager.setName("#{plant_loop.name} Setpoint Manager")
            hw_stpt_manager.addToNode(plant_loop.supplyOutletNode)

            # hot water coils
            plant_loop.demandComponents.each do |dc|
              next unless dc.to_CoilHeatingWater.is_initialized
              coil = dc.to_CoilHeatingWater.get
              coil.setRatedInletWaterTemperature(condensing_loop_temp_c)
              coil.setRatedOutletWaterTemperature(dsgn_return_temp_c)
            end
          end

          # get boiler sizing
          next if run_sizing
          if boiler.nominalCapacity.is_initialized
            total_boiler_capacity_w += boiler.nominalCapacity.get
          elsif boiler.autosizedNominalCapacity.is_initialized
            total_boiler_capacity_w += boiler.autosizedNominalCapacity.get
          else
            run_sizing = true
          end
      end
    end

    if boilers_upgraded.empty?
      runner.registerAsNotApplicable('No boiler has been changed because the fuel is not Gas, or the AFUE is already higher than the chosen one.')
      return false
    end

    # standard template
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    # perform a sizing run if needed
    if run_sizing
      runner.registerInfo('At least one boiler design capacity is not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end

      # get capacity of all boilers
      total_boiler_capacity_w = 0
      boilers_upgraded.each do |boiler|
        if boiler.nominalCapacity.is_initialized
          total_boiler_capacity_w += boiler.nominalCapacity.get
        elsif boiler.autosizedNominalCapacity.is_initialized
          total_boiler_capacity_w += boiler.autosizedNominalCapacity.get
        else
          runner.registerError("Unable to get boiler '#{boiler.name}' design sizing.")
          return false
        end
      end
    end

    runner.registerFinalCondition("#{boilers_upgraded.size} boilers upgraded to #{afue_user_string}.")
    total_boiler_capacity_btuh = OpenStudio.convert(total_boiler_capacity_w, 'W', 'Btu/hr').get
    runner.registerValue('hvac_boiler_nominal_capacity_of_upgraded_boilers', total_boiler_capacity_btuh / 1000.0, 'kBtu/h')

    return true
  end
end

# register the measure to be used by the application
HVACBoiler.new.registerWithApplication
