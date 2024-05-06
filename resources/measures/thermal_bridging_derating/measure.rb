# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2020, Alliance for Sustainable Energy, LLC.
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

require 'tbd'

class ThermalBridgingDerating < OpenStudio::Measure::ModelMeasure

  # Returns measure name
  #
  # @return [String] measure name
  def name
    return 'Thermal Bridging Derating'
  end

  # Returns measure description
  #
  # @return [String] measure description
  def description
    return 'Derates opaque construction thermal resistance for major thermal bridges.'
  end

  # Returns measure modeler description
  #
  # @return [String] measure modeler description
  def modeler_description
    return 'This measure is adapted from the Thermal Bridging and Derating measure. Details, including default psi value sets, are avialble at rd2.github.io/tbd'
  end

  # Returns measure arguments
  #
  # @param model [OpenStudio::Model::Model] An OpenStudio model
  # @return [OpenStudio::Measure::OSArgumentVector] validated arguments
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    # psi value sets are defined in psi.rb on the TBD github repository:
    # https://github.com/rd2/tbd/blob/a250fc0bd1c0db454d21720a68bf6c980d648c8f/lib/tbd/psi.rb#L124
    choices = OpenStudio::StringVector.new
    psi = TBD::PSI.new
    psi.set.keys.each { |k| choices << k.to_s }

    option = OpenStudio::Measure::OSArgument.makeChoiceArgument('option', choices, false)
    option.setDisplayName('Default thermal bridge set')
    option.setDescription("e.g. '90.1.22|steel.m|unmitigated'")
    option.setDefaultValue('poor (BETBG)')
    args << option

    return args
  end

  # Runs the thermal bridging deratign measure
  #
  # @param model [OpenStudio::Model::Model] a model
  # @param runner [OpenStudio::Measure::OSRunner] Measure runner
  # @param [OpenStudio::Measure::OSArgumentVector] args Measure argument list
  # @option args [#to_s] :option ("poor (BETBG)") selected PSI set
  # @return [Bool] whether TBD Measure is successful
  def run(model, runner, args)
    super(model, runner, args)

    argh = {}
    argh[:option] = runner.getStringArgumentValue('option', args)

    return false unless runner.validateUserArguments(arguments(model), args)

    TBD.clean!

    seed = runner.workflow.seedFile
    seed = File.basename(seed.get.to_s) unless seed.empty?
    seed = 'OpenStudio model' if seed.empty? || seed == 'temp_measure_manager.osm'
    argh[:seed] = seed

    tbd = TBD.process(model, argh)

    TBD.exit(runner, argh)
    return true
  end
end

# register the measure to be used by the application
ThermalBridgingDerating.new.registerWithApplication
