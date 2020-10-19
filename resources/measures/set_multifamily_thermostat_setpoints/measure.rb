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

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class SetMultifamilyThermostatSetpoints < OpenStudio::Measure::ModelMeasure
  require 'openstudio-standards'
  require_relative 'resources/deer_building_types'
  include DEERBuildingTypes
  require 'csv'

  # human readable name
  def name
    return "Set Multifamily Thermostat Setpoints"
  end

  # human readable description
  def description
    return "Change the thermostat setpoints in multifamily (MFm) residential spaces to one of five typical thermostat setpoint patterns."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Creates new ruleset schedules following one of five typical thermostat setpoint patterns in the DEER MASControl database.  These are equal likelihood, and use an input of 1-5 to determine which schedule set to use. The same schedule applies to all residential space types in the building. "
  end

  # make new schedule ruleset from temperature setpoints
  def make_deer_temperature_setpoint_schedule(model, standard, name, wntr_dsgn_day_value, smr_dsgn_day_value, morning_value, day_value, evening_value, night_value)
    sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sch.setName("#{name}")

    # set design day schedules
    wntr_dsgn_day = OpenStudio::Model::ScheduleDay.new(model)
    smr_dsgn_day  = OpenStudio::Model::ScheduleDay.new(model)
    sch.setWinterDesignDaySchedule(wntr_dsgn_day)
    sch.winterDesignDaySchedule.setName("#{sch.name} Winter Design Day")
    sch.winterDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), wntr_dsgn_day_value)
    sch.setSummerDesignDaySchedule(smr_dsgn_day)
    sch.summerDesignDaySchedule.setName("#{sch.name} Summer Design Day")
    sch.summerDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), smr_dsgn_day_value)

    # set default schedule
    # Morning 6am-9am
    # Day 9am-5pm
    # Evening 5pm-9pm
    # Night 9pm-6am
    sch.defaultDaySchedule.setName("#{sch.name} Default")
    sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 6, 0, 0), night_value)
    sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 9, 0, 0), morning_value)
    sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 17, 0, 0), day_value)
    sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 21, 0, 0), evening_value)
    sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), night_value)

    # set schedule type limits
    sch_type_limits_obj = standard.model_add_schedule_type_limits(model, standard_sch_type_limit: 'Temperature')
    sch.setScheduleTypeLimits(sch_type_limits_obj)
    return sch
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Templates
    templates = [
        'DEER Pre-1975',
        'DEER 1985',
        'DEER 1996',
        'DEER 2003',
        'DEER 2007',
        'DEER 2011',
        'DEER 2014',
        'DEER 2015',
        'DEER 2017',
        'DOE Ref Pre-1980',
        'DOE Ref 1980-2004',
        '90.1-2004',
        '90.1-2007',
        '90.1-2010',
        '90.1-2013',
        'ComStock DOE Ref Pre-1980',
        'ComStock DOE Ref 1980-2004',
        'ComStock 90.1-2004',
        'ComStock 90.1-2007',
        'ComStock 90.1-2010',
        'ComStock 90.1-2013'
    ]

    # Climate Zones
    climate_zones = [
      'ASHRAE 169-2013-1A',
      'ASHRAE 169-2013-1B',
      'ASHRAE 169-2013-2A',
      'ASHRAE 169-2013-2B',
      'ASHRAE 169-2013-3A',
      'ASHRAE 169-2013-3B',
      'ASHRAE 169-2013-3C',
      'ASHRAE 169-2013-4A',
      'ASHRAE 169-2013-4B',
      'ASHRAE 169-2013-4C',
      'ASHRAE 169-2013-5A',
      'ASHRAE 169-2013-5B',
      'ASHRAE 169-2013-5C',
      'ASHRAE 169-2013-6A',
      'ASHRAE 169-2013-6B',
      'ASHRAE 169-2013-7A',
      'ASHRAE 169-2013-8A',
      'CEC T24-CEC1',
      'CEC T24-CEC2',
      'CEC T24-CEC3',
      'CEC T24-CEC4',
      'CEC T24-CEC5',
      'CEC T24-CEC6',
      'CEC T24-CEC7',
      'CEC T24-CEC8',
      'CEC T24-CEC9',
      'CEC T24-CEC10',
      'CEC T24-CEC11',
      'CEC T24-CEC12',
      'CEC T24-CEC13',
      'CEC T24-CEC14',
      'CEC T24-CEC15',
      'CEC T24-CEC16'
    ]

    # Make an argument for the as-built template
    template_chs = OpenStudio::StringVector.new
    templates.each do |template|
      template_chs << template
    end

    # Make an argument for the template
    template = OpenStudio::Measure::OSArgument.makeChoiceArgument('template', template_chs, true)
    template.setDisplayName('Template')
    template.setDescription('Vintage year lookup for thermostat setpoint schedules.')
    template.setDefaultValue('DEER 1985')
    args << template

    # Make an argument for the climate zone
    climate_zone_chs = OpenStudio::StringVector.new
    climate_zones.each do |climate_zone|
      climate_zone_chs << climate_zone
    end
    climate_zone = OpenStudio::Measure::OSArgument.makeChoiceArgument('climate_zone', climate_zone_chs, true)
    climate_zone.setDisplayName('Climate Zone')
    climate_zone.setDefaultValue('CEC T24-CEC9')
    args << climate_zone

    # Make an argument for the climate zone
    tstat_index_chs = OpenStudio::StringVector.new
    tstat_index_chs << '1'
    tstat_index_chs << '2'
    tstat_index_chs << '3'
    tstat_index_chs << '4'
    tstat_index_chs << '5'
    tstat_index = OpenStudio::Measure::OSArgument.makeChoiceArgument('tstat_index', tstat_index_chs, true)
    tstat_index.setDisplayName('Thermostat Setpoint Schedule Index')
    tstat_index.setDescription('Select one of five thermostat setpoint schedules to apply.')
    tstat_index.setDefaultValue('1')
    args << tstat_index

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables that can be accessed across the measure
    template = runner.getStringArgumentValue('template', user_arguments)
    climate_zone = runner.getStringArgumentValue('climate_zone', user_arguments)
    tstat_index  = runner.getStringArgumentValue('tstat_index', user_arguments)
    vintage = template_to_vintage[template]
    cz = climate_zone_to_short[climate_zone]

    # Not applicable if the building is not MFm
    standards_building_type = ''
    if model.getBuilding.standardsBuildingType.is_initialized
      standards_building_type = model.getBuilding.standardsBuildingType.get
    end
    unless standards_building_type == 'MFm'
      runner.registerAsNotApplicable("The standards building type '#{standards_building_type}' is not 'MFm'; no changes will be made.")
      return true
    end

    # load lookup file and convert to hash table
    setpoint_lookup = "#{File.dirname(__FILE__)}/resources/MASControl3A_ParamTStat.csv"
    if not File.file?(setpoint_lookup)
      runner.registerError("Unable to find file: #{setpoint_lookup}")
      return nil
    end
    setpoint_lookup = CSV.table(setpoint_lookup)
    setpoint_lookup_hsh_arr = setpoint_lookup.map { |row| row.to_hash }

    # select row from inputs
    setpoint_lookup_hsh_arr = setpoint_lookup_hsh_arr.select { |h| h[:vintyear].to_s == vintage.to_s }
    setpoint_lookup_hsh_arr = setpoint_lookup_hsh_arr.select { |h| h[:bldgloc] == cz }
    setpoint_lookup_hsh_arr = setpoint_lookup_hsh_arr.select { |h| h[:tstat].to_i == tstat_index.to_i }
    setpoint_lookup_hsh = setpoint_lookup_hsh_arr[0]

    # convert values to celsius
    htg_dsgn_value = OpenStudio.convert(68.0, 'F', 'C').get
    htg_morning_value = OpenStudio.convert(setpoint_lookup_hsh[:tstathtgmrn].to_f, 'F', 'C').get
    htg_day_value = OpenStudio.convert(setpoint_lookup_hsh[:tstathtgday].to_f, 'F', 'C').get
    htg_evening_value = OpenStudio.convert(setpoint_lookup_hsh[:tstathtgeve].to_f, 'F', 'C').get
    htg_night_value = OpenStudio.convert(setpoint_lookup_hsh[:tstathtgnit].to_f, 'F', 'C').get
    wntr_dsgn_value = OpenStudio.convert(78.0, 'F', 'C').get
    clg_morning_value = OpenStudio.convert(setpoint_lookup_hsh[:tstatclgmrn].to_f, 'F', 'C').get
    clg_day_value = OpenStudio.convert(setpoint_lookup_hsh[:tstatclgday].to_f, 'F', 'C').get
    clg_evening_value = OpenStudio.convert(setpoint_lookup_hsh[:tstatclgeve].to_f, 'F', 'C').get
    clg_night_value = OpenStudio.convert(setpoint_lookup_hsh[:tstatclgnit].to_f, 'F', 'C').get

    # make a standard
    reset_log
    standard = Standard.build("#{template}")

    # create heating and cooling schedules from hash
    htg_stpt_sch = make_deer_temperature_setpoint_schedule(model,
                                                           standard,
                                                           "MFm Res Htg Temperature Setpoint Schedule Variation #{tstat_index}",
                                                           htg_dsgn_value,
                                                           htg_dsgn_value,
                                                           htg_morning_value,
                                                           htg_day_value,
                                                           htg_evening_value,
                                                           htg_night_value)
    clg_stpt_sch = make_deer_temperature_setpoint_schedule(model,
                                                           standard,
                                                           "MFm Res Clg Temperature Setpoint Schedule Variation #{tstat_index}",
                                                           wntr_dsgn_value,
                                                           wntr_dsgn_value,
                                                           clg_morning_value,
                                                           clg_day_value,
                                                           clg_evening_value,
                                                           clg_night_value)

   runner.registerInfo("Created MFm Res Htg and Clg Temperature Setpoint Schedules for vintage '#{vintage}', climate zone #{cz}, and variation #{tstat_index}.")

    num_zones = 0
    # apply new schedules to zones with 'ResBedroom' or 'ResLiving' standards space types
    model.getThermalZones.each do |zone|
      apply_new_schedules = false
      zone.spaces.each do |space|
        next unless space.spaceType.is_initialized
        space_type = space.spaceType.get
        next unless space_type.standardsSpaceType.is_initialized
        standards_space_type = space_type.standardsSpaceType.get
        if standards_space_type == 'ResBedroom' || standards_space_type == 'ResLiving'
          apply_new_schedules = true
          break
        end
      end

      if apply_new_schedules
        unless !zone.thermostatSetpointDualSetpoint.is_initialized
          # set new thermostat schedule
          thermostat = zone.thermostatSetpointDualSetpoint.get
          thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
          thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
          num_zones += 1
        end
      end
    end
    runner.registerInfo("Applied new thermostat schedules to #{num_zones} zones.")
    
    log_messages_to_runner(runner, debug = false)
    reset_log
  end
end

# register the measure to be used by the application
SetMultifamilyThermostatSetpoints.new.registerWithApplication
