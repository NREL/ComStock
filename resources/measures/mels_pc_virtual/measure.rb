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

# start the measure
class MelsPcVirtualization < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see
  def name
    return 'Desktops To Thin Clients'
  end

  # human readable description
  def description
    return 'Laptop computers and thin clients are typically much more efficient than desktop computers, providing the same (or better) performance while using less energy.  As a result, switching from desktops to laptops or thin clients can save energy.  Typically, laptops use about 80% less electricity than desktops (1) and thin clients use (77%) less, assuming that servers and server cooling are handled on-site (2).'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Assume that each occupant in the building has a computer.  Assume that 53% of these are desktops, and 47% are laptops (https://ieer.org/wp/wp-content/uploads/2012/03/DOE-2011-Buildings-Energy-DataBook-BEDB.pdf).  Assume that desktops draw 175W at peak, whereas laptops draw 40W and thin clients draw 45W (including data center cooling load).  Calculate the overall building installed electric equipment power in W, then calculate the reduction in W from switching from desktops.  Determine the percent power reduction for the overall building, and apply this percentage to all electric equipment in the building, because electric equipment is not typically identified in a granular fashion.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Argument to run measure
    run_measure = OpenStudio::Measure::OSArgument.makeBoolArgument('run_measure', true)
    run_measure.setDisplayName('Run Measure')
    run_measure.setDescription('Argument to run measure.')
    run_measure.setDefaultValue(true)
    args << run_measure

    # Choice argument to select Laptops or Thin Clients to replace Desktops
    pc_type_chs = OpenStudio::StringVector.new
    pc_type_chs << 'Laptop'
    pc_type_chs << 'ThinClient'
    pc_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('pc_type', pc_type_chs, true)
    pc_type.setDisplayName('PC Type')
    pc_type.setDefaultValue('ThinClient')
    args << pc_type

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    unless runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Return not applicable if not selected to run
    run_measure = runner.getBoolArgumentValue('run_measure', user_arguments)
    unless run_measure
      runner.registerAsNotApplicable("Run measure is #{run_measure}.")
      return false
    end

    # Assign the user inputs to variables
    pc_type = runner.getStringArgumentValue('pc_type', user_arguments)

    # get the total number of occupants in office or computer-heavy space types in the model
    office_space_occupancy = 0
    initial_office_equip_power_w = 0
    office_space_equip_defs = []
    model.getSpaceTypes.each do |space_type|
      puts "cureent space type = #{space_type.name}"
      next unless space_type.standardsSpaceType.is_initialized
      case space_type.standardsSpaceType.get.to_s
      when 'OfficeOpen', 'OfficeGeneral', 'OfficeSmall', 'CompRoomClassRm', 'Conference', 'Point_of_Sale', 'SmallOffice - OpenOffice', 'SmallOffice - ClosedOffice', 'MediumOffice - OpenOffice', 'MediumOffice - ClosedOffice', 'OpenOffice', 'ClosedOffice', 'Point_of_Sale', 'Library', 'Reception', 'IT_Room', 'Office', 'SmallOffice - Conference', 'MediumOffice - Conference', 'WholeBuilding - Md Office', 'WholeBuilding - Sm Office', 'WholeBuilding - Lg Office'
        office_space_occupancy += space_type.getNumberOfPeople(space_type.floorArea)
        space_type.spaces.each do |space|
          initial_office_equip_power_w += space.electricEquipmentPower
          space.electricEquipment.each do |equip|
            equip_def = equip.electricEquipmentDefinition.name.get
            next if office_space_equip_defs.include? equip_def
            office_space_equip_defs << equip_def
          end
        end
        space_type.electricEquipment.each do |equip|
          equip_def = equip.electricEquipmentDefinition.name.get
          next if office_space_equip_defs.include? equip_def
          office_space_equip_defs << equip_def
        end
      end
    end

    # get the total number of occupants in the building
    total_occ = model.getBuilding.numberOfPeople
    runner.registerInfo("Total building occupancy is #{total_occ.round}. Total occupancy of office space types is #{office_space_occupancy.round}.")

    # register as not applicable if the building does not contain office spaces
    if office_space_occupancy == 0
      runner.registerAsNotApplicable('This building contains no office space types, therefore we assume it contains 0 computers.')
      return false
    end

    # register warning if office occupancy is higher than total occupancy
    if office_space_occupancy > total_occ
      runner.registerInfo('Occupancy of office spaces is higher than total building occupancy. Some space type occupancies may have been double counted.')
    end

    # define assumptions
    desktop_power_w = 175
    frac_desktop = 0.53
    thin_client_power_w = 45
    laptop_power_w = 40

    # Determine the total wattage of electric equipment currently in the building
    initial_equip_power_w = model.getBuilding.electricEquipmentPower

    # Calculate the number of desktops currently in the building
    num_desktops = (office_space_occupancy * frac_desktop).round
    runner.registerInitialCondition("The building contains #{office_space_occupancy.round} office workers.  Assuming #{frac_desktop} of them have desktops and that the remainder have laptops or thin clients, there are currently #{num_desktops} desktops in the building.  The building initially has #{initial_office_equip_power_w.round} W of office electric equipment and #{initial_equip_power_w.round} W total electric equipment.")

    # Determine the wattage reduction that would occur from replacing the existing desktops with laptops/thin clients
    if pc_type == 'ThinClient'
      pwr_reduction_w = (desktop_power_w - thin_client_power_w) * num_desktops
      runner.registerInfo("Replacing existing #{desktop_power_w} W desktops with #{thin_client_power_w} W thin clients will save #{pwr_reduction_w.round} W")
    elsif pc_type == 'Laptop'
      pwr_reduction_w = (desktop_power_w - laptop_power_w) * num_desktops
      runner.registerInfo("Replacing existing #{desktop_power_w} W desktops with #{laptop_power_w} W laptops will save #{pwr_reduction_w.round} W")
    end

    # Determine the fraction that all equipment must be reduced by to represent the switch from desktops to another technology.
    # This reduction is spread over the entire building because laptops aren't explicitly identified in the model.
    reduction_fraction = 1 - (pwr_reduction_w / initial_office_equip_power_w)
    if pwr_reduction_w >= initial_equip_power_w
      runner.registerAsNotApplicable('The amount of power reduction calculated is greater than the total installed electric equipment power in the building.  This likely means that not all occupants in the building were assumed to have computers, or that they are already assumed to have laptops, thin clients, or another similarly low power computer.')
      return false
    end

    # Loop through all electric equipment definitions in the building and lower their power by the fraction calculated above.
    office_space_equip_defs.each do |equip_def|
      equip_def = model.getElectricEquipmentDefinitionByName(equip_def).get
      if equip_def.designLevel.is_initialized
        equip_def.setDesignLevel(equip_def.designLevel.get * reduction_fraction)
      elsif equip_def.wattsperSpaceFloorArea.is_initialized
        equip_def.setWattsperSpaceFloorArea(equip_def.wattsperSpaceFloorArea.get * reduction_fraction)
      elsif equip_def.wattsperPerson.is_initialized
        equip_def.setWattsperPerson(equip_def.wattsperPerson.get * reduction_fraction)
      else
        runner.registerWarning("'#{equip_def.name}' has no load values. Its performance was not altered.")
      end
    end

    # Determine the total wattage of electric equipment now in the building.
    final_equip_power_w = model.getBuilding.electricEquipmentPower
    num_thin_clients = num_desktops.round
    runner.registerValue('mels_pc_virtual_num_thin_clients', num_thin_clients)
    runner.registerFinalCondition("After replacing #{num_desktops.round} desktops with #{pc_type}s, the building now has #{final_equip_power_w.round} W of electric equipment.")
    return true
  end
end

# this allows the measure to be used by the application
MelsPcVirtualization.new.registerWithApplication
