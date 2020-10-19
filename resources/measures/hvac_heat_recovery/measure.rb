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
class HVACHeatRecovery < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC Heat Recovery'
  end

  # human readable description
  def description
    return 'Adds a heat recovery system to all air loops.  Does not replace or update efficiencies for exisitng heat recovery systems.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adds a heat recovery system to all air loops.  Does not replace or update efficiencies for exisitng heat recovery systems.'
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

    no_oa_air_loops = 0
    hx_initial = 0
    run_sizing = false
    model.getAirLoopHVACs.each do |air_loop_hvac|
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      no_oa_air_loops += 1 unless oa_sys.is_initialized
      next unless oa_sys.is_initialized
      has_hx = std.air_loop_hvac_energy_recovery?(air_loop_hvac)
      hx_initial += 1 if has_hx
      next if has_hx
      next if run_sizing
      oa_sys = oa_sys.get
      oa_controller = oa_sys.getControllerOutdoorAir
      unless oa_controller.maximumOutdoorAirFlowRate.is_initialized
        unless oa_controller.autosizedMaximumOutdoorAirFlowRate.is_initialized
          run_sizing = true
        end
      end
    end

    # report initial condition of model
    runner.registerInitialCondition("The model started with #{model.getAirLoopHVACs.size} air loops, of which #{no_oa_air_loops} have no outdoor air and #{hx_initial} already have heat exchangers.")

    if (no_oa_air_loops + hx_initial) >= model.getAirLoopHVACs.size
      runner.registerAsNotApplicable('Model contains no air loops that have outdoor already but do not already contain a heat exchanger.')
      return false
    end

    if run_sizing
      runner.registerInfo('Air loop outdoor air flow rates not sized. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    # apply ERVs to air loops in model
    hx_added = 0
    hx_cfm_added = 0
    air_loops_affected = 0
    model.getAirLoopHVACs.each do |air_loop_hvac|
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      next unless oa_sys.is_initialized
      unless std.air_loop_hvac_energy_recovery?(air_loop_hvac)
        std.air_loop_hvac_apply_energy_recovery_ventilator(air_loop_hvac, '')
        hx_added += 1
        # set heat exchanger efficiency levels
        oa_sys = oa_sys.get
        oa_controller = oa_sys.getControllerOutdoorAir
        if oa_controller.maximumOutdoorAirFlowRate.is_initialized
          oa_flow_m3_per_s = oa_controller.maximumOutdoorAirFlowRate.get
          hx_cfm_added = OpenStudio.convert(oa_flow_m3_per_s, 'm^3/s', 'cfm').get
        else
          oa_flow_m3_per_s = oa_controller.autosizedMaximumOutdoorAirFlowRate.get
          hx_cfm_added = OpenStudio.convert(oa_flow_m3_per_s, 'm^3/s', 'cfm').get
        end
        oa_sys.oaComponents.each do |oa_comp|
          if oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized
            hx = oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.get
            std.heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency(hx)
          end
        end
      end
      air_loops_affected += 1
    end

    # report final condition of model
    runner.registerValue('hvac_number_of_loops_affected', air_loops_affected)
    runner.registerFinalCondition("Added #{hx_added} heat exchangers to air loops with #{hx_cfm_added.round(1)} total cfm.")

    return true
  end
end

# register the measure to be used by the application
HVACHeatRecovery.new.registerWithApplication
