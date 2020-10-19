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

# Sources
# https://www.energy.gov/sites/prod/files/2014/02/f8/Motor%20Energy%20Savings%20Potential%20Report%202013-12-4.pdf
# Efficiencies:
# ECM = 75%
# PSC = 45%
# SPM = 30%
# Pages 5 and 16
# In order to calculate the number of fans (and consequently of motors) per walkin, multiple cut sheets were considered, such as:
# http://www.midstatesrefrigsupply.com/assets/bn-tb-uc-walkin-mp2.pdf
# http://www.omniteaminc.com/catalog/adt_let.pdf
# The ratio between Cooling load (Btu/h) and number of fans is variable and the is no clear pattern.
# The following rations were assumed to calculate the number of motors per walkin, for low temperature and medium temperature respectively.
# LT: 10000 Btu/h/fan
# MT: 4000 Btu/h/fan

# start the measure
class RefrigWalkinMotors < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'refrig_walkin_motors'
  end

  # human readable description
  def description
    return 'This measures checks if the model contains refrigeration walk-ins and changes the fan power to a custom fan motor level, such as SPM, PSC, ECM'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure receives the fan motor level from the user. Then it looks for refrigerated walk-ins; it loops through them; it checks the current fan power of each walk-in and it substitutes it with the level chosen by the user.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << 'SPM'
    choices << 'PSC'
    choices << 'ECM'
    fan_choice = OpenStudio::Measure::OSArgument.makeChoiceArgument('fan_choice', choices, true)
    fan_choice.setDisplayName('Fan Motor Power Density:')
    fan_choice.setDefaultValue('ECM')
    args << fan_choice

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if model.getRefrigerationWalkIns.empty?
      runner.registerAsNotApplicable('No refrigerated walkin case is present in the current model, the model will not be altered.')
      return false
    end

    runner.registerInitialCondition("The model contains #{model.getRefrigerationWalkIns.length} refrigerated walkins.")

    # get the fan type
    fan_choice = runner.getStringArgumentValue('fan_choice', user_arguments)

    # define motor power reduction for PSC and ECM improvements
    efficiency_ecm = 0.75
    efficiency_psc = 0.45
    efficiency_spm = 0.3
    psc_over_spm_fraction = efficiency_spm / efficiency_psc
    ecm_over_spm_fraction = efficiency_spm / efficiency_ecm
    ecm_over_psc_fraction = efficiency_psc / efficiency_ecm

    # cooling load per fan
    low_temperature_btuh_per_fan = 10000.0
    medium_temperature_btuh_per_fan = 4000.0

    changed_walkins = 0
    changed_motors = 0
    model.getRefrigerationWalkIns.each do |individual_walkin|
      current_motor_category = individual_walkin.additionalProperties.getFeatureAsString('motor_category')
      next unless current_motor_category.is_initialized
      current_motor_category = current_motor_category.get

      # define walking type as low temperature or medium temperature
      if individual_walkin.operatingTemperature > 0
        btu_h_per_fan = medium_temperature_btuh_per_fan
      else
        btu_h_per_fan = low_temperature_btuh_per_fan
      end
      old_fan_power_w = individual_walkin.ratedCoolingCoilFanPower
      old_cooling_capacity_w = individual_walkin.ratedCoilCoolingCapacity
      old_cooling_capacity_btuh = OpenStudio.convert(old_cooling_capacity_w, 'W', 'Btu/h').get

      case current_motor_category
      when 'ECM'
        runner.registerInfo("Case #{individual_walkin.name} has already #{current_motor_category}s, no higher efficiency is available. The walkin case will not be modified.")
      when 'PSC'
        if fan_choice == 'ECM'
          new_fan_power_w = ecm_over_psc_fraction * old_fan_power_w
          individual_walkin.setRatedCoolingCoilFanPower(new_fan_power_w)
          changed_walkins += 1
          changed_motors += (old_cooling_capacity_btuh / btu_h_per_fan).ceil
          runner.registerInfo("Case #{individual_walkin.name} had #{current_motor_category}s and they were substituted with #{fan_choice}s, changing from #{old_fan_power_w.round} W to #{new_fan_power_w.round} W")
        else
          runner.registerInfo("Case #{individual_walkin.name} already has a fan power efficiency level higher or equal to the one selected.")
        end
      when 'SPM'
        if fan_choice == 'ECM'
          new_fan_power_w = ecm_over_spm_fraction * old_fan_power_w
          individual_walkin.setRatedCoolingCoilFanPower(new_fan_power_w)
          changed_walkins += 1
          changed_motors += (old_cooling_capacity_btuh / btu_h_per_fan).ceil
          runner.registerInfo("Case #{individual_walkin.name} had #{current_motor_category}s and they were substituted with #{fan_choice}s, changing from #{old_fan_power_w.round} W to #{new_fan_power_w.round} W")
        elsif fan_choice == 'PSC'
          new_fan_power_w = psc_over_spm_fraction * old_fan_power_w
          individual_walkin.setRatedCoolingCoilFanPower(new_fan_power_w)
          changed_walkins += 1
          changed_motors += (old_cooling_capacity_btuh / btu_h_per_fan).ceil
          runner.registerInfo("Case #{individual_walkin.name} had #{current_motor_category}s and they were substituted with #{fan_choice}s, changing from #{old_fan_power_w.round} W to #{new_fan_power_w.round} W")
        else
          runner.registerInfo("Case #{individual_walkin.name} already has a fan power efficiency level higher or equal to the one selected.")
        end
      end
      individual_walkin.additionalProperties.setFeature('motor_category', fan_choice)
    end

    if changed_walkins == 0
      runner.registerAsNotApplicable("The refrigerated walkin cases in the current model have already a level of fan power efficiency\n equal or higher than the selected one.\n The model will not be altered.")
      return true
    end

    # reporting final condition of model
    runner.registerFinalCondition("The motors for #{changed_walkins} walkin cases have been upgraded to #{fan_choice}")
    runner.registerValue('refrig_walkin_motors_changed_motors', changed_motors, '#')

    return true
  end
end

# register the measure to be used by the application
RefrigWalkinMotors.new.registerWithApplication
