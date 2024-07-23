# dependencies
require 'openstudio-standards'

# start the measure
class UpgradeHvacEnableIdealAirLoads < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'UpgradeHvacEnableIdealAirLoads'
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

    # check which zone already include ideal air loads
    existing_ideal_loads = model.getZoneHVACIdealLoadsAirSystems
    runner.registerInitialCondition("The model has #{existing_ideal_loads.size} ideal air loads objects.")

    # dummy standard to access methods in openstudio-standards
    std = Standard.build('90.1-2013')

    # remove existing HVAC
    runner.registerInfo('Removing existing HVAC systems from the model')
    std.remove_hvac(model)

    # add zone hvac ideal load air system objects
    conditioned_zones = []
    model.getThermalZones.each do |zone|
      next if std.thermal_zone_plenum?(zone)
      next if !std.thermal_zone_heated?(zone) && !std.thermal_zone_cooled?(zone)
      conditioned_zones << zone
    end

    # modify design outdoor air object to follow occupancy; ComStock DSOA objects do not have schedules by default
    conditioned_zones.each do |zone|
      sch_ruleset = std.thermal_zones_get_occupancy_schedule(thermal_zones=[zone],
      occupied_percentage_threshold:0.05)
      zone.spaces.each do |space|
        next unless space.designSpecificationOutdoorAir.is_initialized
        dsn_oa = space.designSpecificationOutdoorAir.get
        dsn_oa.setOutdoorAirFlowRateFractionSchedule(sch_ruleset)
      end
    end

    # add ideal air loads
    ideal_loads_objects = std.model_add_ideal_air_loads(model,
                                                        conditioned_zones,
                                                        hvac_op_sch: nil,
                                                        heat_avail_sch: nil,
                                                        cool_avail_sch: nil,
                                                        heat_limit_type: 'NoLimit',
                                                        cool_limit_type: 'NoLimit',
                                                        dehumid_limit_type: 'ConstantSensibleHeatRatio',
                                                        cool_sensible_heat_ratio: 0.75,
                                                        humid_ctrl_type: 'None',
                                                        include_outdoor_air: true,
                                                        enable_dcv: false,
                                                        econo_ctrl_mthd: 'NoEconomizer',
                                                        heat_recovery_type: 'None',
                                                        heat_recovery_sensible_eff: 0.7,
                                                        heat_recovery_latent_eff: 0.65,
                                                        add_output_meters: false)

    # validity checks
    unless ideal_loads_objects
      runner.registerError('Failure in creating ideal loads objects.  See logs from [openstudio.model.Model]. Likely cause is an invalid schedule input or schedule removed from by another measure.')
      return false
    end

    # runner register final conditions of model
    runner.registerFinalCondition("The model has #{ideal_loads_objects.size} ideal air loads objects.")

    return true
  end
end

# this allows the measure to be use by the application
UpgradeHvacEnableIdealAirLoads.new.registerWithApplication
