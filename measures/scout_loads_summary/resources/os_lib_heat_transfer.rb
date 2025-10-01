# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
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

require_relative('os_lib_sql_file')
require 'matrix'

module OsLib_HeatTransfer
  def self.internal_convective_gain_outputs
    return [
      'Zone People Convective Heating Energy',
      'Zone Lights Convective Heating Energy',
      'Zone Electric Equipment Convective Heating Energy',
      'Zone Gas Equipment Convective Heating Energy',
      'Zone Hot Water Equipment Convective Heating Energy',
      'Zone Other Equipment Convective Heating Energy'
    ]
  end

  def self.internal_radiant_gain_outputs
    return [
      'Zone People Radiant Heating Energy',
      'Zone Lights Radiant Heating Energy',
      'Zone Electric Equipment Radiant Heating Energy',
      'Zone Gas Equipment Radiant Heating Energy',
      'Zone Hot Water Equipment Radiant Heating Energy',
      'Zone Other Equipment Radiant Heating Energy'
    ]
  end

  def self.refrigeration_gains_outputs
    return [
      'Refrigeration Zone Case and Walk In Total Sensible Cooling Energy'
    ]
  end

  def self.infiltration_gain_outputs
    return [
      'Zone Infiltration Sensible Heat Gain Energy'
    ]
  end

  def self.infiltration_loss_outputs
    return [
      'Zone Infiltration Sensible Heat Loss Energy'
    ]
  end

  def self.ventilation_gain_outputs
    return [
      'Zone Mechanical Ventilation Cooling Load Increase Energy',
      'Zone Mechanical Ventilation Heating Load Decrease Energy'
    ]
  end

  def self.ventilation_loss_outputs
    return [
      'Zone Mechanical Ventilation Heating Load Increase Energy',
      'Zone Mechanical Ventilation Cooling Load Decrease Energy'
    ]
  end

  def self.air_transfer_outputs
    return [
      'Zone Air Heat Balance Interzone Air Transfer Rate',
      'Zone Exhaust Air Sensible Heat Transfer Rate',
      'Zone Exfiltration Sensible Heat Transfer Rate'
    ]
  end

  def self.surface_convection_outputs
    return [
      'Surface Inside Face Convection Heat Gain Energy'
    ]
  end

  def self.window_gain_component_outputs
    return [
      # 'Zone Windows Total Heat Gain Rate',
      # 'Surface Inside Face Convection Heat Gain Rate',
      # 'Surface Window Net Heat Transfer Energy',
      # 'Surface Window Net Heat Transfer Rate',
      # 'Surface Window Transmitted Solar Radiation Energy',
      # 'Surface Window Transmitted Solar Radiation Rate',
      'Surface Window Inside Face Glazing Net Infrared Heat Transfer Rate',
      'Surface Window Inside Face Shade Net Infrared Heat Transfer Rate',
      # 'Surface Window Inside Face Frame and Divider Zone Heat Gain Rate',
      # 'Surface Window Shortwave from Zone Back Out Window Heat Transfer Rate',
      # 'Surface Inside Face Initial Transmitted Diffuse Transmitted Out Window Solar Radiation Rate',
      # 'Surface Window Gap Convective Heat Transfer Rate',
      # 'Surface Window Inside Face Shade Zone Convection Heat Gain Rate',
      # 'Surface Window Inside Face Gap between Shade and Glazing Zone Convection Heat Gain Rate'
    ]
  end

  def self.window_gain_loss_outputs
    return [
      'Zone Windows Total Heat Gain Energy',
      'Enclosure Windows Total Transmitted Solar Radiation Energy',
      'Zone Windows Total Heat Loss Energy',
    ]
  end

  def self.zone_air_heat_balance_outputs
    return [
      'Zone Air Heat Balance Internal Convective Heat Gain Rate',
      'Zone Air Heat Balance Surface Convection Rate',
      'Zone Air Heat Balance Interzone Air Transfer Rate',
      'Zone Air Heat Balance Outdoor Air Transfer Rate',
      'Zone Air Heat Balance Air Energy Storage Rate',
      'Zone Air Heat Balance System Air Transfer Rate',
      'Zone Air Heat Balance System Convective Heat Gain Rate'
    ]
  end

  def self.zone_total_gains_outputs
    return [
      'Zone Total Internal Radiant Heating Rate',
      'Zone Total Internal Convective Heating Rate',
      'Zone Total Internal Latent Gain Rate',
      'Zone Total Internal Total Heating Rate'
    ]
  end

  def self.zone_air_temperature_outputs
    return [
      'Zone Air Temperature',
      'Zone Mean Air Temperature'
    ]
  end

  def self.heat_transfer_outputs
    outputs = []

    # internal convective gain outputs
    outputs += internal_convective_gain_outputs

    # internal radiant gain outputs
    outputs += internal_radiant_gain_outputs

    # refrigeration gain outputs
    outputs += refrigeration_gains_outputs

    # infiltration gain outputs
    outputs += infiltration_gain_outputs

    # infiltration loss outputs
    outputs += infiltration_loss_outputs

    # ventilation gain outputs
    outputs += ventilation_gain_outputs

    # ventilation loss outputs
    outputs += ventilation_loss_outputs

    # air transfer gain outputs
    outputs += air_transfer_outputs

    # surface convection outputs
    outputs += surface_convection_outputs

    # window gain components
    outputs += window_gain_component_outputs

    # window gain and loss outputs
    outputs += window_gain_loss_outputs

    # zone air heat balance outputs
    outputs += zone_air_heat_balance_outputs

    # zone total gains outputs
    outputs += zone_total_gains_outputs

    # zone air temperature outputs
    outputs += zone_air_temperature_outputs

    return outputs
  end

  # Calculates the error between two vectors for each elements
  # @return Vector where the values are errors as decimals (0.6 = 60% error)
  def self.ts_error_between_vectors(approx_vector, exact_vector, decimals = 2)
    error_vals = []
    approx_vector.to_a.zip(exact_vector.to_a) do |approx, exact|
      err = (approx - exact)/exact
      error_vals << err.round(decimals)
    end

    return Vector.elements(error_vals)
  end

  # Calculates the annual total error between the positive values in two vectors as a single number
  # @return Double where the value is errors as decimal (0.6 = 60% error)
  def self.annual_heat_gain_error_between_vectors(approx_vector, exact_vector, decimals = 2)
    approx_pos_sum = 0.01
    approx_vector.to_a.each do |val|
      approx_pos_sum += val if val > 0
    end

    exact_pos_sum = 0.01
    exact_vector.to_a.each do |val|
      exact_pos_sum += val if val > 0
    end

    err = (approx_pos_sum - exact_pos_sum)/exact_pos_sum

    return err.round(decimals)
  end

  # Calculates the annual total error between the negative values in two vectors as a single number
  # @return Double where the value is errors as decimal (0.6 = 60% error)
  def self.annual_heat_loss_error_between_vectors(approx_vector, exact_vector, decimals = 2)
    approx_pos_sum = -0.01
    approx_vector.to_a.each do |val|
      approx_pos_sum += val if val < 0
    end

    exact_pos_sum = -0.01
    exact_vector.to_a.each do |val|
      exact_pos_sum += val if val < 0
    end

    err = (approx_pos_sum - exact_pos_sum)/exact_pos_sum

    return err.round(decimals)
  end

  # applies the Radiant Time Series factors specified by rts_type to the input laod array
  # at a given seconds per timestep
  # to calculate the delayed rediant load 
  def self.calculate_radiant_delay(load_array, steps_per_hour, rts_type)

    # Radiant Time Series depending on the radiation type
    
    case rts_type
    when 'solar'
      # from ASHRAE HOF 2021 Chapter 18 Table 20: Representative Solar RTS Values for Light to Heavy Construction
      # Medium Construction, 50% glass, with carpet
      rts = [0.54, 0.16, 0.08, 0.04, 0.03, 0.02, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0]
    when 'nonsolar'
      # from ASHRAE HOF 2021 Chapter 18 Table 19: Representative Nonsolar RTS Values for Light to Heavy Construction
      # Medium Construction, 50% glass, with carpet
      rts = [0.49, 0.17, 0.09, 0.05, 0.03, 0.02, 0.02, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.0, 0.00, 0.00, 0.00]
    end

    # apply RTS values to load array
    delayed_load = []
    num_ts_24hr = 24 * steps_per_hour
    load_array.each_with_index do |val, i|
      # get the values from the current hr to 23hrs in the past
      prev_24hr_vals = []
      (0...num_ts_24hr).each do |ts|
        prev_24hr_vals << load_array.fetch(i - ts)
      end

      # calculate the RTS values for the current timestep
      load_rad_rts = 0.0
      prev_24hr_vals.each_slice(steps_per_hour).with_index do |vals_in_hr, hr|
        avg_per_ts_in_hr = vals_in_hr.sum / vals_in_hr.size
        rad_rts = avg_per_ts_in_hr * rts[hr]
        load_rad_rts += rad_rts
      end
      delayed_load << load_rad_rts
    end

    return delayed_load
  end

    
  # Calculates
  def self.thermal_zone_heat_transfer_vectors(runner, zone, sql, freq, ann_env_pd, debug_mode)
    # Define variables
    joules = 'J'
    watts = 'W'
    celsius = 'C'

    # Get the zone name
    zone_name = zone.name.get
    if debug_mode
      puts "Calculating heat transfer vectors for #{zone_name}"
    end

    # space name for enclosure variables, see: https://github.com/NREL/EnergyPlus/issues/10552
    space_name = zone.spaces.first.name.get

    # Get the timestep length
    steps_per_hour = if zone.model.getSimulationControl.timestep.is_initialized
                       zone.model.getSimulationControl.timestep.get.numberOfTimestepsPerHour
                     else
                       6 # default OpenStudio timestep if none specified
                     end
    sec_per_step = (3600/steps_per_hour).to_f

    # Get the annual hours simulated
    hrs_sim = 0
    if sql.hoursSimulated.is_initialized
      hrs_sim = sql.hoursSimulated.get
    else
      runner.registerError('An annual simulation was not run. Cannot summarize annual heat transfer for Scout.')
    end

    # Determine the number of timesteps
    num_ts = hrs_sim * steps_per_hour

    # Hashes of vectors
    heat_transfer_vectors = {}

    # Empty vectors for subtotals
    total_instant_internal_gains = Vector.zero(num_ts)
    total_instant_refrigeration_gains = Vector.zero(num_ts)
    total_delayed_internal_gains = Vector.zero(num_ts)
    total_window_radiation = Vector.zero(num_ts)
    total_surface_convection = Vector.zero(num_ts)
    total_infiltration_gains = Vector.zero(num_ts)
    total_ventilation_gains = Vector.zero(num_ts)
    total_interzone_air_gains = Vector.zero(num_ts)
    total_exfiltration_gains = Vector.zero(num_ts)
    total_exhaust_air_gains = Vector.zero(num_ts)

    # RADIANT DELAY FACTORS
    # Window transmitted solar radiation and internal load radiation are absorbed by zone surfaces and appear as convective loads later on.
    # In EnergyPlus, once heat is transfered to a surface, there is no further way to differentiate the energy.
    # Use the radiant time series factors to attribute past radiation to surface convection at the current timestep
    # These factors are used with the Radiant Time Series load calculation method
    # RTS values = amount of earlier solar radiation heat gain that becomes convective heat gain during the current hour (0 = current hr)
    #   ASHRAE HOF 2013 Chapter 18 Table 20: Representative Solar RTS Values for Light to Heavy Construction
    #   Medium Construction, 50% glass, with carpet
    hrs = [0,    1,    2,    3,    4,    5,    6,    7,    8,    9,    10,   11,   12,   13,   14,   15,   16,   17,   18,   19,  20,  21,  22,  23]
    # rts = [0.54, 0.16, 0.08, 0.04, 0.03, 0.02, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0]
    #   ASHRAE HOF 2013 Chapter 18 Table 19: Representative Nonsolar RTS Values for Light to Heavy Construction
    #   Medium Construction, 50% glass, with carpet

    rts = [0.49, 0.17, 0.09, 0.05, 0.03, 0.02, 0.02, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.0, 0.00, 0.00, 0.00]
    # These numbers are roughly accurate, but change depending on several characteristics.
    # Using a pulse of radiant gain in EnergyPlus gives slightly different values:
    # adjusted_rts = [0.605, 0.106, 0.063, 0.053, 0.048, 0.042, 0.038, 0.030, 0.015, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.0, 0.0, 0.0, 0.0, 0.0]


    # WINDOW SOLAR RADIATION

    # Per the EnergyPlus Engineering Reference for Solar Distribution type = 'FullExterior` (E+ IDD default value):
    #
    #   All beam solar radiation entering the zone is assumed to fall on the floor, where it is absorbed according to the floor’s solar absorptance.
    #   Any reflected by the floor is added to the transmitted diffuse radiation, which is assumed to be uniformly distributed on all interior surfaces.
    #   If no floor is present in the zone, the incident beam solar radiation is absorbed on all interior surfaces according to their absorptances.
    #   The zone heat balance is then applied at each surface and on the zone’s air with the absorbed radiation being treated as a flux on the surface.
    #
    # This means that temperature of the ground/floor (which results in convection) is caused by a combination of previously absorbed
    # solar radiation and current timestep conduction from the temperature difference between the ground/floor and the soil/zone below.

    # # Solar radiation gain (always positive)
    window_radiant_var = 'Enclosure Windows Total Transmitted Solar Radiation Energy'
    wind_solar_rad_vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, window_radiant_var, space_name, num_ts, joules)
    heat_transfer_vectors['Zone Windows Total Transmitted Solar Radiation Energy'] = wind_solar_rad_vals

    # RTS solar radiation energy per timestep for past 24 hrs
    rts_solar_rad_ary = calculate_radiant_delay(wind_solar_rad_vals, steps_per_hour, 'solar')

    heat_transfer_vectors['Zone Windows Total Transmitted Solar Radiation Energy'] = Vector.elements(wind_solar_rad_vals)
    wind_rts_solar_rad_vals = Vector.elements(rts_solar_rad_ary)
    heat_transfer_vectors['Zone Windows Radiation Heat Transfer Energy'] = wind_rts_solar_rad_vals
    total_window_radiation = wind_rts_solar_rad_vals

    # Check that the annual sum of RTS solar matches the annual sum of the instantaneous solar radiation
    # to ensure that calculation was done correctly
    ann_solar_rad = wind_solar_rad_vals.sum
    ann_rts_solar_rad = rts_solar_rad_ary.sum
    if ((ann_rts_solar_rad - ann_solar_rad)/ann_solar_rad).abs > 0.01
      runner.registerError("Solar radiation RTS calculations had an error: annual instantaneous solar = #{ann_solar_rad}, but annual RTS solar = #{ann_rts_solar_rad}; they should be identical")
    end

    # include timeseries checks if in debug mode
    if debug_mode
      # window validation variables
      heat_transfer_vectors['Zone Windows Total Heat Gain'] = Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Windows Total Heat Gain Energy', zone_name, num_ts, joules))
      heat_transfer_vectors['Zone Windows Total Heat Loss'] = Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Windows Total Heat Loss Energy', zone_name, num_ts, joules))
    end

    # NET SURFACE CONVECTION

    # Surface and SubSurface heat gains or losses, depending on sign
    heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Exterior Window Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Interior Wall Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Interior Floor Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Interior Ceiling Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Internal Mass Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    heat_transfer_vectors['Zone Internal Surface Convection Heat Transfer Energy'] = Vector.zero(num_ts)
    
    # collect shading gap convection separately - included in 'Internal Convective' ZAHB total
    heat_transfer_vectors['Zone Shading Gap Convection Heat Transfer Energy'] = Vector.zero(num_ts)

    # window and shade infrared
    heat_transfer_vectors['Zone Windows Net IR Heat Transfer Energy'] = Vector.zero(num_ts)

    # Sign convention for this variable:
    # + = heat flowing into surface (loss to zone)
    # - = heat flowing out of surface (gain to zone)
    # Vector must be reversed to match sign convention used for all other gains above
    surfaces_adjacent_in_same_zone = []
    zone_surface_areas = Hash.new(0.0)
    surfaces_adjacent_to_other_zones = Hash.new(0.0)
    surface_inside_convection_output = 'Surface Inside Face Convection Heat Gain Energy'
    shade_convection_output = 'Surface Window Inside Face Gap between Shade and Glazing Zone Convection Heat Gain Rate'
    window_infrared_var = 'Surface Window Inside Face Glazing Net Infrared Heat Transfer Rate'
    shade_infrared_var = 'Surface Window Inside Face Shade Net Infrared Heat Transfer Rate'

    zone.spaces.sort.each do |space|
      space.surfaces.each do |surface|
        surface_name = surface.name.get
        # puts "Getting convection for #{surface_name} which is a #{surface.outsideBoundaryCondition}-facing #{surface.surfaceType}."
        ht_transfer_vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, surface_inside_convection_output, surface_name, num_ts, joules)

        # Determine the surface type
        surface_type =  if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'
                          'Exterior Wall'
                        elsif ( surface.outsideBoundaryCondition == 'Ground' || surface.outsideBoundaryCondition == 'GroundFCfactorMethod' || surface.outsideBoundaryCondition == 'Foundation' ) && surface.surfaceType == 'Wall'
                          'Exterior Foundation Wall'
                        elsif surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'
                          'Exterior Roof'
                        elsif surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Floor'
                          'Exterior Floor'
                        elsif ( surface.outsideBoundaryCondition == 'Ground' || surface.outsideBoundaryCondition == 'GroundFCfactorMethod' || surface.outsideBoundaryCondition == 'Foundation' ) && surface.surfaceType == 'Floor'
                          'Exterior Ground'
                        # assume others are surfaces that are interior to the building and face other zones
                        elsif (surface.outsideBoundaryCondition == 'Surface' || surface.outsideBoundaryCondition == 'Adiabatic') && surface.surfaceType == 'Wall'
                          'Interior Wall'
                        elsif (surface.outsideBoundaryCondition == 'Surface' || surface.outsideBoundaryCondition == 'Adiabatic') && surface.surfaceType == 'Floor'
                          'Interior Floor'
                        elsif (surface.outsideBoundaryCondition == 'Surface' || surface.outsideBoundaryCondition == 'Adiabatic') && surface.surfaceType == 'RoofCeiling'
                          'Interior Ceiling'
                        else
                          'Internal Surface'
                        end
        zone_surface_areas[surface_type] += surface.netArea

        if surface.adjacentSurface.is_initialized && ( surface.surfaceType == 'RoofCeiling' || surface.surfaceType == 'Floor' || surface.surfaceType == 'Wall' )
          adjacent_surface = surface.adjacentSurface.get
          if adjacent_surface.space.get.thermalZone.get != space.thermalZone.get # only consider interzonal adjacent surfaces
            adjacent_zone = adjacent_surface.space.get.thermalZone.get
            adjacent_zone_name = adjacent_zone.name.get
            unless surfaces_adjacent_to_other_zones.keys.include? adjacent_zone_name
              surfaces_adjacent_to_other_zones[adjacent_zone_name] = []
            end
            surfaces_adjacent_to_other_zones[adjacent_zone_name] << surface
          else # adjacent surfaces within the same zone
            surfaces_adjacent_in_same_zone << surface
          end
        end

        # Add to total for this surface type
        vect = -1.0 * Vector.elements(ht_transfer_vals) # reverse sign of vector
        heat_transfer_vectors["Zone #{surface_type} Convection Heat Transfer Energy"] += vect
        total_surface_convection += vect

        # SubSurfaces
        
        # If no shades:
        # Window net heat gain = convective, net transmitted solar, net IR
        # - Window transmitted solar handled above
        # - Surface Inside Face Convection Heat Gain = Surface Window Inside Face Glazing Zone Convection Heat Gain
        # - Net IR needs to be approtioned as delayed to other surfaces
        # With shades:
        # Additional components from Gap between Window and Shade Convection and Shade Net IR
        # - Surface Inside Face Convection Heat Gain = Surface Window Inside Face Shade Zone Convective Heat Gain
        # - Gap between Shade and Glazing Zone Convection goes into Internal Convective Heat Gain in ZAHB
        # - Shade Net IR needs to be approtioned as delayed gains to other surfaces
        surface.subSurfaces.each do |sub_surface|
          sub_surface_name = sub_surface.name.get

          # Determine the subsurface type
          sub_surface_type =  if sub_surface.subSurfaceType.downcase.include? 'window'
                                'Exterior Window'
                              elsif sub_surface.subSurfaceType.downcase.include? 'door'
                                'Exterior Door'
                              else # assume others are subsurfaces that are interior to the building and face other zones
                                'Internal Surface'
                              end
          zone_surface_areas[sub_surface_type] += sub_surface.netArea

          ht_transfer_vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, surface_inside_convection_output, sub_surface_name, num_ts, joules)
          vect = -1.0 * Vector.elements(ht_transfer_vals) # reverse sign of vector

          # Add to total for this surface type
          heat_transfer_vectors["Zone #{sub_surface_type} Convection Heat Transfer Energy"] += vect
          total_surface_convection += vect
          
          # determine if shade is modeled
          if sub_surface_type == 'Exterior Window' 
            if !sub_surface.shadingControls.empty?
              # add gap convection to internal gains
              # only output is a rate 'to the zone', so don't flip the sign
              shade_gap_conv_vals = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, shade_convection_output, sub_surface_name, num_ts, watts))
              # add to window convective, but don't add to total_surface_convection because it's not included as such in the ZAHB
              heat_transfer_vectors["Zone #{sub_surface_type} Convection Heat Transfer Energy"] += shade_gap_conv_vals
              # this will get added to internal convection gains in the check against the ZAHB
              heat_transfer_vectors['Zone Shading Gap Convection Heat Transfer Energy'] += shade_gap_conv_vals
            end
            # collect window/shade IR - these outputs are 'to the zone', so don't flip the sign
            window_ir_vals = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, window_infrared_var, sub_surface_name, num_ts, watts))
            shade_ir_vals = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, shade_infrared_var, sub_surface_name, num_ts, watts))
            heat_transfer_vectors['Zone Windows Net IR Heat Transfer Energy'] += window_ir_vals
            heat_transfer_vectors['Zone Windows Net IR Heat Transfer Energy'] += shade_ir_vals
          end

        end
      end

      # Internal masses with SurfaceArea specified have surface convection
      space.internalMass.each do |int_mass|
        int_mass_name = int_mass.name.get
        # puts "Getting convection for #{int_mass_name}."
        ht_transfer_vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, surface_inside_convection_output, int_mass_name, num_ts, joules)

        # Add to total for this internal mass
        vect = -1.0 * Vector.elements(ht_transfer_vals) # reverse sign of vector
        heat_transfer_vectors['Zone Internal Mass Convection Heat Transfer Energy'] += vect
        # puts heat_transfer_vectors['Zone Internal Mass Convection Heat Transfer Energy'].to_a.sum
        total_surface_convection += vect

        # add surface area of internal mass
        if int_mass.surfaceArea.is_initialized
          int_mass_area = int_mass.surfaceArea.get
        elsif int_mass.surfaceAreaPerFloorArea.is_initialized
          int_mass_area = int_mass.surfaceAreaPerFloorArea.get * space.floorArea
        elsif int_mass.surfaceAreaPerPerson.is_initialized
          int_mass_area = int_mass.surfaceAreaPerPerson.get * space.numberOfPeople
        end
        zone_surface_areas["Internal Mass"] += int_mass_area
      end
    end

    # calculated delayed window radiant (IR)
    window_delayed_ir_gain = calculate_radiant_delay(heat_transfer_vectors['Zone Windows Net IR Heat Transfer Energy'].to_a, steps_per_hour, 'nonsolar')
    window_delayed_ir_gain_vect = Vector.elements(window_delayed_ir_gain)
    heat_transfer_vectors['Zone Windows Delayed Net IR Heat Transfer Energy'] = window_delayed_ir_gain_vect

    # Check that the sum of surface convection matches the zone total surface convection rate
    true_total_surface_convection = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance Surface Convection Rate', zone_name, num_ts, watts))
    total_surface_convection_difference = true_total_surface_convection - total_surface_convection
    total_surface_convection_error = ts_error_between_vectors(total_surface_convection, true_total_surface_convection, 4)
    total_surface_convection_annual_gain_error = annual_heat_gain_error_between_vectors(total_surface_convection, true_total_surface_convection, 4)
    total_surface_convection_annual_loss_error = annual_heat_loss_error_between_vectors(total_surface_convection, true_total_surface_convection, 4)
    runner.registerInfo("#{zone_name}: Annual Gain Error in Surface Convection is #{total_surface_convection_annual_gain_error * 100}%, Annual Loss Error in Surface Convection is #{total_surface_convection_annual_loss_error * 100}%")

    # include timeseries checks if in debug mode
    if debug_mode
      heat_transfer_vectors['True Surface Convection'] = true_total_surface_convection
      heat_transfer_vectors['Calc Surface Convection'] = total_surface_convection
      heat_transfer_vectors['Diff Surface Convection'] = total_surface_convection_difference
      heat_transfer_vectors['Error in Surface Convection'] = total_surface_convection_error
      heat_transfer_vectors["#{zone_name}: Annual Gain Error in Surface Convection"] = total_surface_convection_annual_gain_error
      heat_transfer_vectors["#{zone_name}: Annual Loss Error in Surface Convection"] = total_surface_convection_annual_loss_error
    end

    # INTERNAL CONVECTIVE AND RADIANT GAINS

    # Internal instant convective gains
    # Internal gains include equipment (electric, gas, other), people, and lights
    internal_convective_gain_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)
      vect = Vector.elements(vals)
      heat_transfer_vectors[output] = vect
      total_instant_internal_gains += vect
    end

    # add window shading convection to instant internal gains
    total_instant_internal_gains += heat_transfer_vectors['Zone Shading Gap Convection Heat Transfer Energy']

    # Report out combined electric and gas equipment
    heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'] = heat_transfer_vectors['Zone Electric Equipment Convective Heating Energy']
    heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'] += heat_transfer_vectors['Zone Gas Equipment Convective Heating Energy']
    heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'] += heat_transfer_vectors['Zone Hot Water Equipment Convective Heating Energy']
    heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'] += heat_transfer_vectors['Zone Other Equipment Convective Heating Energy']

    # Compare Internal gains to EnergyPlus zone air heat balance
    # true_total_internal_gains = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Total Internal Convective Heating Rate', zone_name, num_ts, watts))
    true_total_internal_gains = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance Internal Convective Heat Gain Rate', zone_name, num_ts, watts))
    interal_gains_difference = true_total_internal_gains - total_instant_internal_gains
    internal_gains_error = ts_error_between_vectors(total_instant_internal_gains, true_total_internal_gains, 4)
    internal_gains_annual_gain_error = annual_heat_gain_error_between_vectors(total_instant_internal_gains, true_total_internal_gains, 4)
    internal_gains_annual_loss_error = annual_heat_loss_error_between_vectors(total_instant_internal_gains, true_total_internal_gains, 4)
    runner.registerInfo("#{zone_name}: Annual Gain Error in Internal Gains is #{internal_gains_annual_gain_error * 100}%, Annual Loss Error in Internal Gains is #{internal_gains_annual_loss_error * 100}%")

    # include timeseries checks if in debug mode
    if debug_mode
      heat_transfer_vectors['True Internal Gains'] = true_total_internal_gains
      heat_transfer_vectors['Calc Internal Gains'] = total_instant_internal_gains
      heat_transfer_vectors['Diff Internal Gains'] = interal_gains_difference
      heat_transfer_vectors['Error in Internal Gains'] = internal_gains_error
      heat_transfer_vectors["#{zone_name}: Annual Gain Error in Internal Gains"] = internal_gains_annual_gain_error
      heat_transfer_vectors["#{zone_name}: Annual Loss Error in Internal Gains"] = internal_gains_annual_loss_error
    end

    # Calculate delayed component of internal gains
    internal_radiant_gain_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)

      rad_ary = calculate_radiant_delay(vals, steps_per_hour, 'nonsolar')

      load_rad_vals = Vector.elements(rad_ary)
      delayed_name = output.gsub('Radiant', 'Delayed Convective')
      heat_transfer_vectors[delayed_name] = load_rad_vals
      total_delayed_internal_gains += load_rad_vals

      # Check that the annual sum of RTS radiant matches the annual sum of the radiant
      ann_rad = vals.sum
      ann_rts_rad = rad_ary.sum
      if ((ann_rts_rad - ann_rad)/ann_rad).abs > 0.01
        runner.registerError("#{delayed_name} RTS calculations had an error: annual radiant = #{ann_rad}, but annual RTS = #{ann_rts_rad}; they should be identical")
      end
    end
    heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'] = heat_transfer_vectors['Zone Electric Equipment Delayed Convective Heating Energy']
    heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'] += heat_transfer_vectors['Zone Gas Equipment Delayed Convective Heating Energy']
    heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'] += heat_transfer_vectors['Zone Hot Water Equipment Delayed Convective Heating Energy']
    heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'] += heat_transfer_vectors['Zone Other Equipment Delayed Convective Heating Energy']

    # include timeseries checks if in debug mode
    if debug_mode
      # Total internal gain variables for validation
      heat_transfer_vectors['Calc Delayed Internal Gains'] = total_delayed_internal_gains
      # heat_transfer_vectors['Zone Air Heat Balance Internal Convective Heat Gain'] = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance Internal Convective Heat Gain Rate', zone_name, num_ts, watts))
      heat_transfer_vectors['Zone Air Heat Balance Internal Convective Heat Gain'] = true_total_internal_gains
      heat_transfer_vectors['Zone Total Internal Radiant Heating'] = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Total Internal Radiant Heating Rate', zone_name, num_ts, watts))
      heat_transfer_vectors['Zone Total Internal Convective Heating'] = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Total Internal Convective Heating Rate', zone_name, num_ts, watts))
      heat_transfer_vectors['Zone Total Internal Latent Gain'] = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Total Internal Latent Gain Rate', zone_name, num_ts, watts))
      heat_transfer_vectors['Zone Total Internal Total Heating'] = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Total Internal Total Heating Rate', zone_name, num_ts, watts))
    end

    # SURFACE CONVECTION CORRECTION
    # calculate total zone surface area
    total_zone_surface_area = 0
    total_zone_exterior_surface_area = 0
    total_zone_exterior_ground_area = 0
    total_zone_exterior_floor_area = 0
    total_zone_interior_floor_area = 0
    zone_surface_areas.each do |k, v|
      total_zone_surface_area += v
      total_zone_exterior_surface_area += v if k.include? 'Exterior'
      case k
      when 'Exterior Ground'
        total_zone_exterior_ground_area += v
      when 'Exterior Floor'
        total_zone_exterior_floor_area += v
      when 'Interior Floor'
        total_zone_interior_floor_area += v
      end
    end

    # Subtract window RTS heat transfer from ground and floor surface convection proportional to floor area
    total_zone_ground_and_floor_area = total_zone_exterior_ground_area + total_zone_exterior_floor_area + total_zone_interior_floor_area
    zone_exterior_ground_area_fraction = total_zone_exterior_ground_area / total_zone_ground_and_floor_area
    zone_exterior_floor_area_fraction = total_zone_exterior_floor_area / total_zone_ground_and_floor_area
    zone_interior_floor_area_fraction = total_zone_interior_floor_area / total_zone_ground_and_floor_area
    if debug_mode
      runner.registerInfo("For zone #{zone_name}, removing #{zone_exterior_ground_area_fraction * 100.0}% of window solar radiation from exterior ground convection, #{zone_exterior_floor_area_fraction * 100.0}% of from exterior floor convection, and #{zone_interior_floor_area_fraction * 100.0}% of from interior floor convection.")
    end
    heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'] -= zone_exterior_ground_area_fraction * wind_rts_solar_rad_vals
    heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'] -= zone_exterior_floor_area_fraction * wind_rts_solar_rad_vals
    heat_transfer_vectors['Zone Interior Floor Convection Heat Transfer Energy'] -= zone_interior_floor_area_fraction * wind_rts_solar_rad_vals
    attributable_total_surface_convection = total_surface_convection
    attributable_total_surface_convection -= wind_rts_solar_rad_vals

    # Subtract delayed internal loads from surface convection proportional to surface area
    # subtract delayed glazing gain from non-window surface convection proportional to surface area
    zone_surface_areas.each do |k, v|
      surface_fraction = v / total_zone_surface_area
      case k
      when 'Exterior Wall'
        heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Exterior Foundation Wall'
        heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Exterior Roof'
        heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Exterior Floor'
        heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Exterior Ground'
        heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Exterior Window'
        heat_transfer_vectors['Zone Exterior Window Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
      when 'Exterior Door'
        heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Interior Wall'
        heat_transfer_vectors['Zone Interior Wall Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Interior Wall Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Interior Floor'
        heat_transfer_vectors['Zone Interior Floor Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Interior Floor Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Interior Ceiling'
        heat_transfer_vectors['Zone Interior Ceiling Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Interior Ceiling Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Internal Mass'
        heat_transfer_vectors['Zone Internal Mass Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Internal Mass Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      when 'Internal Surface'
        heat_transfer_vectors['Zone Internal Surface Convection Heat Transfer Energy'] -= surface_fraction * total_delayed_internal_gains
        heat_transfer_vectors['Zone Internal Surface Convection Heat Transfer Energy'] -= surface_fraction * window_delayed_ir_gain_vect
      else
        puts "what is #{k}??"
      end
      if debug_mode
        runner.registerInfo("For zone #{zone_name}, #{surface_fraction.round(3)} #{k} surface fraction.")
      end
    end
    attributable_total_surface_convection -= total_delayed_internal_gains
    attributable_total_surface_convection -= window_delayed_ir_gain_vect

    
    
    # redistribute Interior and Internal convection back to exterior surfaces
    interior_convection_terms = [
      'Zone Interior Wall Convection Heat Transfer Energy',
      'Zone Interior Floor Convection Heat Transfer Energy',
      'Zone Interior Ceiling Convection Heat Transfer Energy',
      'Zone Internal Mass Convection Heat Transfer Energy',
      'Zone Internal Surface Convection Heat Transfer Energy'
    ]
    interior_convection_terms.each do |term|
      # correction = -1 * heat_transfer_vectors[term]
      correction = heat_transfer_vectors[term]
      # heat_transfer_vectors[term] += correction
      heat_transfer_vectors[term] -= correction
      zone_surface_areas.each do |k, v|
        next unless k.include? 'Exterior'
        ext_surface_fraction = v / total_zone_exterior_surface_area
        case k
        when 'Exterior Roof'
          heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        when 'Exterior Wall'
          heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        when 'Exterior Foundation Wall'
          heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        when 'Exterior Floor'
          heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        when 'Exterior Ground'
          heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        when 'Exterior Window'
          heat_transfer_vectors['Zone Exterior Window Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        when 'Exterior Door'
          heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'] += ext_surface_fraction * correction
        end
      end

      final_sum = heat_transfer_vectors[term].to_a.sum
      raise "#{term} not reallocated correctly: ended up with total: #{final_sum}" unless final_sum == 0.0
    end

    # Re-attributed delayed solar, delayed internal gains, and internal surface convection to exterior surfaces
    # The remain convection value is attributable to exterior surface convection only
    heat_transfer_vectors['Calc Attributable Exterior Surface Convection'] = attributable_total_surface_convection

    # REFRIGERATION

    # Refrigeration includes cases and walk-ins
    refrigeration_gains_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)
      vect = Vector.elements(vals)
      heat_transfer_vectors[output] = vect
      total_instant_refrigeration_gains += vect
    end

    # INFILTRATION, AIR TRANSFER, AND VENTILATION LOADS

    # Infiltration gains
    infiltration_gain_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)
      vect = Vector.elements(vals)
      heat_transfer_vectors[output] = vect
      total_infiltration_gains += vect
    end

    # Infiltration losses
    infiltration_loss_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)
      vect = -1.0 * Vector.elements(vals) # reverse vector sign for loss variables before summing
      heat_transfer_vectors[output] = vect
      total_infiltration_gains += vect
    end

    # Report infiltration
    heat_transfer_vectors['Zone Infiltration Gains'] = total_infiltration_gains

    # Compare infiltration gains to EnergyPlus zone air outdoor air heat balance
    true_total_outdoor_air_gains = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance Outdoor Air Transfer Rate', zone_name, num_ts, watts))
    total_outdoor_air_gains_difference = true_total_outdoor_air_gains - total_infiltration_gains
    total_outdoor_air_gains_error = ts_error_between_vectors(total_infiltration_gains, true_total_outdoor_air_gains, 4)
    total_outdoor_air_annual_gains_error = annual_heat_gain_error_between_vectors(total_infiltration_gains, true_total_outdoor_air_gains, 4)
    total_outood_air_annual_loss_error = annual_heat_loss_error_between_vectors(total_infiltration_gains, true_total_outdoor_air_gains, 4)
    runner.registerInfo("#{zone_name}: Annual Gain Error in Infiltration is #{total_outdoor_air_annual_gains_error * 100}%, Annual Loss Error in Infiltration is #{total_outood_air_annual_loss_error * 100}%")

    # include timeseries checks if in debug mode
    if debug_mode
      heat_transfer_vectors['Calc Outdoor Air Gains'] = total_infiltration_gains
      heat_transfer_vectors['True Outdoor Air Gains'] = true_total_outdoor_air_gains
      heat_transfer_vectors['Diff Net Outdoor Air Gains'] = total_outdoor_air_gains_difference
      heat_transfer_vectors['Error in Net Outdoor Air Gains'] = total_outdoor_air_gains_error
      heat_transfer_vectors["#{zone_name}: Annual Gain Error in Outdoor Air Gains"] = total_outdoor_air_annual_gains_error
      heat_transfer_vectors["#{zone_name}: Annual Loss Error in Outdoor Air Gains"] = total_outood_air_annual_loss_error
    end

    # Air transfer gains
    air_transfer_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, watts)
      vect = sec_per_step * Vector.elements(vals)
      heat_transfer_vectors[output] = vect
    end
    total_interzone_air_gains += heat_transfer_vectors['Zone Air Heat Balance Interzone Air Transfer Rate']
    total_exhaust_air_gains += heat_transfer_vectors['Zone Exhaust Air Sensible Heat Transfer Rate']
    total_exfiltration_gains += heat_transfer_vectors['Zone Exfiltration Sensible Heat Transfer Rate']

    # Compare interzone heat transfer
    true_interzone_air = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance Interzone Air Transfer Rate', zone_name, num_ts, watts))
    interzone_air_difference = true_interzone_air - total_interzone_air_gains
    interzone_air_error = ts_error_between_vectors(total_interzone_air_gains, true_interzone_air, 4)
    interzone_air_annual_gain_error = annual_heat_gain_error_between_vectors(total_interzone_air_gains, true_interzone_air, 4)
    interzone_air_annual_loss_error = annual_heat_loss_error_between_vectors(total_interzone_air_gains, true_interzone_air, 4)
    runner.registerInfo("#{zone_name}: Annual Gain Error in Interzone Air is #{interzone_air_annual_gain_error * 100}%, Annual Loss Error in Interzone Air is #{interzone_air_annual_loss_error * 100}%")

    # include timeseries checks if in debug mode
    if debug_mode
      heat_transfer_vectors['Calc Interzone Air Gains'] = total_interzone_air_gains
      heat_transfer_vectors['True Interzone Air Gains'] = true_interzone_air
      heat_transfer_vectors['Diff Interzone Air Gains'] = interzone_air_difference
      heat_transfer_vectors['Error Interzone Air Gains'] = interzone_air_error
      heat_transfer_vectors["#{zone_name}: Annual Gain Error in Interzone Air Gains"] = interzone_air_annual_gain_error
      heat_transfer_vectors["#{zone_name}: Annual Loss Error in Interzone Air Gains"] = interzone_air_annual_loss_error
      heat_transfer_vectors["Zone Air Temperature"] = Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Mean Air Temperature', zone_name, num_ts, celsius))
      heat_transfer_vectors["Zone Air Density"] = Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'System Node Current Density', "#{zone_name} Zone Air Node", num_ts, 'kg/m3'))
      heat_transfer_vectors["Zone Air Specific Heat"] = Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'System Node Specific Heat', "#{zone_name} Zone Air Node", num_ts, 'J/kg-K'))
    end

    # Ventilation gains
    ventilation_gain_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)
      vect = Vector.elements(vals)
      heat_transfer_vectors[output] = vect
      total_ventilation_gains += vect
    end

    # Ventilation losses
    ventilation_loss_outputs.each do |output|
      vals = OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, output, zone_name, num_ts, joules)
      vect = -1.0 * Vector.elements(vals) # reverse vector sign for loss variables before summing
      heat_transfer_vectors[output] = vect
      total_ventilation_gains += vect
    end

    # Report ventilation
    heat_transfer_vectors['Zone Ventilation Gains'] = total_ventilation_gains

    # ENERGY BALANCE VALIDATION TERMS

    # Air energy storage term
    true_air_energy_storage = -1.0 * sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance Air Energy Storage Rate', zone_name, num_ts, watts)) # Reverse sign
    heat_transfer_vectors['Zone Air Heat Balance Air Energy Storage'] = true_air_energy_storage

    # Energy supplied by the HVAC systems for validation
    true_airloop = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance System Air Transfer Rate', zone_name, num_ts, watts))
    true_zone_system_convective = sec_per_step * Vector.elements(OsLib_SqlFile.get_timeseries_array(runner, sql, ann_env_pd, freq, 'Zone Air Heat Balance System Convective Heat Gain Rate', zone_name, num_ts, watts))
    heat_transfer_vectors['HVAC (Airloop) Heat Transfer Energy'] = true_airloop
    heat_transfer_vectors['HVAC (Zone System) Heat Transfer Energy'] = true_zone_system_convective
    hvac_systems_heat_transfer_energy = true_airloop + true_zone_system_convective
    heat_transfer_vectors['HVAC (All) Heat Transfer Energy'] = hvac_systems_heat_transfer_energy
    # Storage is included on both sides of equation: embedded inside convection on demand side, added with opposite sign on supply side
    true_total_energy_balance = hvac_systems_heat_transfer_energy + (2.0 * true_air_energy_storage)

    # Calculated zone heat transfer
    total_zone_heat_transfer = total_instant_internal_gains + total_instant_refrigeration_gains + total_delayed_internal_gains + total_window_radiation + window_delayed_ir_gain_vect + attributable_total_surface_convection + total_infiltration_gains + total_interzone_air_gains
    total_zone_energy_balance_difference = true_total_energy_balance + total_zone_heat_transfer
    total_zone_energy_balance_error = ts_error_between_vectors(total_zone_heat_transfer, -1 * true_total_energy_balance, 4) # Reverse sign of one before comparing
    total_zone_energy_balance_annual_gain_error = annual_heat_gain_error_between_vectors(total_zone_heat_transfer, -1 * true_total_energy_balance, 4) # Reverse sign of one before comparing
    total_zone_energy_balance_annual_loss_error = annual_heat_loss_error_between_vectors(total_zone_heat_transfer, -1 * true_total_energy_balance, 4) # Reverse sign of one before comparing
    runner.registerInfo("#{zone_name}: Annual Energy Balance Gain Error is #{total_zone_energy_balance_annual_gain_error * 100}%, Annual Energy Balance Loss Error is #{total_zone_energy_balance_annual_loss_error * 100}%")

    # include timeseries checks if in debug mode
    heat_transfer_vectors['Calc Energy Balance'] = total_zone_heat_transfer
    heat_transfer_vectors['True Energy Balance'] = true_total_energy_balance
    heat_transfer_vectors['Diff Energy Balance'] = total_zone_energy_balance_difference
    heat_transfer_vectors['Error in Energy Balance'] = total_zone_energy_balance_error
    heat_transfer_vectors["#{zone_name}: Annual Gain Error in Total Energy Balance"] = total_zone_energy_balance_annual_gain_error
    heat_transfer_vectors["#{zone_name}: Annual Loss Error in Total Energy Balance"] = total_zone_energy_balance_annual_loss_error


    return heat_transfer_vectors
  end
end
