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
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'

# start the measure
class HVACOptimalStartStop < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Optimal Start Stop'
  end

  # human readable description
  def description
    return 'This energy efficiency measure (EEM) queries the outdoor air temperature to determine if the HVAC system can be shut off (up to one hour) early. Additionally, this measure modifies the HVAC system start time, optimizing energy savings by delaying startup as long as possible, while still ensuring that the building will be a comfortable temperature when occupants arrive.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This EEM adds EMS logic to the model that actuates the infiltration, HVAC operation, cooling set point, and heating set point schedules. The measure first identifies the schedule HVAC stopping point by day of week (Saturday, Sunday, and Weekdays). Early HVAC system shutoff is determined entirely by the outdoor air temperature (OAT). If the OAT is less than or equal to 2C or greater than or equal to 18C, then no action is taken. The HVAC system is shut off one hour early when the OAT is between 12C and 18C. The HVAC system shut off time varies linearly with OAT from one hour to zero hours between 12C and 2C, and between 18C and 28C. AvailabilityManager:OptimumStart objects are inserted for each HVAC system in the model and use the AdaptiveASHRAE algorithm to dynamically adjust HVAC startup time each day.'
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

    # build standard to access methods
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    air_loop_count = 0
    air_loop_cfm = 0

    model.getAirLoopHVACs.each do |air_loop|
      if !air_loop.designSupplyAirFlowRate.is_initialized
        runner.registerInfo("Air loop '#{air_loop.name}' does not have a design air flow rate and will not be considered in the total flow rate.")
        next
      end

      next if std.air_loop_hvac_optimum_start_required?(air_loop) == false

      std.air_loop_hvac_enable_optimum_start(air_loop)
      air_loop_m3_per_s = air_loop.designSupplyAirFlowRate.get
      air_loop_count += 1
      air_loop_cfm += OpenStudio.convert(air_loop_m3_per_s, 'm^3/s', 'ft^3/min').get
    end

    if air_loop_count == 0
      runner.registerAsNotApplicable('There are not air loops that meet the requirements for an optimal start.  This measure is not applicable.')
    end

    # Report initial condition of the model
    runner.registerInitialCondition("The model started with #{air_loop_count} air loops subject to modification.")

    # Report final condition of model
    runner.registerFinalCondition("The measure modified the start of #{air_loop_count} air loops.")
    runner.registerValue('hvac_opt_start_cfm', air_loop_cfm, 'cfm')

    return true
  end
end

# this allows the measure to be use by the application
HVACOptimalStartStop.new.registerWithApplication
