# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.


# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class ElectrifyKitchenEquipment < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'electrify_kitchen_equipment'
  end

  # human readable description
  def description
    return 'Measure replaces primary gas kitchen equipment with the electric equivalent. Primary kitchen equipment includes griddles, ovens, fryers, steamers, ranges, and stoves. The new equipment will follow the same schedule as the equipment originally in the model.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Measure replaces primary gas kitchen equipment with the electric equivalent. Primary kitchen equipment includes griddles, ovens, fryers, steamers, ranges, and stoves. The new equipment will follow the same schedule as the equipment originally in the model.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # search for kitchen spaces and space types in model by string match
    # this will provide list of kitchen spaces, space types, and number of kitchen spaces
    li_spaces_with_kitchens = []
    li_space_types_with_kitchens = []
    num_kitchens = 0
    model.getSpaces.sort.each do |space|
      if ['kitchen', 'KITCHEN', 'Kitchen'].any? { |word| (space.name.get).include?(word) }
        # append kitchen to list
        li_spaces_with_kitchens << space
        num_kitchens+=1
        # get space type of kitchen and add to list if not already
        kitchen_space_type = space.spaceType.get
        next if li_space_types_with_kitchens.include? kitchen_space_type
        li_space_types_with_kitchens << kitchen_space_type
      end
    end

    electric_equipment_hash = [
      {:equip_type=>"broiler", :elec_design_level_w=>10815.0, :frac_latent=>0.1, :frac_radiant=>0.35, :frac_lost=>0.45},
      {:equip_type=>"fryer", :elec_design_level_w=>14009.0, :frac_latent=>0.1, :frac_radiant=>0.36, :frac_lost=>0.44, :frac_convected=>0.1},
      {:equip_type=>"griddle", :elec_design_level_w=>17116.0, :frac_latent=>0.1, :frac_radiant=>0.39, :frac_lost=>0.41},
      {:equip_type=>"oven", :elec_design_level_w=>12104.0, :frac_latent=>0.1, :frac_radiant=>0.22, :frac_lost=>0.58},
      {:equip_type=>"range", :elec_design_level_w=>21014.0, :frac_latent=>0.1, :frac_radiant=>0.1, :frac_lost=>0.8},
      {:equip_type=>"steamer", :elec_design_level_w=>26964.0, :frac_latent=>0.1, :frac_radiant=>0.1, :frac_lost=>0.79}
    ]

    # measure not applicable if building does not have a kitchen
    if num_kitchens == 0
      runner.registerAsNotApplicable("Building does not have a kitchen; measure is not applicable.")
    end

    # Helper method to extract quantity from the object name
    def get_quantity_from_name(string)
      # quantity = string.match(/\d+(\.\d+)?$/)[0]
      quantity = string.split('=')[1]
      return quantity.to_f
    end

    def get_equip_type_from_name(string)
      equip_type = string.split('_')[1]
      return equip_type
    end 

    replaced_equip_list = []

    # Iterate through each space and get gas equipment
    li_gas_equip = []
    li_space_types_with_kitchens.each do |space_type|
      # loop through each gas equipment
      space_type.gasEquipment.each do |gas_equip|
        # Get the quantity from the gas equipment object name
        quantity = get_quantity_from_name(gas_equip.name.to_s)
        equip_type = get_equip_type_from_name(gas_equip.name.to_s)
        multiplier = gas_equip.multiplier
        modified_name = gas_equip.name.to_s.sub(/^gas_/, '')

        # Remove the gas equipment object
        gas_equip.remove

        # get design level and fractions from hash for current type of equipment
        design_level_w = electric_equipment_hash.find { |equip| equip[:equip_type] == equip_type }&.dig(:elec_design_level_w)
        frac_latent = electric_equipment_hash.find { |equip| equip[:equip_type] == equip_type }&.dig(:frac_latent)
        frac_radiant = electric_equipment_hash.find { |equip| equip[:equip_type] == equip_type }&.dig(:frac_radiant)
        frac_lost = electric_equipment_hash.find { |equip| equip[:equip_type] == equip_type }&.dig(:frac_lost)

        # Create a new electric equipment object
        electric_equip_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
        electric_equip_definition.setName("electric_#{modified_name}")
        electric_equip_definition.setDesignLevel(design_level_w * quantity)
        electric_equip_definition.setFractionLatent(frac_latent)
        electric_equip_definition.setFractionRadiant(frac_radiant)
        electric_equip_definition.setFractionLost(frac_lost)

        electric_equip = OpenStudio::Model::ElectricEquipment.new(electric_equip_definition)
        electric_equip.setName("electric_#{equip_type}_equipment_bldg_quantity=#{quantity}")
        electric_equip.setMultiplier(multiplier)

        replaced_equip_list << "#{quantity} #{equip_type}s"
      end
    end

    runner.registerFinalCondition("Replaced #{replaced_equip_list.join(', ')} with electric appliances.")
    return true
  end
end

# register the measure to be used by the application
ElectrifyKitchenEquipment.new.registerWithApplication
