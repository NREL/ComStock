# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.


# open the class to add methods to return sizing values
class OpenStudio::Model::PumpConstantSpeed
  # Sets all auto-sizeable fields to autosize
  def autosize
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.sizing.PumpConstantSpeed', ".autosize not yet implemented for #{iddObject.type.valueDescription}.")
  end

  # Takes the values calculated by the EnergyPlus sizing routines
  # and puts them into this object model in place of the autosized fields.
  # Must have previously completed a run with sql output for this to work.
  def applySizingValues
    rated_flow_rate = autosizedRatedFlowRate
    if rated_flow_rate.is_initialized
      setRatedFlowRate(rated_flow_rate.get)
    end

    rated_power_consumption = autosizedRatedPowerConsumption
    if rated_power_consumption.is_initialized
      setRatedPowerConsumption(rated_power_consumption.get)
    end
  end

  # returns the autosized rated flow rate as an optional double
  def autosizedRatedFlowRate
    return model.getAutosizedValue(self, 'Rated Flow Rate', 'm3/s')
  end

  # returns the autosized rated power consumption as an optional double
  def autosizedRatedPowerConsumption
    return model.getAutosizedValue(self, 'Rated Power Consumption', 'W')
  end
end
