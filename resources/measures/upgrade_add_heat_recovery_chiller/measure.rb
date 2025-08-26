# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2023, Alliance for Sustainable Energy, LLC.
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
require 'openstudio'
require 'openstudio-standards'
require 'json'
require 'open3'
require 'csv'
require 'time'

# Code written originally by Matt Dalhausen, with modifications by Amy Allen
# for flexibility to different water side components, and addition of sizing routine.

# TODO:
# add performance curves
# compatability for DH objects and electric boiler in cost calculations
# getting state level average utility rates


# start the measure
class AddHeatRecoveryChiller < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    'Heat Recovery Chiller'
  end

  # human readable description
  def description
    'This measure adds a heat recovery chiller and heat recovery loop to the model. The heat recovery chiller may be an existing chiller or new stand-alone heat recovery chiller. Converting an existing chiller will allow the chiller to rejected heat to the heat recovery loop in addition to the condenser loop. A new chiller will reject heat only to the heat recovery loop. The user may specify how to connect the heat recovery loop to the hot water loop, whether the heat recovery is in series or parallel with existing heating source objects, and optionally decide whether to adjust hot water loop temperatures and add output variables.'
  end

  # human readable description of modeling approach
  def modeler_description
    'This creates a new heat recovery loop that is attached to a tertiary node to an existing chiller or a new chiller. The heat recovery loop consists of the chiller and a water heater mixed object that is also connected to a hot water loop. The heat recovery loop and hot water loop are sized to the same user defined temperature setpoint as well as all hot water coils in the model.'
  end

  def calc_LCC(htg_load, clg_load, scen, htg_type, hrc_cap, params)
    if scen == 'Base'
      chw_energy_use_base = # energy use in kWh
        clg_load.map do |num|
          num / (params['base_chiller_cop'] * params['timestep'] * 1000)
        end
      chw_elec_cost_base = chw_energy_use_base.map { |num| num * params['elec_cost'] }
      chw_energy_cost_base_ann = chw_elec_cost_base.inject(0, :+)
      if htg_type == 'Fuel'
        hhw_energy_use_base = # energy use in kWh
          htg_load.map do |num|
            num / (params['base_boiler_eff'] * params['timestep'] * 1000)
          end
        hhw_energy_cost_base = hhw_energy_use_base.map do |num|
          num * params['btu_per_kWh'] * params['gas_cost_per_btu']
        end
        hhw_energy_cost_base_ann = hhw_energy_cost_base.inject(0, :+)
        hhw_cost_LCC = hhw_energy_cost_base_ann * params['ng_cost_factor']
      elsif htg_type == 'Electricity'
        hhw_energy_use_base = # energy use in kWh
          htg_load.map do |num|
            num / (params['base_elec_boiler_eff'] * params['timestep'] * 1000)
          end
        hhw_energy_cost_base = hhw_energy_use_base.map { |num| num * params['elec_cost'] }
        hhw_energy_cost_base_ann = hhw_energy_cost_base.inject(0, :+)
        hhw_cost_LCC = hhw_energy_cost_base_ann * params['elec_cost_factor']
      end
      # Convert to life cycle cost, expressed as a present value
      lcc = hhw_cost_LCC + chw_energy_cost_base_ann * params['elec_cost_factor']
    elsif scen == 'HRC'
      hrc_loads_clg = clg_load.map { |value| value < hrc_cap ? value : hrc_cap }
      # Clg loads above HRC capacity are carried by the chiller
      chiller_loads_clg = clg_load.map { |value| value >= hrc_cap ? value - hrc_cap : 0 }
      # Heating loads above the HRC capacity are carried by the boiler
      boiler_loads_htg = htg_load.map { |value| value >= hrc_cap ? value - hrc_cap : 0 }
      # Calculate energy use
      hrc_energy_use = # HRC energy use; kWh time series
        hrc_loads_clg.map do |num|
          num / (params['hrc_cop'] * params['timestep'] * 1000)
        end
      hrc_energy_use_ann = hrc_energy_use.inject(0, :+) # kWh
      chiller_energy_use = # chiller energy use; kWh time series
        chiller_loads_clg.map do |num|
          num / (params['base_chiller_cop'] * params['timestep'] * 1000)
        end
      chiller_energy_use_ann = chiller_energy_use.inject(0, :+) # kWh
      if htg_type == 'Fuel'
        boiler_energy_use = # kWh time series
          boiler_loads_htg.map do |num|
            num / (params['base_boiler_eff'] * params['timestep'] * 1000)
          end
        boiler_energy_use_ann = boiler_energy_use.inject(0, :+) # kWh
        scen_htg_cost_ann = boiler_energy_use_ann * params['btu_per_kWh'] * params['gas_cost_per_btu']
        htg_cost_LCC = scen_htg_cost_ann * params['ng_cost_factor']
      elsif htg_type == 'Electricity'
        boiler_energy_use = # kWh time series
          boiler_loads_htg.map do |num|
            num / (params['base_elec_boiler_eff'] * params['timestep'] * 1000)
          end
        boiler_energy_use_ann = boiler_energy_use.inject(0, :+) # kWh
        scen_htg_cost_ann = boiler_energy_use_ann * params['elec_cost']
        htg_cost_LCC = scen_htg_cost_ann * params['elec_cost_factor']
      end
      # Calculate energy cost
      scen_elec_cost_ann = (chiller_energy_use_ann + hrc_energy_use_ann) * params['elec_cost']
      # Calculate capital cost
      hrc_cost = params['hrc_cost_per_ton'] * params['tons_per_watt'] * hrc_cap
      lcc = htg_cost_LCC + scen_elec_cost_ann * params['elec_cost_factor'] + hrc_cost
    end
    lcc
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # create choices vector for model plant loops
    cooling_loop_names = OpenStudio::StringVector.new
    heating_loop_names = OpenStudio::StringVector.new
    cooling_loop_names << 'Inferred From Model'
    heating_loop_names << 'Inferred Hot Water Loop From Model'
    heating_loop_names << 'Inferred Service Hot Water Loop From Model'
    # heating_loop_names << 'Inferred Hot Water Loop And Service Hot Water Loop From Model'
    model.getPlantLoops.each do |plant_loop|
      sizing_plant = plant_loop.sizingPlant
      loop_type = sizing_plant.loopType
      cooling_loop_names << plant_loop.name.to_s if loop_type == 'Cooling'
      heating_loop_names << plant_loop.name.to_s if loop_type == 'Heating'
    end

    # chilled water loop (source side of the heat recovery chiller)
    cooling_loop_name = OpenStudio::Measure::OSArgument.makeChoiceArgument('cooling_loop_name', cooling_loop_names,
                                                                           false, true)
    cooling_loop_name.setDefaultValue('Inferred From Model')
    cooling_loop_name.setDisplayName('Cooling Loop')
    cooling_loop_name.setDescription('Choose the source loop for the heat recovery chiller. Infer From Model will use the chilled water loop by floor area served.')
    args << cooling_loop_name

    # hot water loop (receives heat from heat recovery chiller)
    heating_loop_name = OpenStudio::Measure::OSArgument.makeChoiceArgument('heating_loop_name', heating_loop_names,
                                                                           false, true)
    heating_loop_name.setDefaultValue('Inferred Hot Water Loop From Model')
    heating_loop_name.setDisplayName('Heating Loop')
    heating_loop_name.setDescription('Choose the receipient loop for the heat recovery chiller. Infer From Model will use the largest hot water loop by floor area served.')
    args << heating_loop_name

    # connect with a heat exchanger or storage tank
    chiller_options = OpenStudio::StringVector.new
    chiller_options << 'Add New Chiller'
    chiller_options << 'Use Existing Chiller'

    # create argument for adding a new heat recovery chiller
    chiller_choice = OpenStudio::Measure::OSArgument.makeChoiceArgument('chiller_choice', chiller_options, false, true)
    chiller_choice.setDefaultValue('Add New Chiller')
    chiller_choice.setDisplayName('Add new heat recovery chiller or use existing chiller?')
    chiller_choice.setDescription('The default is to add a new heat recovery chiller, otherwise the user will need to select an existing chiller.')
    args << chiller_choice

    # create argument for new heat recovery chiller size
    new_chiller_size_tons = OpenStudio::Measure::OSArgument.makeDoubleArgument('new_chiller_size_tons', false, false)
    new_chiller_size_tons.setDefaultValue(35.0)
    new_chiller_size_tons.setDisplayName('Preliminary sizing for HRC. Value is updated at end of measure with optimal size.')
    new_chiller_size_tons.setDescription('Only applicable if add_new_chiller is set to true.')
    args << new_chiller_size_tons

    # creat choices for vector for model chillers
    chiller_names = OpenStudio::StringVector.new
    chiller_names << 'Infer From Model'
    model.getChillerElectricEIRs.each do |chiller|
      chiller_names << chiller.name.to_s
    end

    # create argument if converting and existing chiller in the model
    existing_chiller_name = OpenStudio::Measure::OSArgument.makeChoiceArgument('existing_chiller_name', chiller_names,
                                                                               false, true)
    existing_chiller_name.setDefaultValue('Infer From Model')
    existing_chiller_name.setDisplayName('Existing Chiller to Convert')
    existing_chiller_name.setDescription('Only applicable if converting an existing chiller. Choose a chiller to convert to a heat recovery chiller. Infer from model will default to the first chiller on the selected chilled water loop.')
    args << existing_chiller_name

    # create argument for parallel or series
    heating_order_options = OpenStudio::StringVector.new
    heating_order_options << 'Parallel'
    heating_order_options << 'Series'

    # create argument for parallel or series
    heating_order = OpenStudio::Measure::OSArgument.makeChoiceArgument('heating_order', heating_order_options, false,
                                                                       true)
    heating_order.setDefaultValue('Series')
    heating_order.setDisplayName('Hot water loop heat recovery ordering')
    heating_order.setDescription('Choose whether the heat recovery connection is in parallel or series with the existing hot water source object (boiler, heat pump, district heat, etc.).')
    args << heating_order

    # create argument for heat recovery loop temperature, if applicable
    heat_recovery_loop_temperature_f = OpenStudio::Measure::OSArgument.makeDoubleArgument(
      'heat_recovery_loop_temperature_f', false
    )
    heat_recovery_loop_temperature_f.setDefaultValue(145.0)
    heat_recovery_loop_temperature_f.setDisplayName('The heat recovery loop temperature in degrees F')
    args << heat_recovery_loop_temperature_f

    # create argument to optionally reset hot water loop tempeatures
    reset_hot_water_loop_temperature = OpenStudio::Measure::OSArgument.makeBoolArgument(
      'reset_hot_water_loop_temperature', false, false
    )
    reset_hot_water_loop_temperature.setDefaultValue(true)
    reset_hot_water_loop_temperature.setDisplayName('Reset hot water loop temperature?')
    reset_hot_water_loop_temperature.setDescription('If true, the measure will reset the hot water loop temperature to match the heat recovery loop temperature. It WILL NOT reset demand side coil objects, which could cause simulation errors or unmet hours. If the hot water loop is connected to the heat recovery loop by a heat exchanger instead of a storage tank, the hot water loop temperature will instead be reset to the heat recovery loop temperature minus 5F.')
    args << reset_hot_water_loop_temperature

    # create argument to optionally reset heating coil design tempeatures
    reset_heating_coil_design_temp = OpenStudio::Measure::OSArgument.makeBoolArgument(
      'reset_heating_coil_design_temp', false, false
    )
    reset_heating_coil_design_temp.setDefaultValue(true)
    reset_heating_coil_design_temp.setDisplayName('Reset heating coil design temperatures?')
    reset_heating_coil_design_temp.setDescription('If true, the measure will reset the heating coil design temperatures to match the heat recovery loop temperature.')
    args << reset_heating_coil_design_temp

    # enable output variables argument
    enable_output_variables = OpenStudio::Measure::OSArgument.makeBoolArgument('enable_output_variables', false, false)
    enable_output_variables.setDefaultValue(true)
    enable_output_variables.setDisplayName('Enable output variables?')
    args << enable_output_variables

    args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(model), user_arguments)

    cooling_loop_name = runner.getStringArgumentValue('cooling_loop_name', user_arguments)
    heating_loop_name = runner.getStringArgumentValue('heating_loop_name', user_arguments)
    chiller_choice = runner.getStringArgumentValue('chiller_choice', user_arguments)
    new_chiller_size_tons = runner.getDoubleArgumentValue('new_chiller_size_tons', user_arguments)
    existing_chiller_name = runner.getStringArgumentValue('existing_chiller_name', user_arguments)
    heating_order = runner.getStringArgumentValue('heating_order', user_arguments)
    heat_recovery_loop_temperature_f = runner.getDoubleArgumentValue('heat_recovery_loop_temperature_f', user_arguments)
    reset_hot_water_loop_temperature = runner.getBoolArgumentValue('reset_hot_water_loop_temperature', user_arguments)
    reset_heating_coil_design_temp = runner.getBoolArgumentValue('reset_heating_coil_design_temp', user_arguments)
    enable_output_variables = runner.getBoolArgumentValue('enable_output_variables', user_arguments)

    # build standards object to access standards methods
    std = Standard.build('90.1-2013')

    # Check for measure applicability
    boilers =  model.getBoilerHotWaters.size # need this variable later
    chillers = model.getChillerElectricEIRs.size
    dh = model.getDistrictHeatings.size
    htg_plant_obj = boilers + dh

    if (chillers < 1) || (htg_plant_obj < 1)
      runner.registerAsNotApplicable('Either no boilers or no chillers in the model; not applicable.')
      return true
    end

    # subsequent check for water cooled chillers

    # Set params for LCC calcs
    lcc_params = {}

    # Need to check if initialized?
    timestep = model.getTimestep
    timesteps_per_hr = timestep.numberOfTimestepsPerHour

    lcc_params['timestep'] = timesteps_per_hr

    # Set parameter values for sizing
    lcc_params['hrc_cost_per_ton'] = 780 # $/ton, from manufacturer quote
    lcc_params['base_boiler_eff'] = 0.8
    lcc_params['hrc_cop'] = 5.0 # to be refined based on actual equipment and part load value
    lcc_params['base_chiller_cop'] = 5.9 # AA TODO: look up by capacity and IPLV
    lcc_params['elec_cost'] = 0.1296 # $/kWh, May 2025 US commercial average
    gas_cost_per_kcf = 11.76 # $/kcf May 2025 US commercial average
    btu_per_ft3 = 1038 # energy density of natural gas, https://www.eia.gov/tools/faqs/faq.php?id=45&t=8
    lcc_params['gas_cost_per_btu'] = gas_cost_per_kcf / 1000 / btu_per_ft3
    lcc_params['btu_per_kWh'] = 3412.14
    lcc_params['tons_per_watt'] = 0.000284345
    lcc_params['base_elec_boiler_eff'] = 1
    lcc_params['elec_cost_factor'] = 13.62 # FEMP LCCA Handbook 135 Supplement for 2024, evaluated for 20 yrs, commerical electricity US average
    lcc_params['ng_cost_factor'] = 13.75 # FEMP LCCA Handbook 135 Supplement for 2024, evaluated for 20 yrs, commerical NG  US average


    # check the cooling_loop_name argument for reasonableness and assign chilled water loop
    chilled_water_loop = nil
    if cooling_loop_name == 'Inferred From Model'
      max_floor_area_served = 0.0
      model.getPlantLoops.each do |plant_loop|
        sizing_plant = plant_loop.sizingPlant
        loop_type = sizing_plant.loopType
        next unless loop_type == 'Cooling'

        floor_area_served = std.plant_loop_total_floor_area_served(plant_loop)
        if floor_area_served > max_floor_area_served
          chilled_water_loop = plant_loop
          max_floor_area_served = floor_area_served
        end
      end

      if chilled_water_loop.nil?
        runner.registerError('Unable to infer chilled water loop in model.')
        return false
      end
    else
      chilled_water_loop = model.getPlantLoopByName(cooling_loop_name)
      unless chilled_water_loop.is_initialized
        runner.registerError("Chilled water loop #{chilled_water_loop} not found in the model. It may have been removed by another measure.")
        return false
      end

      chilled_water_loop = chilled_water_loop.get
    end

    # check the heating_loop_name argument for reasonableness and assign hot water loop
    hot_water_loop = nil
    hot_water_loops = []
    service_hot_water_loops = []
    model.getPlantLoops.each do |plant_loop|
      sizing_plant = plant_loop.sizingPlant
      loop_type = sizing_plant.loopType
      next unless loop_type == 'Heating'

      if std.plant_loop_swh_loop?(plant_loop)
        service_hot_water_loops << plant_loop
      else
        hot_water_loops << plant_loop
      end
    end

    if heating_loop_name == 'Inferred Hot Water Loop From Model'
      max_floor_area_served = 0.0
      hot_water_loops.each do |plant_loop|
        floor_area_served = std.plant_loop_total_floor_area_served(plant_loop)
        if floor_area_served > max_floor_area_served
          hot_water_loop = plant_loop
          max_floor_area_served = floor_area_served
        end
      end
    elsif heating_loop_name == 'Inferred Service Hot Water Loop From Model'
      hot_water_loop = service_hot_water_loops[0]
    else
      hot_water_loop = model.getPlantLoopByName(heating_loop_name)
      unless hot_water_loop.is_initialized
        runner.registerError("Hot water loop #{hot_water_loop} not found in the model. It may have been removed by another measure.")
        return false
      end
      hot_water_loop = hot_water_loop.get
    end

    # check the chiller argument for reasonableness
    if chiller_choice == 'Add New Chiller'
      heat_recovery_chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
      heat_recovery_chiller.setName('Heat Recovery Chiller')
      heat_recovery_chiller.setReferenceCOP(lcc_params['hrc_cop'])
      chilled_water_loop.addSupplyBranchForComponent(heat_recovery_chiller)

      # set as air cooled as condenser loop may not exist
      heat_recovery_chiller.setCondenserType('WaterCooled')

      # attach to existing condenser water loop
      existing_condenser_loop = nil
      chilled_water_loop.supplyComponents('OS:Chiller:Electric:EIR'.to_IddObjectType).each do |chiller|
        chiller = chiller.to_ChillerElectricEIR.get
        next unless existing_condenser_loop.nil?

        condenser_loop = chiller.condenserWaterLoop
        existing_condenser_loop = condenser_loop.get if condenser_loop.is_initialized
      end

      if existing_condenser_loop.nil?
        runner.registerAsNotApplicable('Existing condenser loop not found in the model. This measure requires an existing chiller in the model to share a condenser loop if selecting a new heat recovery chiller.')
        return true
      end

      existing_condenser_loop.addDemandBranchForComponent(heat_recovery_chiller)

      # check new chiller size for reasonableness
      if new_chiller_size_tons < 0.0
        runner.registerError("New chiller size request #{new_chiller_size_tons} must be greater than zero.")
        return false
      end

      # set new chiller size
      chiller_capacity_w = OpenStudio.convert(new_chiller_size_tons, 'ton', 'W').get
      heat_recovery_chiller.setReferenceCapacity(chiller_capacity_w)

      # may need to add plant equipment operation object here

    elsif chiller_choice == 'Use Existing Chiller'
      if existing_chiller_name == 'Infer From Model'
        chillers = []
        chilled_water_loop.supplyComponents('OS:Chiller:Electric:EIR'.to_IddObjectType).each do |chiller|
          chillers << chiller.to_ChillerElectricEIR.get
        end
        if chillers.empty?
          runner.registerError("Unable to find a chiller on chilled water loop #{chilled_water_loop} not found in the model. It may have been removed by another measure.")
          return false
        else
          # use first chiller on the loop
          heat_recovery_chiller = chillers[0]
        end
      else
        existing_chiller = model.getChillerElectricEIRByName(existing_chiller_name)
        unless existing_chiller.is_initialized
          runner.registerError("Chiller named #{existing_chiller_name} not found in the model. It may have been removed by another measure.")
          return false
        end
        heat_recovery_chiller = existing_chiller.get
      end

      if heat_recovery_chiller.condenserType == 'AirCooled'
        runner.registerAsNotApplicable("Chiller named #{heat_recovery_chiller.name} is an air-cooled chiller. This measure does not support air-cooled chillers. The method works by altering the fraction going to a heat recovery loop versus a condenser loop. With no condenser loop, it won't have the node to have heat recovery. Make your air-cooled chiller a water-cooled chiller, then create a dummy condensor loop. You can set the heat recovery fraction to 1 so the condenser loop never operates.")
        return true
      end
    else
      runner.registerError("Invalid chiller_choice argument #{chiller_choice}.")
      return false
    end

    # check that the chiller heat recovery water flow rate is autosized or greater than zero
    if !heat_recovery_chiller.isDesignHeatRecoveryWaterFlowRateAutosized && heat_recovery_chiller.designHeatRecoveryWaterFlowRate.is_initialized
      flow_rate = heat_recovery_chiller.designHeatRecoveryWaterFlowRate.get
      heat_recovery_chiller.autosizeDesignHeatRecoveryWaterFlowRate if flow_rate.zero?
    end

    # check the heat_recovery_loop_temperature_f argument for reasonableness
    if heat_recovery_loop_temperature_f < 70.0
      runner.registerError("Heat recovery loop temperature #{heat_recovery_loop_temperature_f} is below 70F, which is outside the range of equipment considered in this measure.")
      return false
    elsif heat_recovery_loop_temperature_f < 100.0
      runner.registerWarning("Heat recovery loop temperature #{heat_recovery_loop_temperature_f} is atypical; typical ranges are 100-140F.")
    elsif heat_recovery_loop_temperature_f > 150.0
      runner.registerWarning("Heat recovery loop temperature #{heat_recovery_loop_temperature_f} is atypical; typical ranges are 100-140F.")
    elsif heat_recovery_loop_temperature_f > 180.0
      runner.registerError("Heat recovery loop temperature #{heat_recovery_loop_temperature_f} is above 180F, which is outside the range of equipment considered in this measure.")
      return false
    end

    # optionally reset the hot water plant design sizing and setpoint schedule
    if reset_hot_water_loop_temperature
      new_hot_water_temperature_f = heat_recovery_loop_temperature_f - 5 # Offset to emulate effects of heat exchanger
      new_hot_water_temperature_c = OpenStudio.convert(new_hot_water_temperature_f, 'F', 'C').get

      hot_water_loop_sizing = hot_water_loop.sizingPlant
      hot_water_loop_sizing.setDesignLoopExitTemperature(new_hot_water_temperature_c)
      hot_water_loop_sizing.setLoopDesignTemperatureDifference(OpenStudio.convert(20.0, 'R', 'K').get)
      hw_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                    new_hot_water_temperature_c,
                                                                                    name: "Hot Water Loop #{new_hot_water_temperature_f}F",
                                                                                    schedule_type_limit: 'Temperature')
      hw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hw_temp_sch)
      # #Implement ASHRAE recommended reset; for future use
      # new_high_hot_water_temperature_c = OpenStudio.convert(180, 'F', 'C').get
      # new_low_hot_water_temperature_c = OpenStudio.convert(150, 'F', 'C').get
      # low_oat_c = OpenStudio.convert(20, 'F', 'C').get
      # high_oat_c = OpenStudio.convert(50, 'F', 'C').get
      # hw_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
      # hw_stpt_manager.setSetpointatOutdoorHighTemperature(new_low_hot_water_temperature_c)
      # hw_stpt_manager.setSetpointatOutdoorLowTemperature(new_high_hot_water_temperature_c)
      # hw_stpt_manager.setOutdoorHighTemperature(high_oat_c)
      # hw_stpt_manager.setOutdoorLowTemperature(low_oat_c)
      hw_stpt_manager.setName('Hot Water Loop Setpoint Manager')
      hw_stpt_manager.addToNode(hot_water_loop.supplyOutletNode)
      # runner.registerInfo("Reset hot water temperatures on hot water loop #{hot_water_loop.name} to #{new_hot_water_temperature_f}F.")
    end

    if reset_heating_coil_design_temp
      # change the water heating coils to use heat recovery loop temperature
      runner.registerWarning('Resetting hot water coil temperatures. This measure currently only changes CoilHeatingWater objects. If you have other objects on this loop, you will need to change them manually.')
      hot_water_loop.demandComponents('OS:Coil:Heating:Water'.to_IddObjectType).each do |coil|
        coil = coil.to_CoilHeatingWater.get
        coil.setRatedInletWaterTemperature(OpenStudio.convert(new_hot_water_temperature_f, 'F', 'C').get)
        coil.setRatedOutletWaterTemperature(OpenStudio.convert(new_hot_water_temperature_f - 20.0, 'F', 'C').get)
        # Autosize coils for new temperatures
        coil.autosizeUFactorTimesAreaValue
        coil.autosizeMaximumWaterFlowRate
        coil.autosizeRatedCapacity
      end
    end

    # create the heat recovery loop
    heat_recovery_loop = OpenStudio::Model::PlantLoop.new(model)
    heat_recovery_loop.setName('Heat Recovery Loop')
    heat_recovery_loop.setLoadDistributionScheme('Optimal')
    heat_recovery_loop.setMinimumLoopTemperature(10.0)
    heat_recovery_loop.setMaximumLoopTemperature(85.0)
    heat_recovery_loop_temperature_c = OpenStudio.convert(heat_recovery_loop_temperature_f, 'F', 'C').get
    sizing_plant = heat_recovery_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    sizing_plant.setDesignLoopExitTemperature(heat_recovery_loop_temperature_c)
    sizing_plant.setLoopDesignTemperatureDifference(OpenStudio.convert(20.0, 'R', 'K').get)
    hr_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                  heat_recovery_loop_temperature_c,
                                                                                  name: "Heat Recovery Loop #{heat_recovery_loop_temperature_f}F",
                                                                                  schedule_type_limit: 'Temperature')
    heat_recovery_loop.addDemandBranchForComponent(heat_recovery_chiller.to_HVACComponent.get)

    if chiller_choice == 'Add New Chiller'
      heat_recovery_chiller_outlet_node = heat_recovery_chiller.demandOutletModelObject.get.to_Node.get
      heat_recovery_chiller_outlet_node.setName('Heat Recovery Outlet Node')
      heat_recovery_chiller.setHeatRecoveryLeavingTemperatureSetpointNode(heat_recovery_loop.demandOutletNode)
    elsif chiller_choice == 'Use Existing Chiller'
      heat_recovery_chiller_outlet_node = heat_recovery_chiller.tertiaryOutletModelObject.get.to_Node.get
      heat_recovery_chiller_outlet_node.setName('Heat Recovery Outlet Node')
      heat_recovery_chiller.setHeatRecoveryLeavingTemperatureSetpointNode(heat_recovery_loop.demandOutletNode)
    end

    # create the heat recovery chiller operation scheme and setpoint manager
    hr_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hr_temp_sch)
    hr_stpt_manager.setName('Heat Recovery Loop Leaving Chiller Setpoint Manager')
    hr_stpt_manager.addToNode(heat_recovery_loop.demandOutletNode)

    # create the same setpoint manager on the supply node
    hr_supply_outlet_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hr_temp_sch)
    hr_supply_outlet_stpt_manager.setName('Heat Recovery Loop Supply Setpoint Manager')
    hr_supply_outlet_stpt_manager.addToNode(heat_recovery_loop.supplyOutletNode)

    # create pump
    hr_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    hr_pump.setName("#{heat_recovery_loop.name} Pump")
    hr_pump.setRatedPumpHead(OpenStudio.convert(10.0, 'ftH_{2}O', 'Pa').get)
    hr_pump.setPumpControlType('Intermittent')
    hr_pump.addToNode(heat_recovery_loop.supplyInletNode)

    # add a water heater (storage tank) to the supply side of both hot water loop and heat recovery loop
    water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
    water_heater.setName('Heat Recovery Storage Water Heater')
    water_heater.setHeaterMaximumCapacity(1.0) # 1 watt capacity
    water_heater.setHeaterFuelType('Electricity')
    water_heater.setHeaterThermalEfficiency(1.0)
    water_heater.setOffCycleParasiticFuelConsumptionRate(0.0)
    water_heater.setOffCycleParasiticFuelType('Electricity')
    water_heater.setOnCycleParasiticFuelConsumptionRate(0.0)
    water_heater.setOnCycleParasiticFuelType('Electricity')
    amb_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                   OpenStudio.convert(70.0, 'F',
                                                                                                      'C').get,
                                                                                   name: 'Ambient Temp Sch 70F',
                                                                                   schedule_type_limit: 'Temperature')
    water_heater.setAmbientTemperatureIndicator('Schedule')
    water_heater.setAmbientTemperatureSchedule(amb_temp_sch)
    # ensure water heater object does not heat above the setpoint
    water_heater.setMaximumTemperatureLimit(heat_recovery_loop_temperature_c)
    water_heater.setTankVolume(0.189271) # Setting to a low volume to emulate no storage

    hr_connecting_object = water_heater

    # make the loop connection
    heat_recovery_loop.addSupplyBranchForComponent(hr_connecting_object)

    # setup plant equipment operation scheme
    hr_equipment_heating_operation = OpenStudio::Model::PlantEquipmentOperationHeatingLoad.new(model)
    hr_equipment_cooling_operation = OpenStudio::Model::PlantEquipmentOperationCoolingLoad.new(model)
    hr_equipment_heating_operation.addEquipment(hr_connecting_object)
    hr_equipment_cooling_operation.addEquipment(heat_recovery_chiller)
    heat_recovery_loop.setPlantEquipmentOperationHeatingLoad(hr_equipment_heating_operation)
    heat_recovery_loop.setPlantEquipmentOperationCoolingLoad(hr_equipment_cooling_operation)

    # loop through other chilled water supply components and add them to the operation.
    # makes heat recovery chiller first in the operation scheme to preferentially load this chiller first.
    if chiller_choice == 'Add New Chiller'
      chw_equipment_cooling_operation = OpenStudio::Model::PlantEquipmentOperationCoolingLoad.new(model)
      chw_equipment_cooling_operation.addEquipment(heat_recovery_chiller)
      chilled_water_source_objects = ['OS:Chiller:Electric:EIR']
      chilled_water_loop.supplyComponents.each do |chwsc|
        next unless chilled_water_source_objects.include?(chwsc.iddObject.name)
        next if chwsc.name.to_s == hr_connecting_object.name.to_s

        chw_equipment_cooling_operation.addEquipment(chwsc.to_HVACComponent.get)
      end
      chilled_water_loop.resetPlantEquipmentOperationCoolingLoad
      chilled_water_loop.setPlantEquipmentOperationCoolingLoad(chw_equipment_cooling_operation)
      chilled_water_loop.setLoadDistributionScheme('SequentialLoad')
    end

    # hot water source objects for
    hot_water_source_objects = [
      'OS:Boiler:HotWater',
      'OS:Boiler:Steam',
      'OS:WaterHeater:Mixed',
      'OS:WaterHeater:Stratified',
      'OS:WaterHeater:HeatPump',
      'OS:DistrictHeating:Water', # #AA updated
      'OS:HeatPump:WaterToWater:EquationFit:Heating',
      'OS:HeatPump:PlantLoop:EIR:Heating',
      'OS:SolarCollector:FlatPlate:Water',
      'OS:SolarCollector:IntegralCollectorStorage',
      'OS:SolarCollector:FlatPlate:PhotovoltaicThermal',
      'OS:PlantComponent:TemperatureSource',
      'OS:PlantComponent:UserDefined'
    ]

    # add hr_connecting_object to selected hot water loop
    if heating_order == 'Parallel'
      # add a new supply branch for the connecting object
      hot_water_loop.addSupplyBranchForComponent(hr_connecting_object)

      # setup plant equipment operation on hot water loop
      hw_equipment_operation = OpenStudio::Model::PlantEquipmentOperationHeatingLoad.new(model)
      hw_equipment_operation.addEquipment(hr_connecting_object)

      # loop through other hot water supply components and add them to the operation
      hot_water_source_object_count = 0
      hot_water_loop.supplyComponents.each do |sc|
        next unless hot_water_source_objects.include?(sc.iddObject.name)
        next if sc.name.to_s == hr_connecting_object.name.to_s

        hw_equipment_operation.addEquipment(sc.to_HVACComponent.get)
        hot_water_source_object_count += 1
      end

      # add a warning if adding the heat recovery chiller may have replaced an existing plant equipment operating heating load object
      if hot_water_source_object_count > 1
        runner.registerWarning('This measure may have replaced an existing plant equipment operation scheme. Check the hot water loop equipment ordering to make sure it is still valid.')
      end
      hot_water_loop.setPlantEquipmentOperationHeatingLoad(hw_equipment_operation)
      hot_water_loop.setLoadDistributionScheme('SequentialLoad')
    elsif heating_order == 'Series'
      # infer source object inlet node
      inlet_nodes = []
      hot_water_loop.supplyComponents.each do |sc|
        next unless hot_water_source_objects.include?(sc.iddObject.name)

        if sc.to_WaterToWaterComponent.is_initialized
          sc.to_WaterToWaterComponent.get
          inlet_nodes << sc.to_WaterToWaterComponent.get.supplyInletModelObject.get.to_Node.get
        elsif sc.to_StraightComponent.is_initialized
          sc.to_StraightComponent.get
          inlet_nodes << sc.to_StraightComponent.get.inletModelObject.get.to_Node.get
        elsif sc.to_ZoneHVACComponent.is_initialized
          sc.to_StraightComponent.get
          inlet_nodes << sc.to_ZoneHVACComponent.get.inletNode.get.to_Node.get # #AA confirm that this will work
        end
      end

      # For future implementation
      # # create the same setpoint manager after the connecting object
      # hr_htg_loop_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hr_temp_sch)
      # hr_htg_loop_stpt_manager.setName('Heat Recovery Heating Loop Setpoint Manager')
      # #hr_htg_loop_stpt_manager.addToNode(outlet_node_con)
      # hr_htg_loop_stpt_manager.addToNode(inlet_nodes[0])

      # place the connecting object before the existing source object
      hr_connecting_object.addToNode(inlet_nodes[0])

    else
      runner.registerError("Invalid heating order type #{heating_order}.")
      return false
    end

    # rename plant nodes
    std.rename_plant_loop_nodes(model)

    # Autosize plant loop after changes to heating supply temperatures.
    hot_water_loop.autosizeMaximumLoopFlowRate
    hot_water_loop.autocalculatePlantLoopVolume
    # autosize air loops and terminal units after changes to heating supply temperatures.
    model.getAirLoopHVACs.each do |air_loop|
      air_loop.autosizeDesignSupplyAirFlowRate
      air_loop_sizing = air_loop.sizingSystem
      air_loop_sizing.autosizeCoolingDesignCapacity
      air_loop_sizing.autosizeHeatingDesignCapacity
      air_loop.supplyComponents.each do |sup_comp|
        if sup_comp.to_FanVariableVolume.is_initialized
          fan = sup_comp.to_FanVariableVolume.get
          fan.autosizeMaximumFlowRate
        end
      end
      air_loop.demandComponents.each do |dem_comp|
        next unless dem_comp.to_AirTerminalSingleDuctVAVReheat.is_initialized

        term = dem_comp.to_AirTerminalSingleDuctVAVReheat.get
        term.autosizeMaximumHotWaterOrSteamFlowRate
        term.autosizeFixedMinimumAirFlowRate
        term.autosizeMaximumAirFlowRate
      end
    end

    # add output variables
    if enable_output_variables
      heat_recovery_demand_inlet_node = model.getNodeByName('Heat Recovery Loop Demand Inlet Node').get
      heat_recovery_demand_inlet_node.outputVariables
      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Heat Recovery Loop Demand Inlet Node')
      var.setReportingFrequency('Timestep')

      heat_recovery_demand_outlet_node = model.getNodeByName('Heat Recovery Loop Demand Outlet Node').get
      heat_recovery_demand_outlet_node.outputVariables
      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Heat Recovery Loop Demand Outlet Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Heat Recovery Storage Water Heater Demand Outlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Heat Recovery Storage Water Heater Demand Inlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Mass Flow Rate', model)
      var.setKeyValue('Heat Recovery Storage Water Heater Demand Outlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Mass Flow Rate', model)
      var.setKeyValue('Node 12')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Node 12')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Node 13')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('Chiller Evaporator Cooling Rate', model)
      var.setKeyValue('*')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Hot Water Loop Pump Outlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Mass Flow Rate', model)
      var.setKeyValue('Hot Water Loop Pump Outlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Mass Flow Rate', model)
      var.setKeyValue('Heat Recovery Chiller Demand Inlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Heat Recovery Chiller Demand Inlet Water Node')
      var.setReportingFrequency('Timestep')

      var = OpenStudio::Model::OutputVariable.new('System Node Temperature', model)
      var.setKeyValue('Heat Recovery Chiller Demand Outlet Water Node')
      var.setReportingFrequency('Timestep')

    end

    # Add vars for sizing

    var = OpenStudio::Model::OutputVariable.new('Plant Supply Side Cooling Demand Rate', model)
    var.setKeyValue(chilled_water_loop.name.to_s)
    var.setKeyValue('Chilled Water Loop')
    var.setReportingFrequency('Timestep')

    var = OpenStudio::Model::OutputVariable.new('Plant Supply Side Heating Demand Rate', model)
    var.setKeyValue(hot_water_loop.name.to_s)
    var.setReportingFrequency('Timestep')

    var = OpenStudio::Model::OutputVariable.new('System Node Mass Flow Rate', model)
    var.setKeyValue('Hot Water Loop Pump Outlet Water Node')
    var.setReportingFrequency('Timestep')

    var = OpenStudio::Model::OutputVariable.new('Boiler Part Load Ratio', model)
    var.setKeyValue('*')
    var.setReportingFrequency('Timestep')

    var = OpenStudio::Model::OutputVariable.new('Boiler Efficiency', model)
    var.setKeyValue('*')
    var.setReportingFrequency('Timestep')

    var = OpenStudio::Model::OutputVariable.new('Boiler Heating Rate', model)
    var.setKeyValue('*')
    var.setReportingFrequency('Timestep')

    # Create hash of vars to add
    # vars = Hash.new
    # vars["Heat Recovery Storage Water Heater Demand Outlet Water Node"] = ["System Node Temperature", "System Node Mass Flow Rate"] #need to structure this differently or make it a hash explicitly
    # vars["Heat Recovery Storage Water Heater Demand Inlet Water Node"] = "System Node Temperature"
    # vars["Node 12"] = ["System Node Mass Flow Rate", "System Node Temperature"]
    # vars["Node 13"] = "System Node Temperature"
    # vars["*"] = "Chiller Evaporator Cooling Rate"

    # vars.keys.each do |key|
    # if vars[key].is_a?(Hash)
    # vars[key].each do |val|
    # var = OpenStudio::Model::OutputVariable.new(val, model)
    # end
    # else
    # else
    # runner.registerInfo("key #{key}")
    # var = OpenStudio::Model::OutputVariable.new(hash[key], model)
    # end
    # var.setKeyValue(key)
    # var.setReportingFrequency('Timestep')
    # end
    # Sizing routine for HRC
    ann_loads_run_dir = "#{Dir.pwd}/AnnualHRCLoadsRun"
    ann_loads_sql_path = "#{ann_loads_run_dir}/run/eplusout.sql"
    if File.exist?(ann_loads_sql_path)
      sql_path = OpenStudio::Path.new(ann_loads_sql_path)
      sql = OpenStudio::SqlFile.new(sql_path)
      model.setSqlFile(sql)
    else
      # std.model_run_simulation_and_log_errors(model, ann_loads_run_dir)
      runner.registerInfo('Running an annual simulation to determine thermal loads for HRC.')
      if std.model_run_simulation_and_log_errors(model, ann_loads_run_dir) == false
        runner.registerError('Annual run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    if model.sqlFile.empty?
      runner.registerError('Model did not have an sql file; cannot get loads for sizing HRC.')
      return false
    end
    sql = model.sqlFile.get

    # get weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized && (env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod'))
        ann_env_pd = env_pd
      end
    end

    # add timeseries thermal loads to array
    chw_loads_ts = sql.timeSeries(ann_env_pd, 'Timestep', 'Plant Supply Side Cooling Demand Rate',
                                  chilled_water_loop.name.to_s)
    hhw_loads_ts = sql.timeSeries(ann_env_pd, 'Timestep', 'Plant Supply Side Heating Demand Rate',
                                  hot_water_loop.name.to_s)
    # dhw_loads_ts = sql.timeSeries(ann_env_pd, 'Timestep', 'Plant Supply Side Heating Demand Rate',
    # dhw_loop) #To be included if DHW loop integrated in the future

    # Process results
    if chw_loads_ts.is_initialized
      chw_loads = []
      vals = chw_loads_ts.get.values
      for i in 0..(vals.size - 1)
        chw_loads << vals[i]
      end
    end

    if hhw_loads_ts.is_initialized
      hhw_loads = []
      vals = hhw_loads_ts.get.values
      for i in 0..(vals.size - 1)
        hhw_loads << vals[i]
      end
    end

    # Create combined array of loads
    combined_array = chw_loads.zip(hhw_loads)

    overlap_loads_comb = combined_array.map do |row|
      overlap_load = [row[0], row[1]].min
      row << overlap_load
    end

    overlap_loads = combined_array.map do |row|
      [row[0], row[1]].min
    end


    CSV.open('overlap_loads_comb.csv', 'w') do |csv|
      overlap_loads_comb.each do |row|
        csv << row
      end
    end

    sorted_overlap_loads = overlap_loads.sort.reverse

    max_overlap_load = sorted_overlap_loads[0] # maximum value, sorted in descending order

    puts max_overlap_load

    step_size = (max_overlap_load / 10).floor

    # Calculate estimated baseline energy cost for purpose of evaluation

    htg_type = 'Fuel'
    # treat district heating as fuel for purposes of cost calculation
    # handle electric boilers
    if boilers >= 1
      # if Electric
      # htg_type = 'Electric'
    end

    lcc_base = calc_LCC(hhw_loads, chw_loads, 'Base', htg_type, 0, lcc_params)

    puts lcc_base

    hrc_eval = {}

    # update this so # of steps is 10
    (1...11).each do |step|
      hrc_cap_init = step * step_size
      hrc_cap = [hrc_cap_init, max_overlap_load].min # ensure not exceeding overlap load
      hrc_lcc = calc_LCC(hhw_loads, chw_loads, 'HRC', htg_type, hrc_cap, lcc_params)
      hrc_eval[hrc_cap] = hrc_lcc
    end

    # Find the HRC size corresponding to the minimum life cycle cost
    opt_hrc_size = hrc_eval.key(hrc_eval.values.min)
    heat_recovery_chiller.setReferenceCapacity(opt_hrc_size)
    puts hrc_eval

    true
  end
end

# register the measure to be used by the application
AddHeatRecoveryChiller.new.registerWithApplication
