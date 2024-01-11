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

module OsLib_ModelGeneration
  # simple list of building types that are valid for get_space_types_from_building_type
  # for general public use use extended = false
  def get_building_types(extended = false)
    # get building_types
    if extended
      doe = get_doe_building_types(true)
      deer = get_deer_building_types(true)
    else
      doe = get_doe_building_types
      deer = get_deer_building_types
    end

    # combine building_types
    array = OpenStudio::StringVector.new
    temp_array = doe.to_a + deer.to_a
    temp_array.each do |i|
      array << i
    end

    return array
  end

  # get_doe_building_types
  # for general public use use extended = false
  def get_doe_building_types(extended = false)
    # DOE Prototypes
    array = OpenStudio::StringVector.new
    array << 'SecondarySchool'
    array << 'PrimarySchool'
    array << 'SmallOffice'
    array << 'MediumOffice'
    array << 'LargeOffice'
    array << 'SmallHotel'
    array << 'LargeHotel'
    array << 'Warehouse'
    array << 'RetailStandalone'
    array << 'RetailStripmall'
    array << 'QuickServiceRestaurant'
    array << 'FullServiceRestaurant'
    array << 'MidriseApartment'
    array << 'HighriseApartment'
    array << 'Hospital'
    array << 'Outpatient'
    array << 'SuperMarket'
    array << 'Laboratory'
    array << 'LargeDataCenterLowITE'
    array << 'LargeDataCenterHighITE'
    array << 'SmallDataCenterLowITE'
    array << 'SmallDataCenterHighITE'

    return array
  end

  # get_deer_building_types
  # for general public use use extended = false
  def get_deer_building_types(extended = false)
    # DOE Prototypes
    array = OpenStudio::StringVector.new
    array << 'Asm'
    array << 'DMo'
    array << 'ECC'
    array << 'EPr'
    array << 'ERC'
    array << 'ESe'
    array << 'EUn'
    array << 'GHs'
    array << 'Gro'
    array << 'Hsp'
    array << 'Htl'
    array << 'MBT'
    array << 'MFm'
    array << 'MLI'
    array << 'Mtl'
    array << 'Nrs'
    array << 'OfL'
    array << 'OfS'
    array << 'RFF'
    array << 'RSD'
    array << 'Rt3'
    array << 'RtL'
    array << 'RtS'
    array << 'SCn'
    array << 'SFm'
    array << 'SUn'
    array << 'WRf'

    return array
  end

  # simple list of templates that are valid for get_space_types_from_building_type
  # for general public use use extended = false
  def get_templates(extended = false)
    # get templates
    if extended
      doe = get_doe_templates(true)
      deer = get_deer_templates(true)
    else
      doe = get_doe_templates
      deer = get_deer_templates
    end

    # combine templates
    array = OpenStudio::StringVector.new
    temp_array = doe.to_a + deer.to_a
    temp_array.each do |i|
      array << i
    end

    return array
  end

  # get_doe_templates
  # for general public use use extended = false
  def get_doe_templates(extended = false)
    array = OpenStudio::StringVector.new
    array << 'DOE Ref Pre-1980'
    array << 'DOE Ref 1980-2004'
    array << '90.1-2004'
    array << '90.1-2007'
    array << '90.1-2010'
    array << '90.1-2013'
    array << '90.1-2016'
    array << '90.1-2019'
    array << 'ComStock DOE Ref Pre-1980'
    array << 'ComStock DOE Ref 1980-2004'
    array << 'ComStock 90.1-2004'
    array << 'ComStock 90.1-2007'
    array << 'ComStock 90.1-2010'
    array << 'ComStock 90.1-2013'
    array << 'ComStock 90.1-2016'
    array << 'ComStock 90.1-2019'
    if extended
      # array << '189.1-2009' # if turn this on need to update space_type_array for RetailStripmall
      array << 'NREL ZNE Ready 2017'
    end

    return array
  end

  # get_deer_templates
  # for general public use use extended = false
  def get_deer_templates(extended = false)
    array = OpenStudio::StringVector.new
    array << 'DEER Pre-1975'
    array << 'DEER 1985'
    array << 'DEER 1996'
    array << 'DEER 2003'
    array << 'DEER 2007'
    array << 'DEER 2011'
    array << 'DEER 2014'
    array << 'DEER 2015'
    array << 'DEER 2017'
    array << 'DEER 2020'
    if extended
      array << 'DEER 2025'
      array << 'DEER 2030'
      array << 'DEER 2035'
      array << 'DEER 2040'
      array << 'DEER 2045'
      array << 'DEER 2050'
      array << 'DEER 2055'
      array << 'DEER 2060'
      array << 'DEER 2065'
      array << 'DEER 2070'
      array << 'DEER 2075'
    end

    array << 'ComStock DEER Pre-1975'
    array << 'ComStock DEER 1985'
    array << 'ComStock DEER 1996'
    array << 'ComStock DEER 2003'
    array << 'ComStock DEER 2007'
    array << 'ComStock DEER 2011'
    array << 'ComStock DEER 2014'
    array << 'ComStock DEER 2015'
    array << 'ComStock DEER 2017'
    array << 'ComStock DEER 2020'

    return array
  end

  # get_climate_zones
  # for general public use use extended = false
  def get_climate_zones(extended = false, extra = nil)

    # get climate_zones
    if extended && extra != nil
      doe = get_doe_climate_zones(true, extra)
      deer = get_deer_climate_zones(true, nil)
    elsif extended
      doe = get_doe_climate_zones(true, nil)
      deer = get_deer_climate_zones(true, nil)
    elsif extra != nil
      doe = get_doe_climate_zones(false, extra)
      deer = get_deer_climate_zones(false, nil)
    else
      doe = get_doe_climate_zones
      deer = get_deer_climate_zones
    end

    # combine climate zones
    array = OpenStudio::StringVector.new
    temp_array = doe.to_a + deer.to_a
    temp_array.each do |i|
      array << i
    end

    return array
  end

  # get_doe_climate_zones
  # for general public use use extended = false
  def get_doe_climate_zones(extended = false, extra = nil)
    # Lookup From Model should be added as an option where appropriate in the measure
    cz_choices = OpenStudio::StringVector.new
    if !extra.nil?
      cz_choices << extra
    end
    cz_choices << 'ASHRAE 169-2013-1A'
    cz_choices << 'ASHRAE 169-2013-1B'
    cz_choices << 'ASHRAE 169-2013-2A'
    cz_choices << 'ASHRAE 169-2013-2B'
    cz_choices << 'ASHRAE 169-2013-3A'
    cz_choices << 'ASHRAE 169-2013-3B'
    cz_choices << 'ASHRAE 169-2013-3C'
    cz_choices << 'ASHRAE 169-2013-4A'
    cz_choices << 'ASHRAE 169-2013-4B'
    cz_choices << 'ASHRAE 169-2013-4C'
    cz_choices << 'ASHRAE 169-2013-5A'
    cz_choices << 'ASHRAE 169-2013-5B'
    cz_choices << 'ASHRAE 169-2013-5C'
    cz_choices << 'ASHRAE 169-2013-6A'
    cz_choices << 'ASHRAE 169-2013-6B'
    cz_choices << 'ASHRAE 169-2013-7A'
    cz_choices << 'ASHRAE 169-2013-8A'
    if extended
      cz_choices << 'ASHRAE 169-2013-0A'
      cz_choices << 'ASHRAE 169-2013-0B'
    end

    return cz_choices
  end

  # get_deer_climate_zones
  # for general public use use extended = false
  def get_deer_climate_zones(extended = false, extra = nil)
    # Lookup From Model should be added as an option where appropriate in the measure
    cz_choices = OpenStudio::StringVector.new
    if !extra.nil?
      cz_choices << extra
    end
    cz_choices << 'CEC T24-CEC1'
    cz_choices << 'CEC T24-CEC2'
    cz_choices << 'CEC T24-CEC3'
    cz_choices << 'CEC T24-CEC4'
    cz_choices << 'CEC T24-CEC5'
    cz_choices << 'CEC T24-CEC6'
    cz_choices << 'CEC T24-CEC7'
    cz_choices << 'CEC T24-CEC8'
    cz_choices << 'CEC T24-CEC9'
    cz_choices << 'CEC T24-CEC10'
    cz_choices << 'CEC T24-CEC11'
    cz_choices << 'CEC T24-CEC12'
    cz_choices << 'CEC T24-CEC13'
    cz_choices << 'CEC T24-CEC14'
    cz_choices << 'CEC T24-CEC15'
    cz_choices << 'CEC T24-CEC16'

    return cz_choices
  end

  # calculate aspect ratio from area and perimeter
  def calc_aspect_ratio(a, p)
    l = 0.25 * (p + Math.sqrt(p**2 - 16 * a))
    w = 0.25 * (p - Math.sqrt(p**2 - 16 * a))
    aspect_ratio = l / w

    return aspect_ratio
  end

  # Building Form Defaults from Table 4.2 in Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010
  # aspect ratio for NA replaced with floor area to perimeter ratio from prototype model
  # currently no reason to split apart doe and deer inputs here
  def building_form_defaults(building_type)
    hash = {}

    # DOE Prototypes

    # calculate aspect ratios not represented on Table 4.2
    primary_footprint = 73958.0
    primary_p = 619.0 # wrote measure using calculate_perimeter method in os_lib_geometry
    primary_ns_ew_ratio = 2.829268293 # estimated from ratio of ns/ew total wall area
    primary_width = Math.sqrt(primary_footprint / primary_ns_ew_ratio)
    primary_p_min = 2 * (primary_width + primary_width / primary_footprint)
    primary_p_mult = primary_p / primary_p_min

    secondary_footprint = 210887.0 / 2.0 # floor area divided by area instead of true footprint 128112.0)
    secondary_p = 708.0 # wrote measure using calculate_perimeter method in os_lib_geometry
    secondary_ns_ew_ratio = 2.069230769 # estimated from ratio of ns/ew total wall area
    secondary_width = Math.sqrt(secondary_footprint / secondary_ns_ew_ratio)
    secondary_p_min = 2 * (secondary_width + secondary_width / secondary_footprint)
    secondary_p_mult = secondary_p / secondary_p_min

    outpatient_footprint = 40946.0 / 3.0 # floor area divided by area instead of true footprint 17872.0)
    outpatient_p = 537.0 # wrote measure using calculate_perimeter method in os_lib_geometry
    outpatient_ns_ew_ratio = 1.56448737 # estimated from ratio of ns/ew total wall area
    outpatient_width = Math.sqrt(outpatient_footprint / outpatient_ns_ew_ratio)
    outpatient_p_min = 2 * (outpatient_width + outpatient_footprint / outpatient_width)
    outpatient_p_mult = outpatient_p / outpatient_p_min

    # primary_aspet_ratio = calc_aspect_ratio(73958.0, 2060.0)
    # secondary_aspet_ratio = calc_aspect_ratio(128112.0, 2447.0)
    # outpatient_aspet_ratio = calc_aspect_ratio(14782.0, 588.0)
    supermarket_a = 45001.0
    supermarket_p = 866.0
    supermarket_wwr = 1880.0 / (supermarket_p * 20.0)
    supermarket_aspect_ratio = calc_aspect_ratio(supermarket_a, supermarket_p)

    hash['SmallOffice'] = { aspect_ratio: 1.5, wwr: 0.15, typical_story: 10.0, perim_mult: 1.0 }
    hash['MediumOffice'] = { aspect_ratio: 1.5, wwr: 0.33, typical_story: 13.0, perim_mult: 1.0 }
    hash['LargeOffice'] = { aspect_ratio: 1.5, wwr: 0.15, typical_story: 13.0, perim_mult: 1.0 }
    hash['RetailStandalone'] = { aspect_ratio: 1.28, wwr: 0.07, typical_story: 20.0, perim_mult: 1.0 }
    hash['RetailStripmall'] = { aspect_ratio: 4.0, wwr: 0.11, typical_story: 17.0, perim_mult: 1.0 }
    hash['PrimarySchool'] = { aspect_ratio: primary_ns_ew_ratio.round(1), wwr: 0.35, typical_story: 13.0, perim_mult: primary_p_mult.round(3) }
    hash['SecondarySchool'] = { aspect_ratio: secondary_ns_ew_ratio.round(1), wwr: 0.33, typical_story: 13.0, perim_mult: secondary_p_mult.round(3) }
    hash['Outpatient'] = { aspect_ratio: outpatient_ns_ew_ratio.round(1), wwr: 0.20, typical_story: 10.0, perim_mult: outpatient_p_mult.round(3) }
    hash['Hospital'] = { aspect_ratio: 1.33, wwr: 0.16, typical_story: 14.0, perim_mult: 1.0 }
    hash['SmallHotel'] = { aspect_ratio: 3.0, wwr: 0.11, typical_story: 9.0, first_story: 11.0, perim_mult: 1.0 }
    hash['LargeHotel'] = { aspect_ratio: 5.1, wwr: 0.27, typical_story: 10.0, first_story: 13.0, perim_mult: 1.0 }

    # code in get_space_types_from_building_type is used to override building wwr with space type specific wwr
    hash['Warehouse'] = { aspect_ratio: 2.2, wwr: 0.0, typical_story: 28.0, perim_mult: 1.0 }

    hash['QuickServiceRestaurant'] = { aspect_ratio: 1.0, wwr: 0.14, typical_story: 10.0, perim_mult: 1.0 }
    hash['FullServiceRestaurant'] = { aspect_ratio: 1.0, wwr: 0.18, typical_story: 10.0, perim_mult: 1.0 }
    hash['QuickServiceRestaurant'] = { aspect_ratio: 1.0, wwr: 0.18, typical_story: 10.0, perim_mult: 1.0 }
    hash['MidriseApartment'] = { aspect_ratio: 2.75, wwr: 0.15, typical_story: 10.0, perim_mult: 1.0 }
    hash['HighriseApartment'] = { aspect_ratio: 2.75, wwr: 0.15, typical_story: 10.0, perim_mult: 1.0 }
    # SuperMarket inputs come from prototype model
    hash['SuperMarket'] = { aspect_ratio: supermarket_aspect_ratio.round(1), wwr: supermarket_wwr.round(2), typical_story: 20.0, perim_mult: 1.0 }

    # Add Laboratory and Data Centers
    hash['Laboratory'] = { aspect_ratio: 1.33, wwr: 0.12, typical_story: 10.0, perim_mult: 1.0 }
    hash['LargeDataCenterLowITE'] = { aspect_ratio: 1.67, wwr: 0.0, typical_story: 14.0, perim_mult: 1.0 }
    hash['LargeDataCenterHighITE'] = { aspect_ratio: 1.67, wwr: 0.0, typical_story: 14.0, perim_mult: 1.0 }
    hash['SmallDataCenterLowITE'] = { aspect_ratio: 1.5, wwr: 0.0, typical_story: 14.0, perim_mult: 1.0 }
    hash['SmallDataCenterHighITE'] = { aspect_ratio: 1.5, wwr: 0.0, typical_story: 14.0, perim_mult: 1.0 }

    # DEER Prototypes
    hash['Asm'] = { aspect_ratio: 1.0, wwr: 0.19, typical_story: 15.0 }
    hash['ECC'] = { aspect_ratio: 4.0, wwr: 0.25, typical_story: 13.0 }
    hash['EPr'] = { aspect_ratio: 2.0, wwr: 0.16, typical_story: 12.0 }
    hash['ERC'] = { aspect_ratio: 1.7, wwr: 0.03, typical_story: 12.0 }
    hash['ESe'] = { aspect_ratio: 1.0, wwr: 0.15, typical_story: 13.0 }
    hash['EUn'] = { aspect_ratio: 2.5, wwr: 0.3, typical_story: 14.0 }
    hash['Gro'] = { aspect_ratio: 1.0, wwr: 0.07, typical_story: 25.0 }
    hash['Hsp'] = { aspect_ratio: 1.5, wwr: 0.11, typical_story: 13.0 }
    hash['Htl'] = { aspect_ratio: 3.0, wwr: 0.23, typical_story: 9.5, first_story: 12.0 }
    hash['MBT'] = { aspect_ratio: 10.7, wwr: 0.12, typical_story: 15.0 }
    hash['MFm'] = { aspect_ratio: 1.4, wwr: 0.24, typical_story: 9.5 }
    hash['MLI'] = { aspect_ratio: 1.0, wwr: 0.01, typical_story: 35.0 }
    hash['Mtl'] = { aspect_ratio: 5.1, wwr: 0.41, typical_story: 9.0 }
    hash['Nrs'] = { aspect_ratio: 10.3, wwr: 0.2, typical_story: 13.0 }
    hash['OfL'] = { aspect_ratio: 1.5, wwr: 0.33, typical_story: 12.0 }
    hash['OfS'] = { aspect_ratio: 1.5, wwr: 0.33, typical_story: 12.0 }
    hash['RFF'] = { aspect_ratio: 1.0, wwr: 0.25, typical_story: 13.0 }
    hash['RSD'] = { aspect_ratio: 1.0, wwr: 0.13, typical_story: 13.0 }
    hash['Rt3'] = { aspect_ratio: 1.0, wwr: 0.02, typical_story: 20.8 }
    hash['RtL'] = { aspect_ratio: 1.0, wwr: 0.03, typical_story: 20.5 }
    hash['RtS'] = { aspect_ratio: 1.0, wwr: 0.13, typical_story: 12.0 }
    hash['SCn'] = { aspect_ratio: 1.0, wwr: 0.01, typical_story: 48.0 }
    hash['SUn'] = { aspect_ratio: 1.0, wwr: 0.01, typical_story: 48.0 }
    hash['WRf'] = { aspect_ratio: 1.6, wwr: 0.0, typical_story: 32.0 }

    return hash[building_type]
  end

  # create hash of space types and generic ratios of building floor area
  # currently no reason to split apart doe and deer inputs here
  def get_space_types_from_building_type(building_type, template, whole_building = true)
    hash = {}

    # TODO: - Confirm that these work for all standards
    # DOE Prototypes
    if building_type == 'SecondarySchool'
      if ['DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'].include?(template)
        hash['Auditorium'] = { ratio: 0.0504, space_type_gen: true, default: false, story_height: 26.0 }
        hash['Cafeteria'] = { ratio: 0.0319, space_type_gen: true, default: false }
        hash['Classroom'] = { ratio: 0.3528, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.2144, space_type_gen: true, default: false, circ: true }
        hash['Gym'] = { ratio: 0.1009, space_type_gen: true, default: false, story_height: 26.0 }
        hash['Gym - audience'] = { ratio: 0.0637, space_type_gen: true, default: false, story_height: 26.0 }
        hash['Kitchen'] = { ratio: 0.0110, space_type_gen: true, default: false }
        hash['Library'] = { ratio: 0.0429, space_type_gen: true, default: false }
        hash['Lobby'] = { ratio: 0.0214, space_type_gen: true, default: false }
        hash['Mechanical'] = { ratio: 0.0349, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0543, space_type_gen: true, default: false }
        hash['Restroom'] = { ratio: 0.0214, space_type_gen: true, default: false }
      else
        hash['Auditorium'] = { ratio: 0.0504, space_type_gen: true, default: false, story_height: 26.0 }
        hash['Cafeteria'] = { ratio: 0.0319, space_type_gen: true, default: false }
        hash['Classroom'] = { ratio: 0.3041, space_type_gen: true, default: true }
        hash['ComputerRoom'] = { ratio: 0.0487, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.2144, space_type_gen: true, default: false, circ: true }
        hash['Gym'] = { ratio: 0.1646, space_type_gen: true, default: false, story_height: 26.0 }
        hash['Kitchen'] = { ratio: 0.0110, space_type_gen: true, default: false }
        hash['Library'] = { ratio: 0.0429, space_type_gen: true, default: false }
        hash['Lobby'] = { ratio: 0.0214, space_type_gen: true, default: false }
        hash['Mechanical'] = { ratio: 0.0349, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0543, space_type_gen: true, default: false }
        hash['Restroom'] = { ratio: 0.0214, space_type_gen: true, default: false }
      end
    elsif building_type == 'PrimarySchool'
      if ['DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'].include?(template)
        # updated to 2004 which includes library vs. pre-1980
        hash['Cafeteria'] = { ratio: 0.0458, space_type_gen: true, default: false }
        hash['Classroom'] = { ratio: 0.5610, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.1633, space_type_gen: true, default: false, circ: true }
        hash['Gym'] = { ratio: 0.0520, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.0244, space_type_gen: true, default: false }
        hash['Library'] = { ratio: 0.0, space_type_gen: true, default: false } # no library in model
        hash['Lobby'] = { ratio: 0.0249, space_type_gen: true, default: false }
        hash['Mechanical'] = { ratio: 0.0367, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0642, space_type_gen: true, default: false }
        hash['Restroom'] = { ratio: 0.0277, space_type_gen: true, default: false }
      else
        # updated to 2004 which includes library vs. pre-1980
        hash['Cafeteria'] = { ratio: 0.0458, space_type_gen: true, default: false }
        hash['Classroom'] = { ratio: 0.4793, space_type_gen: true, default: true }
        hash['ComputerRoom'] = { ratio: 0.0236, space_type_gen: true, default: true }
        hash['Corridor'] = { ratio: 0.1633, space_type_gen: true, default: false, circ: true }
        hash['Gym'] = { ratio: 0.0520, space_type_gen: true, default: false }
        hash['Kitchen'] = { ratio: 0.0244, space_type_gen: true, default: false }
        hash['Library'] = { ratio: 0.0581, space_type_gen: true, default: false }
        hash['Lobby'] = { ratio: 0.0249, space_type_gen: true, default: false }
        hash['Mechanical'] = { ratio: 0.0367, space_type_gen: true, default: false }
        hash['Office'] = { ratio: 0.0642, space_type_gen: true, default: false }
        hash['Restroom'] = { ratio: 0.0277, space_type_gen: true, default: false }
      end
    elsif building_type == 'SmallOffice'
      # TODO: - populate Small, Medium, and Large office for whole_building false
      if whole_building
        hash['WholeBuilding - Sm Office'] = { ratio: 1.0, space_type_gen: true, default: true }
      else
        hash['SmallOffice - Breakroom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - ClosedOffice'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Conference'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Corridor'] = { ratio: 0.99, space_type_gen: true, default: false, circ: true }
        hash['SmallOffice - Elec/MechRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Lobby'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - OpenOffice'] = { ratio: 0.99, space_type_gen: true, default: true }
        hash['SmallOffice - Restroom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Stair'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Storage'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Classroom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['SmallOffice - Dining'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['WholeBuilding - Sm Office'] = { ratio: 0.0, space_type_gen: true, default: false }
      end
    elsif building_type == 'MediumOffice'
      if whole_building
        hash['WholeBuilding - Md Office'] = { ratio: 1.0, space_type_gen: true, default: true }
      else
        hash['MediumOffice - Breakroom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - ClosedOffice'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Conference'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Corridor'] = { ratio: 0.99, space_type_gen: true, default: false, circ: true }
        hash['MediumOffice - Elec/MechRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Lobby'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - OpenOffice'] = { ratio: 0.99, space_type_gen: true, default: true }
        hash['MediumOffice - Restroom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Stair'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Storage'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Classroom'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['MediumOffice - Dining'] = { ratio: 0.99, space_type_gen: true, default: false }
        hash['WholeBuilding - Md Office'] = { ratio: 0.0, space_type_gen: true, default: false }
      end
    elsif building_type == 'LargeOffice'
      if ['DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'].include?(template)
        if whole_building
          hash['WholeBuilding - Lg Office'] = { ratio: 1.0, space_type_gen: true, default: true }
        else
          hash['BreakRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['ClosedOffice'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Conference'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Corridor'] = { ratio: 0.99, space_type_gen: true, default: false, circ: true }
          hash['Elec/MechRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['IT_Room'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Lobby'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['OpenOffice'] = { ratio: 0.99, space_type_gen: true, default: true }
          hash['PrintRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Restroom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Stair'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Storage'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Vending'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['WholeBuilding - Lg Office'] = { ratio: 0.0, space_type_gen: true, default: false }
        end
      else
        if whole_building
          hash['WholeBuilding - Lg Office'] = { ratio: 0.9737, space_type_gen: true, default: true }
          hash['OfficeLarge Data Center'] = { ratio: 0.0094, space_type_gen: true, default: false }
          hash['OfficeLarge Main Data Center'] = { ratio: 0.0169, space_type_gen: true, default: false }
        else
          hash['BreakRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['ClosedOffice'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Conference'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Corridor'] = { ratio: 0.99, space_type_gen: true, default: false, circ: true }
          hash['Elec/MechRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['IT_Room'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Lobby'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['OpenOffice'] = { ratio: 0.99, space_type_gen: true, default: true }
          hash['PrintRoom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Restroom'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Stair'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Storage'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['Vending'] = { ratio: 0.99, space_type_gen: true, default: false }
          hash['WholeBuilding - Lg Office'] = { ratio: 0.0, space_type_gen: true, default: false }
          hash['OfficeLarge Data Center'] = { ratio: 0.0, space_type_gen: true, default: false }
          hash['OfficeLarge Main Data Center'] = { ratio: 0.0, space_type_gen: true, default: false }
        end
      end
    elsif building_type == 'SmallHotel'
      hash['Corridor'] = { ratio: 0.1313, space_type_gen: true, default: false, circ: true }
      hash['Elec/MechRoom'] = { ratio: 0.0038, space_type_gen: true, default: false }
      hash['ElevatorCore'] = { ratio: 0.0113, space_type_gen: true, default: false }
      hash['Exercise'] = { ratio: 0.0081, space_type_gen: true, default: false }
      hash['GuestLounge'] = { ratio: 0.0406, space_type_gen: true, default: false }
      hash['GuestRoom123Occ'] = { ratio: 0.4081, space_type_gen: true, default: true }
      hash['GuestRoom123Vac'] = { ratio: 0.2231, space_type_gen: true, default: false }
      hash['Laundry'] = { ratio: 0.0244, space_type_gen: true, default: false }
      hash['Mechanical'] = { ratio: 0.0081, space_type_gen: true, default: false }
      hash['Meeting'] = { ratio: 0.0200, space_type_gen: true, default: false }
      hash['Office'] = { ratio: 0.0325, space_type_gen: true, default: false }
      hash['PublicRestroom'] = { ratio: 0.0081, space_type_gen: true, default: false }
      hash['StaffLounge'] = { ratio: 0.0081, space_type_gen: true, default: false }
      hash['Stair'] = { ratio: 0.0400, space_type_gen: true, default: false }
      hash['Storage'] = { ratio: 0.0325, space_type_gen: true, default: false }
    elsif building_type == 'LargeHotel'
      hash['Banquet'] = { ratio: 0.0585, space_type_gen: true, default: false }
      hash['Basement'] = { ratio: 0.1744, space_type_gen: false, default: false }
      hash['Cafe'] = { ratio: 0.0166, space_type_gen: true, default: false }
      hash['Corridor'] = { ratio: 0.1736, space_type_gen: true, default: false, circ: true }
      hash['GuestRoom'] = { ratio: 0.4099, space_type_gen: true, default: true }
      hash['Kitchen'] = { ratio: 0.0091, space_type_gen: true, default: false }
      hash['Laundry'] = { ratio: 0.0069, space_type_gen: true, default: false }
      hash['Lobby'] = { ratio: 0.1153, space_type_gen: true, default: false }
      hash['Mechanical'] = { ratio: 0.0145, space_type_gen: true, default: false }
      hash['Retail'] = { ratio: 0.0128, space_type_gen: true, default: false }
      hash['Storage'] = { ratio: 0.0084, space_type_gen: true, default: false }
    elsif building_type == 'Warehouse'
      hash['Bulk'] = { ratio: 0.6628, space_type_gen: true, default: true }
      hash['Fine'] = { ratio: 0.2882, space_type_gen: true, default: false }
      hash['Office'] = { ratio: 0.0490, space_type_gen: true, default: false, wwr: 0.71, story_height: 14.0 }
    elsif building_type == 'RetailStandalone'
      hash['Back_Space'] = { ratio: 0.1656, space_type_gen: true, default: false }
      hash['Entry'] = { ratio: 0.0052, space_type_gen: true, default: false }
      hash['Point_of_Sale'] = { ratio: 0.0657, space_type_gen: true, default: false }
      hash['Retail'] = { ratio: 0.7635, space_type_gen: true, default: true }
    elsif building_type == 'RetailStripmall'
      hash['Strip mall - type 1'] = { ratio: 0.25, space_type_gen: true, default: false }
      hash['Strip mall - type 2'] = { ratio: 0.25, space_type_gen: true, default: false }
      hash['Strip mall - type 3'] = { ratio: 0.50, space_type_gen: true, default: true }
    elsif building_type == 'QuickServiceRestaurant'
      hash['Dining'] = { ratio: 0.5, space_type_gen: true, default: true }
      hash['Kitchen'] = { ratio: 0.5, space_type_gen: true, default: false }
    elsif building_type == 'FullServiceRestaurant'
      hash['Dining'] = { ratio: 0.7272, space_type_gen: true, default: true }
      hash['Kitchen'] = { ratio: 0.2728, space_type_gen: true, default: false }
    elsif building_type == 'MidriseApartment'
      hash['Apartment'] = { ratio: 0.8727, space_type_gen: true, default: true }
      hash['Corridor'] = { ratio: 0.0991, space_type_gen: true, default: false, circ: true }
      hash['Office'] = { ratio: 0.0282, space_type_gen: true, default: false }
    elsif building_type == 'HighriseApartment'
      hash['Apartment'] = { ratio: 0.8896, space_type_gen: true, default: true }
      hash['Corridor'] = { ratio: 0.0991, space_type_gen: true, default: false, circ: true }
      hash['Office'] = { ratio: 0.0113, space_type_gen: true, default: false }
    elsif building_type == 'Hospital'
      hash['Basement'] = { ratio: 0.1667, space_type_gen: false, default: false }
      hash['Corridor'] = { ratio: 0.1741, space_type_gen: true, default: false, circ: true }
      hash['Dining'] = { ratio: 0.0311, space_type_gen: true, default: false }
      hash['ER_Exam'] = { ratio: 0.0099, space_type_gen: true, default: false }
      hash['ER_NurseStn'] = { ratio: 0.0551, space_type_gen: true, default: false }
      hash['ER_Trauma'] = { ratio: 0.0025, space_type_gen: true, default: false }
      hash['ER_Triage'] = { ratio: 0.0050, space_type_gen: true, default: false }
      hash['ICU_NurseStn'] = { ratio: 0.0298, space_type_gen: true, default: false }
      hash['ICU_Open'] = { ratio: 0.0275, space_type_gen: true, default: false }
      hash['ICU_PatRm'] = { ratio: 0.0115, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.0414, space_type_gen: true, default: false }
      hash['Lab'] = { ratio: 0.0236, space_type_gen: true, default: false }
      hash['Lobby'] = { ratio: 0.0657, space_type_gen: true, default: false }
      hash['NurseStn'] = { ratio: 0.1723, space_type_gen: true, default: false }
      hash['Office'] = { ratio: 0.0286, space_type_gen: true, default: false }
      hash['OR'] = { ratio: 0.0273, space_type_gen: true, default: false }
      hash['PatCorridor'] = { ratio: 0.0, space_type_gen: true, default: false } # not in prototype
      hash['PatRoom'] = { ratio: 0.0845, space_type_gen: true, default: true }
      hash['PhysTherapy'] = { ratio: 0.0217, space_type_gen: true, default: false }
      hash['Radiology'] = { ratio: 0.0217, space_type_gen: true, default: false }
    elsif building_type == 'Outpatient'
      hash['Anesthesia'] = { ratio: 0.0026, space_type_gen: true, default: false }
      hash['BioHazard'] = { ratio: 0.0014, space_type_gen: true, default: false }
      hash['Cafe'] = { ratio: 0.0103, space_type_gen: true, default: false }
      hash['CleanWork'] = { ratio: 0.0071, space_type_gen: true, default: false }
      hash['Conference'] = { ratio: 0.0082, space_type_gen: true, default: false }
      hash['DressingRoom'] = { ratio: 0.0021, space_type_gen: true, default: false }
      hash['Elec/MechRoom'] = { ratio: 0.0109, space_type_gen: true, default: false }
      hash['ElevatorPumpRoom'] = { ratio: 0.0022, space_type_gen: true, default: false }
      hash['Exam'] = { ratio: 0.1029, space_type_gen: true, default: true }
      hash['Hall'] = { ratio: 0.1924, space_type_gen: true, default: false, circ: true }
      hash['IT_Room'] = { ratio: 0.0027, space_type_gen: true, default: false }
      hash['Janitor'] = { ratio: 0.0672, space_type_gen: true, default: false }
      hash['Lobby'] = { ratio: 0.0152, space_type_gen: true, default: false }
      hash['LockerRoom'] = { ratio: 0.0190, space_type_gen: true, default: false }
      hash['Lounge'] = { ratio: 0.0293, space_type_gen: true, default: false }
      hash['MedGas'] = { ratio: 0.0014, space_type_gen: true, default: false }
      hash['MRI'] = { ratio: 0.0107, space_type_gen: true, default: false }
      hash['MRI_Control'] = { ratio: 0.0041, space_type_gen: true, default: false }
      hash['NurseStation'] = { ratio: 0.0189, space_type_gen: true, default: false }
      hash['Office'] = { ratio: 0.1828, space_type_gen: true, default: false }
      hash['OR'] = { ratio: 0.0346, space_type_gen: true, default: false }
      hash['PACU'] = { ratio: 0.0232, space_type_gen: true, default: false }
      hash['PhysicalTherapy'] = { ratio: 0.0462, space_type_gen: true, default: false }
      hash['PreOp'] = { ratio: 0.0129, space_type_gen: true, default: false }
      hash['ProcedureRoom'] = { ratio: 0.0070, space_type_gen: true, default: false }
      hash['Reception'] = { ratio: 0.0365, space_type_gen: true, default: false }
      hash['Soil Work'] = { ratio: 0.0088, space_type_gen: true, default: false }
      hash['Stair'] = { ratio: 0.0146, space_type_gen: true, default: false }
      hash['Toilet'] = { ratio: 0.0193, space_type_gen: true, default: false }
      hash['Undeveloped'] = { ratio: 0.0835, space_type_gen: false, default: false }
      hash['Xray'] = { ratio: 0.0220, space_type_gen: true, default: false }
    elsif building_type == 'SuperMarket'
      # TODO: - populate ratios for SuperMarket
      hash['Bakery'] = { ratio: 0.99, space_type_gen: true, default: false }
      hash['Deli'] = { ratio: 0.99, space_type_gen: true, default: false }
      hash['DryStorage'] = { ratio: 0.99, space_type_gen: true, default: false }
      hash['Office'] = { ratio: 0.99, space_type_gen: true, default: false }
      hash['Produce'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Sales'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Corridor'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Dining'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Elec/MechRoom'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Meeting'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Restroom'] = { ratio: 0.99, space_type_gen: true, default: true }
      hash['Vestibule'] = { ratio: 0.99, space_type_gen: true, default: true }
    elsif building_type == 'Laboratory'
      hash['Office'] = { ratio: 0.50, space_type_gen: true, default: true }
      hash['Open lab'] = { ratio: 0.35, space_type_gen: true, default: true }
      hash['Equipment corridor'] = { ratio: 0.05, space_type_gen: true, default: true }
      hash['Lab with fume hood'] = { ratio: 0.10, space_type_gen: true, default: true }
    elsif building_type == 'LargeDataCenterHighITE'
      hash['StandaloneDataCenter'] = { ratio: 1.0, space_type_gen: true, default: true }
    elsif building_type == 'LargeDataCenterLowITE'
      hash['StandaloneDataCenter'] = { ratio: 1.0, space_type_gen: true, default: true }
    elsif building_type == 'SmallDataCenterHighITE'
      hash['ComputerRoom'] = { ratio: 1.0, space_type_gen: true, default: true }
    elsif building_type == 'SmallDataCenterLowITE'
      hash['ComputerRoom'] = { ratio: 1.0, space_type_gen: true, default: true }
      # DEER Prototypes
    elsif building_type == 'Asm'
      hash['Auditorium'] = { ratio: 0.7658, space_type_gen: true, default: true }
      hash['OfficeGeneral'] = { ratio: 0.2342, space_type_gen: true, default: false }
    elsif building_type == 'ECC'
      hash['Classroom'] = { ratio: 0.5558, space_type_gen: true, default: true }
      hash['CompRoomClassRm'] = { ratio: 0.0319, space_type_gen: true, default: false }
      hash['Shop'] = { ratio: 0.1249, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.0876, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.0188, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.181, space_type_gen: true, default: false }
    elsif building_type == 'EPr'
      hash['Classroom'] = { ratio: 0.53, space_type_gen: true, default: true }
      hash['CorridorStairway'] = { ratio: 0.1, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.15, space_type_gen: true, default: false }
      hash['Gymnasium'] = { ratio: 0.15, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.07, space_type_gen: true, default: false }
    elsif building_type == 'ERC'
      hash['Classroom'] = { ratio: 0.5, space_type_gen: true, default: true }
    elsif building_type == 'ESe'
      hash['Classroom'] = { ratio: 0.488, space_type_gen: true, default: true }
      hash['CompRoomClassRm'] = { ratio: 0.021, space_type_gen: true, default: false }
      hash['CorridorStairway'] = { ratio: 0.1, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.15, space_type_gen: true, default: false }
      hash['Gymnasium'] = { ratio: 0.15, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.07, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.021, space_type_gen: true, default: true }
    elsif building_type == 'EUn'
      hash['Dining'] = { ratio: 0.0238, space_type_gen: true, default: false }
      hash['Classroom'] = { ratio: 0.3056, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.3422, space_type_gen: true, default: true }
      hash['CompRoomClassRm'] = { ratio: 0.038, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.0105, space_type_gen: true, default: false }
      hash['CorridorStairway'] = { ratio: 0.03, space_type_gen: true, default: false }
      hash['FacMaint'] = { ratio: 0.08, space_type_gen: true, default: false }
      hash['DormitoryRoom'] = { ratio: 0.1699, space_type_gen: true, default: false }
    elsif building_type == 'Gro'
      hash['GrocSales'] = { ratio: 0.8002, space_type_gen: true, default: true }
      hash['RefWalkInCool'] = { ratio: 0.0312, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.07, space_type_gen: true, default: false }
      hash['RefFoodPrep'] = { ratio: 0.0253, space_type_gen: true, default: false }
      hash['RefWalkInFreeze'] = { ratio: 0.0162, space_type_gen: true, default: false }
      hash['IndLoadDock'] = { ratio: 0.057, space_type_gen: true, default: false }
    elsif building_type == 'Hsp'
      hash['HspSurgOutptLab'] = { ratio: 0.2317, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.0172, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.0075, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.3636, space_type_gen: true, default: false }
      hash['PatientRoom'] = { ratio: 0.38, space_type_gen: true, default: true }
    elsif building_type == 'Htl'
      hash['Dining'] = { ratio: 0.004, space_type_gen: true, default: false }
      hash['BarCasino'] = { ratio: 0.005, space_type_gen: true, default: false }
      hash['HotelLobby'] = { ratio: 0.0411, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.0205, space_type_gen: true, default: false }
      hash['GuestRmCorrid'] = { ratio: 0.1011, space_type_gen: true, default: false }
      hash['Laundry'] = { ratio: 0.0205, space_type_gen: true, default: false }
      hash['GuestRmOcc'] = { ratio: 0.64224, space_type_gen: true, default: true }
      hash['GuestRmUnOcc'] = { ratio: 0.16056, space_type_gen: true, default: true }
      hash['Kitchen'] = { ratio: 0.005, space_type_gen: true, default: false }
    elsif building_type == 'MBT'
      hash['CompRoomData'] = { ratio: 0.02, space_type_gen: true, default: false }
      hash['Laboratory'] = { ratio: 0.4534, space_type_gen: true, default: true }
      hash['CorridorStairway'] = { ratio: 0.2, space_type_gen: true, default: false }
      hash['Conference'] = { ratio: 0.02, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.03, space_type_gen: true, default: false }
      hash['OfficeOpen'] = { ratio: 0.2666, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.01, space_type_gen: true, default: false }
    elsif building_type == 'MFm'
      hash['ResLiving'] = { ratio: 0.9297, space_type_gen: true, default: true }
      hash['ResPublicArea'] = { ratio: 0.0725, space_type_gen: true, default: false }
    elsif building_type == 'MLI'
      hash['StockRoom'] = { ratio: 0.2, space_type_gen: true, default: false }
      hash['Work'] = { ratio: 0.8, space_type_gen: true, default: true }
    elsif building_type == 'Mtl'
      hash['OfficeGeneral'] = { ratio: 0.02, space_type_gen: true, default: false }
      hash['GuestRmCorrid'] = { ratio: 0.649, space_type_gen: true, default: true }
      hash['Laundry'] = { ratio: 0.016, space_type_gen: true, default: false }
      hash['GuestRmOcc'] = { ratio: 0.25208, space_type_gen: true, default: false }
      hash['GuestRmUnOcc'] = { ratio: 0.06302, space_type_gen: true, default: false }
    elsif building_type == 'Nrs'
      hash['CorridorStairway'] = { ratio: 0.0555, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.105, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.045, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.35, space_type_gen: true, default: false }
      hash['PatientRoom'] = { ratio: 0.4445, space_type_gen: true, default: true }
    elsif building_type == 'OfL'
      hash['LobbyWaiting'] = { ratio: 0.0412, space_type_gen: true, default: false }
      hash['OfficeSmall'] = { ratio: 0.3704, space_type_gen: true, default: false }
      hash['OfficeOpen'] = { ratio: 0.5296, space_type_gen: true, default: true }
      hash['MechElecRoom'] = { ratio: 0.0588, space_type_gen: true, default: false }
    elsif building_type == 'OfS'
      hash['Hall'] = { ratio: 0.3141, space_type_gen: true, default: false }
      hash['OfficeSmall'] = { ratio: 0.6859, space_type_gen: true, default: true }
    elsif building_type == 'RFF'
      hash['Dining'] = { ratio: 0.3997, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.4, space_type_gen: true, default: true }
      hash['LobbyWaiting'] = { ratio: 0.1501, space_type_gen: true, default: false }
      hash['Restroom'] = { ratio: 0.0501, space_type_gen: true, default: false }
    elsif building_type == 'RSD'
      hash['Restroom'] = { ratio: 0.0357, space_type_gen: true, default: false }
      hash['Dining'] = { ratio: 0.5353, space_type_gen: true, default: true }
      hash['LobbyWaiting'] = { ratio: 0.1429, space_type_gen: true, default: false }
      hash['Kitchen'] = { ratio: 0.2861, space_type_gen: true, default: false }
    elsif building_type == 'Rt3'
      hash['RetailSales'] = { ratio: 1.0, space_type_gen: true, default: true }
    elsif building_type == 'RtL'
      hash['OfficeGeneral'] = { ratio: 0.0363, space_type_gen: true, default: false }
      hash['Work'] = { ratio: 0.0405, space_type_gen: true, default: false }
      hash['StockRoom'] = { ratio: 0.0920, space_type_gen: true, default: false }
      hash['RetailSales'] = { ratio: 0.8312, space_type_gen: true, default: true }
      #hash['Kitchen'] = { ratio: 0.0113, space_type_gen: true, default: false }
    elsif building_type == 'RtS'
      hash['RetailSales'] = { ratio: 0.8, space_type_gen: true, default: true }
      hash['StockRoom'] = { ratio: 0.2, space_type_gen: true, default: false }
    elsif building_type == 'SCn'
      hash['WarehouseCond'] = { ratio: 1.0, space_type_gen: true, default: true }
    elsif building_type == 'SUn'
      hash['WarehouseUnCond'] = { ratio: 1.0, space_type_gen: true, default: true }
    elsif building_type == 'WRf'
      hash['IndLoadDock'] = { ratio: 0.08, space_type_gen: true, default: false }
      hash['OfficeGeneral'] = { ratio: 0.02, space_type_gen: true, default: false }
      hash['RefStorFreezer'] = { ratio: 0.4005, space_type_gen: true, default: false }
      hash['RefStorCooler'] = { ratio: 0.4995, space_type_gen: true, default: true }
    else
      return false
    end

    return hash
  end

  # remove existing non resource objects from the model
  # technically thermostats and building stories are resources but still want to remove them.
  def remove_non_resource_objects(runner, model, options = nil)
    if options.nil?
      options = {}
      options[:remove_building_stories] = true
      options[:remove_thermostats] = true
      options[:remove_air_loops] = true
      options[:remove_non_swh_plant_loops] = true

      # leave these in by default unless requsted when method called
      options[:remove_swh_plant_loops] = false
      options[:remove_exterior_lights] = false
      options[:remove_site_shading] = false
    end

    num_model_objects = model.objects.size

    # remove non-resource objects not removed by removing the building
    if options[:remove_building_stories] then model.getBuildingStorys.each(&:remove) end
    if options[:remove_thermostats] then model.getThermostats.each(&:remove) end
    if options[:remove_air_loops] then model.getAirLoopHVACs.each(&:remove) end
    if options[:remove_exterior_lights] then model.getFacility.exteriorLights.each(&:remove) end
    if options[:remove_site_shading] then model.getSite.shadingSurfaceGroups.each(&:remove) end

    # see if plant loop is swh or not and take proper action (booter loop doesn't have water use equipment)
    model.getPlantLoops.each do |plant_loop|
      is_swh_loop = false
      plant_loop.supplyComponents.each do |component|
        if component.to_WaterHeaterMixed.is_initialized
          is_swh_loop = true
          next
        end
      end

      if is_swh_loop
        if options[:remove_swh_plant_loops] then plant_loop.remove end
      else
        if options[:remove_non_swh_plant_loops] then plant_loop.remove end
      end
    end

    # remove water use connections (may be removed when loop is removed)
    if options[:remove_swh_plant_loops] then model.getWaterConnectionss.each(&:remove) end
    if options[:remove_swh_plant_loops] then model.getWaterUseEquipments.each(&:remove) end

    # remove building but reset fields on new building object.
    building_fields = []
    building = model.getBuilding
    num_fields = building.numFields
    num_fields.times.each do |i|
      building_fields << building.getString(i).get
    end
    # removes spaces, space's child objects, thermal zones, zone equipment, non site surfaces, building stories and water use connections.
    model.getBuilding.remove
    building = model.getBuilding
    num_fields.times.each do |i|
      next if i == 0 # don't try and set handle
      building_fields << building.setString(i, building_fields[i])
    end

    # other than optionally site shading and exterior lights not messing with site characteristics

    if num_model_objects - model.objects.size > 0
      runner.registerInfo("Removed #{num_model_objects - model.objects.size} non resource objects from the model.")
    end

    return true
  end

  # create_bar(runner,model,bar_hash)
  # measures using this method should include OsLibGeometry and OsLibHelperMethods
  def create_bar(runner, model, bar_hash, story_multiplier_method = 'Basements Ground Mid Top')
    # warn about site shading
    if !model.getSite.shadingSurfaceGroups.empty?
      runner.registerWarning('The model has one or more site shading surafces. New geometry may not be positioned where expected, it will be centered over the center of the original geometry.')
    end

    # make custom story hash when number of stories below grade > 0
    # todo - update this so have option basements are not below 0? (useful for simplifying existing model and maintaining z position relative to site shading)
    story_hash = {}
    eff_below = bar_hash[:num_stories_below_grade]
    eff_above = bar_hash[:num_stories_above_grade]
    footprint_origin = bar_hash[:center_of_footprint]
    typical_story_height = bar_hash[:floor_height]

    # flatten story_hash out to individual stories included in building area
    stories_flat = []
    stories_flat_counter = 0
    bar_hash[:stories].each_with_index do |(k, v), i|
      # k is invalid in some cases, old story object that has been removed, should be from low to high including basement
      # skip if source story insn't included in building area
      if v[:story_included_in_building_area].nil? || (v[:story_included_in_building_area] == true)

        # add to counter
        stories_flat_counter += v[:story_min_multiplier]

        flat_hash = {}
        flat_hash[:story_party_walls] = v[:story_party_walls]
        flat_hash[:below_partial_story] = v[:below_partial_story]
        flat_hash[:bottom_story_ground_exposed_floor] = v[:bottom_story_ground_exposed_floor]
        flat_hash[:top_story_exterior_exposed_roof] = v[:top_story_exterior_exposed_roof]
        if i < eff_below
          flat_hash[:story_type] = 'B'
          flat_hash[:multiplier] = 1
        elsif i == eff_below
          flat_hash[:story_type] = 'Ground'
          flat_hash[:multiplier] = 1
        elsif stories_flat_counter == eff_below + eff_above.ceil
          flat_hash[:story_type] = 'Top'
          flat_hash[:multiplier] = 1
        else
          flat_hash[:story_type] = 'Mid'
          flat_hash[:multiplier] = v[:story_min_multiplier]
        end

        compare_hash = {}
        if !stories_flat.empty?
          stories_flat.last.each { |k, v| compare_hash[k] = flat_hash[k] if flat_hash[k] != v }
        end
        if (story_multiplier_method != 'None' && stories_flat.last == flat_hash) || (story_multiplier_method != 'None' && compare_hash.size == 1 && compare_hash.include?(:multiplier))
          stories_flat.last[:multiplier] += v[:story_min_multiplier]
        else
          stories_flat << flat_hash
        end
      end
    end

    if bar_hash[:num_stories_below_grade] > 0

      # add in below grade levels (may want to add below grade multipliers at some point if we start running deep basements)
      eff_below.times do |i|
        story_hash["B#{i + 1}"] = { space_origin_z: footprint_origin.z - typical_story_height * (i + 1), space_height: typical_story_height, multiplier: 1 }
      end
    end

    # add in above grade levels
    if eff_above > 2
      story_hash['Ground'] = { space_origin_z: footprint_origin.z, space_height: typical_story_height, multiplier: 1 }

      footprint_counter = 0
      effective_stories_counter = 1
      stories_flat.each do |hash|
        next if hash[:story_type] != 'Mid'
        if footprint_counter == 0
          string = 'Mid'
        else
          string = "Mid#{footprint_counter + 1}"
        end
        story_hash[string] = { space_origin_z: footprint_origin.z + typical_story_height * effective_stories_counter + typical_story_height * (hash[:multiplier] - 1) / 2.0, space_height: typical_story_height, multiplier: hash[:multiplier] }
        footprint_counter += 1
        effective_stories_counter += hash[:multiplier]
      end

      story_hash['Top'] = { space_origin_z: footprint_origin.z + typical_story_height * (eff_above.ceil - 1), space_height: typical_story_height, multiplier: 1 }
    elsif eff_above > 1
      story_hash['Ground'] = { space_origin_z: footprint_origin.z, space_height: typical_story_height, multiplier: 1 }
      story_hash['Top'] = { space_origin_z: footprint_origin.z + typical_story_height * (eff_above.ceil - 1), space_height: typical_story_height, multiplier: 1 }
    else # one story only
      story_hash['Ground'] = { space_origin_z: footprint_origin.z, space_height: typical_story_height, multiplier: 1 }
    end

    # create footprints
    if bar_hash[:bar_division_method] == 'Multiple Space Types - Simple Sliced'
      footprints = []
      story_hash.size.times do |i|
        # adjust size of bar of top story is not a full story
        if i + 1 == story_hash.size
          area_multiplier = (1.0 - bar_hash[:num_stories_above_grade].ceil + bar_hash[:num_stories_above_grade])
          edge_multiplier = Math.sqrt(area_multiplier)
          length = bar_hash[:length] * edge_multiplier
          width = bar_hash[:width] * edge_multiplier
        else
          length = bar_hash[:length]
          width = bar_hash[:width]
        end
        footprints << OsLib_Geometry.make_sliced_bar_simple_polygons(runner, bar_hash[:space_types], length, width, bar_hash[:center_of_footprint])
      end

    elsif bar_hash[:bar_division_method] == 'Multiple Space Types - Individual Stories Sliced'

      # update story_hash for partial_story_above
      story_hash.each_with_index do |(k, v), i|
        # adjust size of bar of top story is not a full story
        if i + 1 == story_hash.size
          story_hash[k][:partial_story_multiplier] = (1.0 - bar_hash[:num_stories_above_grade].ceil + bar_hash[:num_stories_above_grade])
        end
      end

      footprints = OsLib_Geometry.make_sliced_bar_multi_polygons(runner, bar_hash[:space_types], bar_hash[:length], bar_hash[:width], bar_hash[:center_of_footprint], story_hash)

    else
      footprints = []
      story_hash.size.times do |i|
        # adjust size of bar of top story is not a full story
        if i + 1 == story_hash.size
          area_multiplier = (1.0 - bar_hash[:num_stories_above_grade].ceil + bar_hash[:num_stories_above_grade])
          edge_multiplier = Math.sqrt(area_multiplier)
          length = bar_hash[:length] * edge_multiplier
          width = bar_hash[:width] * edge_multiplier
        else
          length = bar_hash[:length]
          width = bar_hash[:width]
        end
        footprints << OsLib_Geometry.make_core_and_perimeter_polygons(runner, length, width, bar_hash[:center_of_footprint]) # perimeter defaults to 15'
      end

      # set primary space type to building default space type
      space_types = bar_hash[:space_types].sort_by { |k, v| v[:floor_area] }
      if space_types.last.first.class.to_s == 'OpenStudio::Model::SpaceType'
        model.getBuilding.setSpaceType(space_types.last.first)
      end

    end

    # makeSpacesFromPolygons
    new_spaces = OsLib_Geometry.makeSpacesFromPolygons(runner, model, footprints, bar_hash[:floor_height], bar_hash[:num_stories], bar_hash[:center_of_footprint], story_hash)

    # put all of the spaces in the model into a vector for intersection and surface matching
    spaces = OpenStudio::Model::SpaceVector.new
    model.getSpaces.sort.each do |space|
      spaces << space
    end

    # flag for intersection and matching type
    diagnostic_intersect = true

    # only intersect if make_mid_story_surfaces_adiabatic false
    if diagnostic_intersect

      model.getPlanarSurfaces.sort.each do |surface|
        array = []
        vertices = surface.vertices
        fixed = false
        vertices.each do |vertex|
          next if fixed
          if array.include?(vertex)
            # create a new set of vertices
            new_vertices = OpenStudio::Point3dVector.new
            array_b = []
            surface.vertices.each do |vertex_b|
              next if array_b.include?(vertex_b)
              new_vertices << vertex_b
              array_b << vertex_b
            end
            surface.setVertices(new_vertices)
            num_removed = vertices.size - surface.vertices.size
            runner.registerWarning("#{surface.name} has duplicate vertices. Started with #{vertices.size} vertices, removed #{num_removed}.")
            fixed = true
          else
            array << vertex
          end
        end
      end

      # remove collinear points in a surface
      model.getPlanarSurfaces.sort.each do |surface|
        new_vertices = OpenStudio.removeCollinear(surface.vertices)
        starting_count = surface.vertices.size
        final_count = new_vertices.size
        if final_count < starting_count
          runner.registerWarning("Removing #{starting_count - final_count} collinear vertices from #{surface.name}.")
          surface.setVertices(new_vertices)
        end
      end

      # remove duplicate surfaces in a space (should be done after remove duplicate and collinear points)
      model.getSpaces.sort.each do |space|
        # secondary array to compare against
        surfaces_b = space.surfaces.sort

        space.surfaces.sort.each do |surface_a|
          # delete from secondary array
          surfaces_b.delete(surface_a)

          surfaces_b.each do |surface_b|
            next if surface_a == surface_b # dont' test against same surface
            if surface_a.equalVertices(surface_b)
              runner.registerWarning("#{surface_a.name} and #{surface_b.name} in #{space.name} have duplicate geometry, removing #{surface_b.name}.")
              surface_b.remove
            elsif surface_a.reverseEqualVertices(surface_b)
              # TODO: - add logic to determine which face naormal is reversed and which is correct
              runner.registerWarning("#{surface_a.name} and #{surface_b.name} in #{space.name} have reversed geometry, removing #{surface_b.name}.")
              surface_b.remove
            end
          end
        end
      end

      if !(bar_hash[:make_mid_story_surfaces_adiabatic])
        # intersect and surface match two pair by pair
        spaces_b = model.getSpaces.sort
        # looping through vector of each space
        model.getSpaces.sort.each do |space_a|
          spaces_b.delete(space_a)
          spaces_b.each do |space_b|
            # runner.registerInfo("Intersecting and matching surfaces between #{space_a.name} and #{space.name}")
            spaces_temp = OpenStudio::Model::SpaceVector.new
            spaces_temp << space_a
            spaces_temp << space_b
            # intersect and sort
            OpenStudio::Model.intersectSurfaces(spaces_temp)
            OpenStudio::Model.matchSurfaces(spaces_temp)
          end
        end
        runner.registerInfo('Intersecting and matching surfaces in model, this will create additional geometry.')
      else # elsif bar_hash[:double_loaded_corridor] # only intersect spaces in each story, not between wtory
        model.getBuilding.buildingStories.sort.each do |story|
          # intersect and surface match two pair by pair
          spaces_b = story.spaces.sort
          # looping through vector of each space
          story.spaces.sort.each do |space_a|
            spaces_b.delete(space_a)
            spaces_b.each do |space_b|
              spaces_temp = OpenStudio::Model::SpaceVector.new
              spaces_temp << space_a
              spaces_temp << space_b
              # intersect and sort
              OpenStudio::Model.intersectSurfaces(spaces_temp)
              OpenStudio::Model.matchSurfaces(spaces_temp)
            end
          end
          runner.registerInfo("Intersecting and matching surfaces in story #{story.name}, this will create additional geometry.")
        end
      end

    else

      if !(bar_hash[:make_mid_story_surfaces_adiabatic])
        # intersect surfaces
        # (when bottom floor has many space types and one above doesn't will end up with heavily subdivided floor. Maybe use adiabatic and don't intersect floor/ceilings)
        intersect_surfaces = true
        if intersect_surfaces
          OpenStudio::Model.intersectSurfaces(spaces)
          OpenStudio::Model.matchSurfaces(spaces)
          runner.registerInfo('Intersecting and matching surfaces in model, this will create additional geometry.')
        end
      else # elsif bar_hash[:double_loaded_corridor] # only intersect spaces in each story, not between wtory
        model.getBuilding.buildingStories.sort.each do |story|
          story_spaces = OpenStudio::Model::SpaceVector.new
          story.spaces.sort.each do |space|
            story_spaces << space
          end
          OpenStudio::Model.intersectSurfaces(story_spaces)
          OpenStudio::Model.matchSurfaces(story_spaces)
          runner.registerInfo("Intersecting and matching surfaces in story #{story.name}, this will create additional geometry.")
        end
      end

    end

    # set boundary conditions if not already set when geometry was created
    # todo - update this to use space original z value vs. story name
    if bar_hash[:num_stories_below_grade] > 0
      model.getBuildingStorys.sort.each do |story|
        next if !story.name.to_s.include?('Story B')
        story.spaces.sort.each do |space|
          next if !new_spaces.include?(space)
          space.surfaces.sort.each do |surface|
            next if surface.surfaceType != 'Wall'
            next if surface.outsideBoundaryCondition != 'Outdoors'
            surface.setOutsideBoundaryCondition('Ground')
          end
        end
      end
    end

    # sort stories (by name for now but need better way)
    sorted_stories = {}
    new_spaces.each do |space|
      next if !space.buildingStory.is_initialized
      story = space.buildingStory.get
      if !sorted_stories.key?(name.to_s)
        sorted_stories[story.name.to_s] = story
      end
    end

    # flag space types that have wwr overrides
    space_type_wwr_overrides = {}

    # loop through building stories, spaces, and surfaces
    sorted_stories.sort.each_with_index do |(key, story), i|
      # flag for adiabatic floor if building doesn't have ground exposed floor
      if stories_flat[i][:bottom_story_ground_exposed_floor] == false
        adiabatic_floor = true
      end
      # flag for adiabatic roof if building doesn't have exterior exposed roof
      if stories_flat[i][:top_story_exterior_exposed_roof] == false
        adiabatic_ceiling = true
      end

      # make all mid story floor and ceilings adiabatic if requested
      if bar_hash[:make_mid_story_surfaces_adiabatic]
        if i > 0
          adiabatic_floor = true
        end
        if i < sorted_stories.size - 1
          adiabatic_ceiling = true
        end
      end

      # flag orientations for this story to recieve party walls
      party_wall_facades = stories_flat[i][:story_party_walls]

      story.spaces.each do |space|
        next if !new_spaces.include?(space)
        space.surfaces. each do |surface|
          # set floor to adiabatic if requited
          if adiabatic_floor && surface.surfaceType == 'Floor'
            make_surfaces_adiabatic([surface])
          elsif adiabatic_ceiling && surface.surfaceType == 'RoofCeiling'
            make_surfaces_adiabatic([surface])
          end

          # skip of not exterior wall
          next if surface.surfaceType != 'Wall'
          next if surface.outsideBoundaryCondition != 'Outdoors'

          # get the absoluteAzimuth for the surface so we can categorize it
          absoluteAzimuth = OpenStudio.convert(surface.azimuth, 'rad', 'deg').get + surface.space.get.directionofRelativeNorth + model.getBuilding.northAxis
          absoluteAzimuth = absoluteAzimuth % 360.0 # should result in value between 0 and 360
          absoluteAzimuth = absoluteAzimuth.round(5) # this was creating issues at 45 deg angles with opposing facades

          # target wwr values that may be changed for specific space types
          wwr_n = bar_hash[:building_wwr_n]
          wwr_e = bar_hash[:building_wwr_e]
          wwr_s = bar_hash[:building_wwr_s]
          wwr_w = bar_hash[:building_wwr_w]

          # look for space type specific wwr values
          if surface.space.is_initialized && surface.space.get.spaceType.is_initialized
            space_type = surface.space.get.spaceType.get

            # see if space type has wwr value
            bar_hash[:space_types].each do |k, v|
              if v.key?(:space_type) && space_type == v[:space_type]

                # if matching space type specifies a wwr then override the orientation specific recommendations for this surface.
                if v.key?(:wwr)
                  wwr_n = v[:wwr]
                  wwr_e = v[:wwr]
                  wwr_s = v[:wwr]
                  wwr_w = v[:wwr]
                  space_type_wwr_overrides[space_type] = v[:wwr]
                end
              end
            end
          end

          # add fenestration (wwr for now, maybe overhang and overhead doors later)
          if (absoluteAzimuth >= 315.0) || (absoluteAzimuth < 45.0)
            if party_wall_facades.include?('north')
              make_surfaces_adiabatic([surface])
            else
              surface.setWindowToWallRatio(wwr_n)
            end
          elsif (absoluteAzimuth >= 45.0) && (absoluteAzimuth < 135.0)
            if party_wall_facades.include?('east')
              make_surfaces_adiabatic([surface])
            else
              surface.setWindowToWallRatio(wwr_e)
            end
          elsif (absoluteAzimuth >= 135.0) && (absoluteAzimuth < 225.0)
            if party_wall_facades.include?('south')
              make_surfaces_adiabatic([surface])
            else
              surface.setWindowToWallRatio(wwr_s)
            end
          elsif (absoluteAzimuth >= 225.0) && (absoluteAzimuth < 315.0)
            if party_wall_facades.include?('west')
              make_surfaces_adiabatic([surface])
            else
              surface.setWindowToWallRatio(wwr_w)
            end
          else
            runner.registerError('Unexpected value of facade: ' + absoluteAzimuth + '.')
            return false
          end
        end
      end
    end

    # report space types with custom wwr values
    space_type_wwr_overrides.each do |space_type, wwr|
      runner.registerInfo("For #{space_type.name} the default building wwr was replaced with a space type specfic value of #{wwr}")
    end

    new_floor_area_si = 0.0
    new_spaces.each do |space|
      new_floor_area_si += space.floorArea * space.multiplier
    end
    new_floor_area_ip = OpenStudio.convert(new_floor_area_si, 'm^2', 'ft^2').get

    final_floor_area_ip = OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get
    if new_floor_area_ip == final_floor_area_ip
      runner.registerInfo("Created bar envelope with floor area of #{OpenStudio.toNeatString(new_floor_area_ip, 0, true)} ft^2.")
    else
      runner.registerInfo("Created bar envelope with floor area of #{OpenStudio.toNeatString(new_floor_area_ip, 0, true)} ft^2. Total building area is #{OpenStudio.toNeatString(final_floor_area_ip, 0, true)} ft^2.")
    end

    return new_spaces
  end

  # make selected surfaces adiabatic
  def make_surfaces_adiabatic(surfaces)
    surfaces.each do |surface|
      if surface.construction.is_initialized
        surface.setConstruction(surface.construction.get)
      end
      surface.setOutsideBoundaryCondition('Adiabatic')
    end
  end

  # get length and width of rectangle matching bounding box aspect ratio will maintaining proper floor area
  def calc_bar_reduced_bounding_box(envelope_data_hash)
    bar = {}

    bounding_length = envelope_data_hash[:building_max_xyz][0] - envelope_data_hash[:building_min_xyz][0]
    bounding_width = envelope_data_hash[:building_max_xyz][1] - envelope_data_hash[:building_min_xyz][1]
    bounding_area = bounding_length * bounding_width
    footprint_area = envelope_data_hash[:building_floor_area] / envelope_data_hash[:effective__num_stories].to_f
    area_multiplier = footprint_area / bounding_area
    edge_multiplier = Math.sqrt(area_multiplier)
    bar[:length] = bounding_length * edge_multiplier
    bar[:width] = bounding_width * edge_multiplier

    return bar
  end

  # get length and width of rectangle matching longer of two edges, and reducing the other way until floor area matches
  def calc_bar_reduced_width(envelope_data_hash)
    bar = {}

    bounding_length = envelope_data_hash[:building_max_xyz][0] - envelope_data_hash[:building_min_xyz][0]
    bounding_width = envelope_data_hash[:building_max_xyz][1] - envelope_data_hash[:building_min_xyz][1]
    footprint_area = envelope_data_hash[:building_floor_area] / envelope_data_hash[:effective__num_stories].to_f

    if bounding_length >= bounding_width
      bar[:length] = bounding_length
      bar[:width] = footprint_area / bounding_length
    else
      bar[:width] = bounding_width
      bar[:length] = footprint_area / bounding_width
    end

    return bar
  end

  # get length and width of rectangle by stretching it until both floor area and exterior wall area or perimeter match
  def calc_bar_stretched(envelope_data_hash)
    bar = {}

    bounding_length = envelope_data_hash[:building_max_xyz][0] - envelope_data_hash[:building_min_xyz][0]
    bounding_width = envelope_data_hash[:building_max_xyz][1] - envelope_data_hash[:building_min_xyz][1]
    a = envelope_data_hash[:building_floor_area] / envelope_data_hash[:effective__num_stories].to_f
    p = envelope_data_hash[:building_perimeter]

    if bounding_length >= bounding_width
      bar[:length] = 0.25 * (p + Math.sqrt(p**2 - 16 * a))
      bar[:width] = 0.25 * (p - Math.sqrt(p**2 - 16 * a))
    else
      bar[:length] = 0.25 * (p - Math.sqrt(p**2 - 16 * a))
      bar[:width] = 0.25 * (p + Math.sqrt(p**2 - 16 * a))
    end

    return bar
  end

  def bar_hash_setup_run(runner, model, args, length, width, floor_height_si, center_of_footprint, space_types_hash, num_stories)
    # create envelope
    # populate bar_hash and create envelope with data from envelope_data_hash and user arguments
    bar_hash = {}
    bar_hash[:length] = length
    bar_hash[:width] = width
    bar_hash[:num_stories_below_grade] = args['num_stories_below_grade']
    bar_hash[:num_stories_above_grade] = args['num_stories_above_grade']
    bar_hash[:floor_height] = floor_height_si
    bar_hash[:center_of_footprint] = center_of_footprint
    bar_hash[:bar_division_method] = args['bar_division_method']
    bar_hash[:make_mid_story_surfaces_adiabatic] = args['make_mid_story_surfaces_adiabatic']
    bar_hash[:space_types] = space_types_hash
    bar_hash[:building_wwr_n] = args['wwr']
    bar_hash[:building_wwr_s] = args['wwr']
    bar_hash[:building_wwr_e] = args['wwr']
    bar_hash[:building_wwr_w] = args['wwr']

    # round up non integer stoires to next integer
    num_stories_round_up = num_stories.ceil
    runner.registerInfo("Making bar with length of #{OpenStudio.toNeatString(OpenStudio.convert(length, 'm', 'ft').get, 0, true)} ft and width of #{OpenStudio.toNeatString(OpenStudio.convert(width, 'm', 'ft').get, 0, true)} ft")

    # party_walls_array to be used by orientation specific or fractional party wall values
    party_walls_array = [] # this is an array of arrays, where each entry is effective building story with array of directions

    if args['party_wall_stories_north'] + args['party_wall_stories_south'] + args['party_wall_stories_east'] + args['party_wall_stories_west'] > 0

      # loop through effective number of stories add orientation specific party walls per user arguments
      num_stories_round_up.times do |i|
        test_value = i + 1 - bar_hash[:num_stories_below_grade]

        array = []
        if args['party_wall_stories_north'] >= test_value
          array << 'north'
        end
        if args['party_wall_stories_south'] >= test_value
          array << 'south'
        end
        if args['party_wall_stories_east'] >= test_value
          array << 'east'
        end
        if args['party_wall_stories_west'] >= test_value
          array << 'west'
        end

        # populate party_wall_array for this story
        party_walls_array << array
      end
    end

    # calculate party walls if using party_wall_fraction method
    if args['party_wall_fraction'] > 0 && !party_walls_array.empty?
      runner.registerWarning('Both orientation and fractional party wall values arguments were populated, will ignore fractional party wall input')
    elsif args['party_wall_fraction'] > 0

      # orientation of long and short side of building will vary based on building rotation

      # full story ext wall area
      typical_length_facade_area = length * floor_height_si
      typical_width_facade_area = width * floor_height_si

      # top story ext wall area, may be partial story
      partial_story_multiplier = (1.0 - args['num_stories_above_grade'].ceil + args['num_stories_above_grade'])
      area_multiplier = partial_story_multiplier
      edge_multiplier = Math.sqrt(area_multiplier)
      top_story_length = length * edge_multiplier
      top_story_width = width * edge_multiplier
      top_story_length_facade_area = top_story_length * floor_height_si
      top_story_width_facade_area = top_story_width * floor_height_si

      total_exterior_wall_area = 2 * (length + width) * (args['num_stories_above_grade'].ceil - 1.0) * floor_height_si + 2 * (top_story_length + top_story_width) * floor_height_si
      target_party_wall_area = total_exterior_wall_area * args['party_wall_fraction']

      width_counter = 0
      width_area = 0.0
      facade_area = typical_width_facade_area
      until (width_area + facade_area >= target_party_wall_area) || (width_counter == args['num_stories_above_grade'].ceil * 2)
        # update facade area for top story
        if width_counter == args['num_stories_above_grade'].ceil - 1 || width_counter == args['num_stories_above_grade'].ceil * 2 - 1
          facade_area = top_story_width_facade_area
        else
          facade_area = typical_width_facade_area
        end

        width_counter += 1
        width_area += facade_area

      end
      width_area_remainder = target_party_wall_area - width_area

      length_counter = 0
      length_area = 0.0
      facade_area = typical_length_facade_area
      until (length_area + facade_area >= target_party_wall_area) || (length_counter == args['num_stories_above_grade'].ceil * 2)
        # update facade area for top story
        if length_counter == args['num_stories_above_grade'].ceil - 1 || length_counter == args['num_stories_above_grade'].ceil * 2 - 1
          facade_area = top_story_length_facade_area
        else
          facade_area = typical_length_facade_area
        end

        length_counter += 1
        length_area += facade_area
      end
      length_area_remainder = target_party_wall_area - length_area

      # get rotation and best fit to adjust orientation for fraction party wall
      rotation = args['building_rotation'] % 360.0 # should result in value between 0 and 360
      card_dir_array = [0.0, 90.0, 180.0, 270.0, 360.0]
      # reverse array to properly handle 45, 135, 225, and 315
      best_fit = card_dir_array.reverse.min_by { |x| (x.to_f - rotation).abs }

      if ![90.0, 270.0].include? best_fit
        width_card_dir = ['east', 'west']
        length_card_dir = ['north', 'south']
      else # if rotation is closest to 90 or 270 then reverse which orientation is used for length and width
        width_card_dir = ['north', 'south']
        length_card_dir = ['east', 'west']
      end

      # if dont' find enough on short sides
      if width_area_remainder <= typical_length_facade_area

        num_stories_round_up.times do |i|
          if i + 1 <= args['num_stories_below_grade']
            party_walls_array << []
            next
          end
          if i + 1 - args['num_stories_below_grade'] <= width_counter
            if i + 1 - args['num_stories_below_grade'] <= width_counter - args['num_stories_above_grade']
              party_walls_array << width_card_dir
            else
              party_walls_array << [width_card_dir.first]
            end
          else
            party_walls_array << []
          end
        end

      else # use long sides instead

        num_stories_round_up.times do |i|
          if i + 1 <= args['num_stories_below_grade']
            party_walls_array << []
            next
          end
          if i + 1 - args['num_stories_below_grade'] <= length_counter
            if i + 1 - args['num_stories_below_grade'] <= length_counter - args['num_stories_above_grade']
              party_walls_array << length_card_dir
            else
              party_walls_array << [length_card_dir.first]
            end
          else
            party_walls_array << []
          end
        end

      end

      # TODO: - currently won't go past making two opposing sets of walls party walls. Info and registerValue are after create_bar in measure.rb

    end

    # populate bar hash with story information
    bar_hash[:stories] = {}
    num_stories_round_up.times do |i|
      if party_walls_array.empty?
        party_walls = []
      else
        party_walls = party_walls_array[i]
      end

      # add below_partial_story
      if num_stories.ceil > num_stories && i == num_stories_round_up - 2
        below_partial_story = true
      else
        below_partial_story = false
      end

      # bottom_story_ground_exposed_floor and top_story_exterior_exposed_roof already setup as bool
      bar_hash[:stories]["key #{i}"] = { story_party_walls: party_walls, story_min_multiplier: 1, story_included_in_building_area: true, below_partial_story: below_partial_story, bottom_story_ground_exposed_floor: args['bottom_story_ground_exposed_floor'], top_story_exterior_exposed_roof: args['top_story_exterior_exposed_roof'] }
    end

    # create bar
    new_spaces = create_bar(runner, model, bar_hash, args['story_multiplier'])

    # check expect roof and wall area
    target_footprint = bar_hash[:length] * bar_hash[:width]
    ground_floor_area = 0.0
    roof_area = 0.0
    new_spaces.each do |space|
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Ground'
          ground_floor_area += surface.netArea
        elsif surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors'
          roof_area += surface.netArea
        end
      end
    end
    # TODO: - extend to address when top and or bottom story are not exposed via argument
    if ground_floor_area > target_footprint + 0.001 || roof_area > target_footprint + 0.001
      # runner.registerError("Ground exposed floor or Roof area is larger than footprint, likely inter-floor surface matching and intersection error.")
      # return false

      # not providing adiabatic work around when top story is partial story.
      if args['num_stories_above_grade'].to_f != args['num_stories_above_grade'].ceil
        runner.registerError('Ground exposed floor or Roof area is larger than footprint, likely inter-floor surface matching and intersection error.')
        return false
      else
        runner.registerInfo('Ground exposed floor or Roof area is larger than footprint, likely inter-floor surface matching and intersection error, altering impacted surfaces boundary condition to be adiabatic.')
        match_error = true
      end
    else
      match_error = false
    end

    # TODO: - should be able to remove this fix after OpenStudio intersection issue is fixed. At that time turn the above message into an error with return false after it
    if match_error

      # identify z value of top and bottom story
      bottom_story = nil
      top_story = nil
      new_spaces.each do |space|
        story = space.buildingStory.get
        nom_z = story.nominalZCoordinate.get
        if bottom_story.nil?
          bottom_story = nom_z
        elsif bottom_story > nom_z
          bottom_story = nom_z
        end
        if top_story.nil?
          top_story = nom_z
        elsif top_story < nom_z
          top_story = nom_z
        end
      end

      # change boundary condition and intersection as needed.
      new_spaces.each do |space|
        if space.buildingStory.get.nominalZCoordinate.get > bottom_story
          # change floors
          space.surfaces.each do |surface|
            next if !(surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Ground')
            surface.setOutsideBoundaryCondition('Adiabatic')
          end
        end
        if space.buildingStory.get.nominalZCoordinate.get < top_story
          # change ceilings
          space.surfaces.each do |surface|
            next if !(surface.surfaceType == 'RoofCeiling' && surface.outsideBoundaryCondition == 'Outdoors')
            surface.setOutsideBoundaryCondition('Adiabatic')
          end
        end
      end
    end
  end

  # bar_from_building_type_ratios
  # used for varieties of measures that create bar from building type ratios
  def bar_from_building_type_ratios(model, runner, user_arguments)
    # assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments(model))
    if !args then return false end

    # add in arguments that may not be passed in
    if !args.key?('double_loaded_corridor')
      args['double_loaded_corridor'] = 'None' # use None when not in measure building type data may not contain this
    end
    if !args.key?('perim_mult')
      args['perim_mult'] = 1.0 # will not make two bars for extended perimeter
    end

    # lookup and replace argument values from upstream measures
    if args['use_upstream_args'] == true
      args.each do |arg, value|
        next if arg == 'use_upstream_args' # this argument should not be changed
        value_from_osw = OsLib_HelperMethods.check_upstream_measure_for_arg(runner, arg)
        if !value_from_osw.empty?
          runner.registerInfo("Replacing argument named #{arg} from current measure with a value of #{value_from_osw[:value]} from #{value_from_osw[:measure_name]}.")
          new_val = value_from_osw[:value]
          # TODO: - make code to handle non strings more robust. check_upstream_measure_for_arg could pass back the argument type
          if arg == 'total_bldg_floor_area'
            args[arg] = new_val.to_f
          elsif arg == 'num_stories_above_grade'
            args[arg] = new_val.to_f
          elsif arg == 'zipcode'
            args[arg] = new_val.to_i
          else
            args[arg] = new_val
          end
        end
      end
    end

    # check expected values of double arguments
    fraction_args = ['bldg_type_b_fract_bldg_area',
                     'bldg_type_c_fract_bldg_area',
                     'bldg_type_d_fract_bldg_area',
                     'wwr', 'party_wall_fraction']
    fraction = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => 1.0, 'min_eq_bool' => true, 'max_eq_bool' => true, 'arg_array' => fraction_args)

    positive_args = ['total_bldg_floor_area']
    positive = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => nil, 'min_eq_bool' => false, 'max_eq_bool' => false, 'arg_array' => positive_args)

    one_or_greater_args = ['num_stories_above_grade']
    one_or_greater = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 1.0, 'max' => nil, 'min_eq_bool' => true, 'max_eq_bool' => false, 'arg_array' => one_or_greater_args)

    non_neg_args = ['num_stories_below_grade',
                    'floor_height',
                    'ns_to_ew_ratio',
                    'party_wall_stories_north',
                    'party_wall_stories_south',
                    'party_wall_stories_east',
                    'party_wall_stories_west',
                    'single_floor_area',
                    'bar_width']
    non_neg = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => nil, 'min_eq_bool' => true, 'max_eq_bool' => false, 'arg_array' => non_neg_args)

    # return false if any errors fail
    if !fraction then return false end
    if !positive then return false end
    if !one_or_greater then return false end
    if !non_neg then return false end

    # if aspect ratio, story height or wwr have argument value of 0 then use smart building type defaults
    building_form_defaults = building_form_defaults(args['bldg_type_a'])

    # store list of defaulted items
    defaulted_args = []

    if args['ns_to_ew_ratio'] == 0.0
      args['ns_to_ew_ratio'] = building_form_defaults[:aspect_ratio]
      runner.registerInfo("0.0 value for aspect ratio will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:aspect_ratio]}.")
    end

    if args['perim_mult'] == 0.0
      # if this is not defined then use default of 1.0
      if !building_form_defaults.key?(:perim_mult)
        args['perim_mult'] = 1.0
      else
        args['perim_mult'] = building_form_defaults[:perim_mult]
      end
      runner.registerInfo("0.0 value for minimum perimeter multiplier will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:perim_mult]}.")
    elsif args['perim_mult'] < 1.0
      runner.registerError('Other than the smart default value of 0, the minimum perimeter multiplier should be equal to 1.0 or greater.')
      return false
    end

    if args['floor_height'] == 0.0
      args['floor_height'] = building_form_defaults[:typical_story]
      runner.registerInfo("0.0 value for floor height will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:typical_story]}.")
      defaulted_args << 'floor_height'
    end
    # because of this can't set wwr to 0.0. If that is desired then we can change this to check for 1.0 instead of 0.0
    if args['wwr'] == 0.0
      args['wwr'] = building_form_defaults[:wwr]
      runner.registerInfo("0.0 value for window to wall ratio will be replaced with smart default for #{args['bldg_type_a']} of #{building_form_defaults[:wwr]}.")
    end

    # check that sum of fractions for b,c, and d is less than 1.0 (so something is left for primary building type)
    bldg_type_a_fract_bldg_area = 1.0 - args['bldg_type_b_fract_bldg_area'] - args['bldg_type_c_fract_bldg_area'] - args['bldg_type_d_fract_bldg_area']
    if bldg_type_a_fract_bldg_area <= 0.0
      runner.registerError('Primary Building Type fraction of floor area must be greater than 0. Please lower one or more of the fractions for Building Type B-D.')
      return false
    end

    # Make the standard applier
    standard = Standard.build((args['template']).to_s)

    # report initial condition of model
    runner.registerInitialCondition("The building started with #{model.getSpaces.size} spaces.")

    # determine of ns_ew needs to be mirrored
    mirror_ns_ew = false
    rotation = model.getBuilding.northAxis
    if rotation > 45.0 && rotation < 135.0
      mirror_ns_ew = true
    elsif rotation > 45.0 && rotation < 135.0
      mirror_ns_ew = true
    end

    # remove non-resource objects not removed by removing the building
    remove_non_resource_objects(runner, model)

    # rename building to infer template in downstream measure
    name_array = [args['template'], args['bldg_type_a']]
    if args['bldg_type_b_fract_bldg_area'] > 0 then name_array << args['bldg_type_b'] end
    if args['bldg_type_c_fract_bldg_area'] > 0 then name_array << args['bldg_type_c'] end
    if args['bldg_type_d_fract_bldg_area'] > 0 then name_array << args['bldg_type_d'] end
    model.getBuilding.setName(name_array.join('|').to_s)

    # hash to whole building type data
    building_type_hash = {}

    # gather data for bldg_type_a
    building_type_hash[args['bldg_type_a']] = {}
    building_type_hash[args['bldg_type_a']][:frac_bldg_area] = bldg_type_a_fract_bldg_area
    # building_type_hash[args['bldg_type_a']][:num_units] = args['bldg_type_a_num_units']
    building_type_hash[args['bldg_type_a']][:space_types] = get_space_types_from_building_type(args['bldg_type_a'], args['template'], true)

    # gather data for bldg_type_b
    if args['bldg_type_b_fract_bldg_area'] > 0
      building_type_hash[args['bldg_type_b']] = {}
      building_type_hash[args['bldg_type_b']][:frac_bldg_area] = args['bldg_type_b_fract_bldg_area']
      # building_type_hash[args['bldg_type_b']][:num_units] = args['bldg_type_b_num_units']
      building_type_hash[args['bldg_type_b']][:space_types] = get_space_types_from_building_type(args['bldg_type_b'], args['template'], true)
    end

    # gather data for bldg_type_c
    if args['bldg_type_c_fract_bldg_area'] > 0
      building_type_hash[args['bldg_type_c']] = {}
      building_type_hash[args['bldg_type_c']][:frac_bldg_area] = args['bldg_type_c_fract_bldg_area']
      # building_type_hash[args['bldg_type_c']][:num_units] = args['bldg_type_c_num_units']
      building_type_hash[args['bldg_type_c']][:space_types] = get_space_types_from_building_type(args['bldg_type_c'], args['template'], true)
    end

    # gather data for bldg_type_d
    if args['bldg_type_d_fract_bldg_area'] > 0
      building_type_hash[args['bldg_type_d']] = {}
      building_type_hash[args['bldg_type_d']][:frac_bldg_area] = args['bldg_type_d_fract_bldg_area']
      # building_type_hash[args['bldg_type_d']][:num_units] = args['bldg_type_d_num_units']
      building_type_hash[args['bldg_type_d']][:space_types] = get_space_types_from_building_type(args['bldg_type_d'], args['template'], true)
    end

    # creating space types for requested building types
    building_type_hash.each do |building_type, building_type_hash|
      runner.registerInfo("Creating Space Types for #{building_type}.")

      # mapping building_type name is needed for a few methods
      building_type = standard.model_get_lookup_name(building_type)

      # create space_type_map from array
      sum_of_ratios = 0.0
      building_type_hash[:space_types] = building_type_hash[:space_types].sort_by { |k, v| v[:ratio] }.to_h
      building_type_hash[:space_types].each do |space_type_name, hash|
        next if hash[:space_type_gen] == false # space types like undeveloped and basement are skipped.

        # create space type
        space_type = OpenStudio::Model::SpaceType.new(model)
        space_type.setStandardsBuildingType(building_type)
        space_type.setStandardsSpaceType(space_type_name)
        space_type.setName("#{building_type} #{space_type_name}")

        # set color
        test = standard.space_type_apply_rendering_color(space_type) # this uses openstudio-standards
        if !test
          # TODO: - once fixed in standards un-comment this
          # runner.registerWarning("Could not find color for #{args['template']} #{space_type.name}")
        end

        # extend hash to hold new space type object
        hash[:space_type] = space_type

        # add to sum_of_ratios counter for adjustment multiplier
        sum_of_ratios += hash[:ratio]
      end

      # store multiplier needed to adjust sum of ratios to equal 1.0
      building_type_hash[:ratio_adjustment_multiplier] = 1.0 / sum_of_ratios
    end

    # calculate length and with of bar
    total_bldg_floor_area_si = OpenStudio.convert(args['total_bldg_floor_area'], 'ft^2', 'm^2').get
    single_floor_area_si = OpenStudio.convert(args['single_floor_area'], 'ft^2', 'm^2').get

    # store number of stories
    num_stories = args['num_stories_below_grade'] + args['num_stories_above_grade']

    # handle user-assigned single floor plate size condition
    if args['single_floor_area'] > 0.0
      footprint_si = single_floor_area_si
      total_bldg_floor_area_si = footprint_si * num_stories.to_f
      runner.registerWarning('User-defined single floor area was used for calculation of total building floor area')
      # add warning if custom_height_bar is true and applicable building type is selected
      if args['custom_height_bar']
        runner.registerWarning('Cannot use custom height bar with single floor area method, will not create custom height bar.')
        args['custom_height_bar'] = false
      end
    else
      footprint_si = nil
    end

    # populate space_types_hash
    space_types_hash = {}
    multi_height_space_types_hash = {}
    custom_story_heights = []
    if args['space_type_sort_logic'] == 'Building Type > Size'
      building_type_hash = building_type_hash.sort_by { |k, v| v[:frac_bldg_area] }
    end
    building_type_hash.each do |building_type, building_type_hash|
      if args['double_loaded_corridor'] == 'Primary Space Type'

        # see if building type has circulation space type, if so then merge that along with default space type into hash key in place of space type
        default_st = nil
        circ_st = nil
        building_type_hash[:space_types].each do |space_type_name, hash|
          if hash[:default] then default_st = space_type_name end
          if hash[:circ] then circ_st = space_type_name end
        end

        # update building hash
        if !default_st.nil? && !circ_st.nil?
          runner.registerInfo("Combining #{default_st} and #{circ_st} into a group representing a double loaded corridor")

          # add new item
          building_type_hash[:space_types]['Double Loaded Corridor'] = {}
          double_loaded_st = building_type_hash[:space_types]['Double Loaded Corridor']
          double_loaded_st[:ratio] = building_type_hash[:space_types][default_st][:ratio] + building_type_hash[:space_types][circ_st][:ratio]
          double_loaded_st[:double_loaded_corridor] = true
          double_loaded_st[:space_type] = model.getBuilding
          double_loaded_st[:children] = {}
          building_type_hash[:space_types][default_st][:orig_ratio] = building_type_hash[:ratio_adjustment_multiplier] * building_type_hash[:frac_bldg_area] * building_type_hash[:space_types][default_st][:ratio]
          building_type_hash[:space_types][circ_st][:orig_ratio] = building_type_hash[:ratio_adjustment_multiplier] * building_type_hash[:frac_bldg_area] * building_type_hash[:space_types][circ_st][:ratio]
          building_type_hash[:space_types][default_st][:name] = default_st
          building_type_hash[:space_types][circ_st][:name] = circ_st
          double_loaded_st[:children][:default] = building_type_hash[:space_types][default_st]
          double_loaded_st[:children][:circ] = building_type_hash[:space_types][circ_st]
          double_loaded_st[:orig_ratio] = 0.0

          # zero out ratios from old item (don't delete because I still want the space types made)
          building_type_hash[:space_types][default_st][:ratio] = 0.0
          building_type_hash[:space_types][circ_st][:ratio] = 0.0
        end
      end

      building_type_hash[:space_types].each do |space_type_name, hash|
        next if hash[:space_type_gen] == false

        space_type = hash[:space_type]
        ratio_of_bldg_total = hash[:ratio] * building_type_hash[:ratio_adjustment_multiplier] * building_type_hash[:frac_bldg_area]
        final_floor_area = ratio_of_bldg_total * total_bldg_floor_area_si # I think I can just pass ratio but passing in area is cleaner

        # only add custom height space if 0 is used for floor_height
        if defaulted_args.include?('floor_height') && hash.key?(:story_height) && args['custom_height_bar']
          multi_height_space_types_hash[space_type] = { floor_area: final_floor_area, space_type: space_type, story_height: hash[:story_height] }
          if hash.key?(:orig_ratio) then multi_height_space_types_hash[space_type][:orig_ratio] = hash[:orig_ratio] end
          custom_story_heights << hash[:story_height]
          if args['wwr'] == 0 && hash.key?(:wwr)
            multi_height_space_types_hash[space_type][:wwr] = hash[:wwr]
          end
        else
          # only add wwr if 0 used for wwr arg and if space type has wwr as key
          space_types_hash[space_type] = { floor_area: final_floor_area, space_type: space_type }
          if hash.key?(:orig_ratio) then space_types_hash[space_type][:orig_ratio] = hash[:orig_ratio] end
          if args['wwr'] == 0 && hash.key?(:wwr)
            space_types_hash[space_type][:wwr] = hash[:wwr]
          end
          if hash[:double_loaded_corridor]
            space_types_hash[space_type][:children] = hash[:children]
          end
        end
      end
    end

    # resort if not sorted by building type
    if args['space_type_sort_logic'] == 'Size'
      # added code to convert to hash. I use sort_by 3 other times, but those seem to be working fine as is now.
      space_types_hash = Hash[space_types_hash.sort_by { |k, v| v[:floor_area] }]
    end

    # calculate targets for testing
    target_areas = {} # used for checks
    target_areas_cust_height = 0.0
    space_types_hash.each do |k, v|
      if v.key?(:orig_ratio)
        target_areas[k] = v[:orig_ratio] * total_bldg_floor_area_si
      else
        target_areas[k] = v[:floor_area]
      end
    end
    multi_height_space_types_hash.each do |k, v|
      if v.key?(:orig_ratio)
        target_areas[k] = v[:orig_ratio] * total_bldg_floor_area_si
        target_areas_cust_height += v[:orig_ratio] * total_bldg_floor_area_si
      else
        target_areas[k] = v[:floor_area]
        target_areas_cust_height += v[:floor_area]
      end
    end

    # gather inputs
    if footprint_si.nil?
      footprint_si = (total_bldg_floor_area_si - target_areas_cust_height) / num_stories.to_f
    end
    floor_height_si = OpenStudio.convert(args['floor_height'], 'ft', 'm').get
    min_allow_size = OpenStudio.convert(15.0, 'ft', 'm').get
    specified_bar_width_si = OpenStudio.convert(args['bar_width'], 'ft', 'm').get

    # set custom width
    if specified_bar_width_si > 0
      runner.registerInfo('Ignoring perimeter multiplier argument when non zero width argument is used')
      if footprint_si / specified_bar_width_si >= min_allow_size
        width = specified_bar_width_si
        length = footprint_si / width
      else
        length = min_allow_size
        width = footprint_si / length
        runner.registerWarning('User specified width results in a length that is too short, adjusting width to be narrower than specified.')
      end
      width_cust_height = specified_bar_width_si
    else
      width = Math.sqrt(footprint_si / args['ns_to_ew_ratio'])
      length = footprint_si / width
      width_cust_height = Math.sqrt(target_areas_cust_height / args['ns_to_ew_ratio'])
    end
    length_cust_height = target_areas_cust_height / width_cust_height
    if args['perim_mult'] > 1.0 && target_areas_cust_height > 0.0
      # TODO: - update tests that hit this warning
      runner.registerWarning('Ignoring perimeter multiplier for bar that represents custom height spaces.')
    end

    # check if dual bar is needed
    dual_bar = false
    if specified_bar_width_si > 0.0 && args['bar_division_method'] == 'Multiple Space Types - Individual Stories Sliced'
      if length / width != args['ns_to_ew_ratio']

        if args['ns_to_ew_ratio'] >= 1.0 && args['ns_to_ew_ratio'] > length / width
          runner.registerWarning("Can't meet target aspect ratio of #{args['ns_to_ew_ratio']}, Lowering it to #{length / width} ")
          args['ns_to_ew_ratio'] = length / width
        elsif args['ns_to_ew_ratio'] < 1.0 && args['ns_to_ew_ratio'] > length / width
          runner.registerWarning("Can't meet target aspect ratio of #{args['ns_to_ew_ratio']}, Increasing it to #{length / width} ")
          args['ns_to_ew_ratio'] = length / width
        else
          # check if each bar would be longer then 15 feet, then set as dual bar and override perimeter multiplier
          length_alt1 = ((args['ns_to_ew_ratio'] * footprint_si) / width + 2 * args['ns_to_ew_ratio'] * width - 2 * width) / (1 + args['ns_to_ew_ratio'])
          length_alt2 = length - length_alt1
          if [length_alt1, length_alt2].min >= min_allow_size
            dual_bar = true
          else
            runner.registerInfo('Second bar would be below minimum length, will model as single bar')
            # swap length and width if single bar and aspect ratio less than 1
            if args['ns_to_ew_ratio'] < 1.0
              width = length
              length = specified_bar_width_si
            end
          end
        end
      end
    elsif args['perim_mult'] > 1.0 && args['bar_division_method'] == 'Multiple Space Types - Individual Stories Sliced'
      runner.registerInfo('You selected a perimeter multiplier greater than 1.0 for a supported bar division method. This will result in two detached rectangular buildings if secondary bar meets minimum size requirements.')
      dual_bar = true
    elsif args['perim_mult'] > 1.0
      runner.registerWarning("You selected a perimeter multiplier greater than 1.0 but didn't select a bar division method that supports this. The value for this argument will be ignored by the measure")
    end

    # calculations for dual bar, which later will be setup to run create_bar twice
    if dual_bar
      min_perim = 2 * width + 2 * length
      target_area = footprint_si
      target_perim = min_perim * args['perim_mult']
      tol_testing = 0.00001
      dual_bar_calc_approach = nil # stretched, adiabatic_ends_bar_b, dual_bar
      runner.registerInfo("Minimum rectangle is #{OpenStudio.toNeatString(OpenStudio.convert(length, 'm', 'ft').get, 0, true)} ft x #{OpenStudio.toNeatString(OpenStudio.convert(width, 'm', 'ft').get, 0, true)} ft with an area of #{OpenStudio.toNeatString(OpenStudio.convert(length * width, 'm^2', 'ft^2').get, 0, true)} ft^2. Perimeter is #{OpenStudio.toNeatString(OpenStudio.convert(min_perim, 'm', 'ft').get, 0, true)} ft.")
      runner.registerInfo("Target dual bar perimeter is #{OpenStudio.toNeatString(OpenStudio.convert(target_perim, 'm', 'ft').get, 0, true)} ft.")

      # determine which of the three paths to hit target perimeter multiplier are possible
      # A use dual bar non adiabatic
      # B use dual bar adiabatic
      # C use stretched bar (requires model to miss ns/ew ratio)

      # custom quadratic equation to solve two bars with common width 2l^2 - p*l + 4a = 0
      if target_perim**2 - 32 * footprint_si > 0
        if specified_bar_width_si > 0
          runner.registerInfo('Ignoring perimeter multiplier argument and using use specified bar width.')
          dual_double_end_width = specified_bar_width_si
          dual_double_end_length = footprint_si / dual_double_end_width
        else
          dual_double_end_length = 0.25 * (target_perim + Math.sqrt(target_perim**2 - 32 * footprint_si))
          dual_double_end_width = footprint_si / dual_double_end_length
        end

        # now that stretched  bar is made, determine where to split it and rotate
        bar_a_length = (args['ns_to_ew_ratio'] * (dual_double_end_length + dual_double_end_width) - dual_double_end_width) / (1 + args['ns_to_ew_ratio'])
        bar_b_length = dual_double_end_length - bar_a_length
        area_a = bar_a_length * dual_double_end_width
        area_b = bar_b_length * dual_double_end_width
      else
        # this will throw it to adiabatic ends test
        bar_a_length = 0
        bar_b_length = 0
      end

      if bar_a_length >= min_allow_size && bar_b_length >= min_allow_size
        dual_bar_calc_approach = 'dual_bar'
      else
        # adiabatic bar input calcs
        if target_perim**2 - 16 * footprint_si > 0
          adiabatic_dual_double_end_length = 0.25 * (target_perim + Math.sqrt(target_perim**2 - 16 * footprint_si))
          adiabatic_dual_double_end_width = footprint_si / adiabatic_dual_double_end_length
          # test for unexpected
          unexpected = false
          if (target_area - adiabatic_dual_double_end_length * adiabatic_dual_double_end_width).abs > tol_testing then unexpected = true end
          if specified_bar_width_si == 0
            if (target_perim - (adiabatic_dual_double_end_length * 2 + adiabatic_dual_double_end_width * 2)).abs > tol_testing then unexpected = true end
          end
          if unexpected
            runner.registerWarning('Unexpected values for dual rectangle adiabatic ends bar b.')
          end
          # now that stretched  bar is made, determine where to split it and rotate
          adiabatic_bar_a_length = (args['ns_to_ew_ratio'] * (adiabatic_dual_double_end_length + adiabatic_dual_double_end_width)) / (1 + args['ns_to_ew_ratio'])
          adiabatic_bar_b_length = adiabatic_dual_double_end_length - adiabatic_bar_a_length
          adiabatic_area_a = adiabatic_bar_a_length * adiabatic_dual_double_end_width
          adiabatic_area_b = adiabatic_bar_b_length * adiabatic_dual_double_end_width
        else
          # this will throw it stretched single bar
          adiabatic_bar_a_length = 0
          adiabatic_bar_b_length = 0
        end
        if adiabatic_bar_a_length >= min_allow_size && adiabatic_bar_b_length >= min_allow_size
          dual_bar_calc_approach = 'adiabatic_ends_bar_b'
        else
          dual_bar_calc_approach = 'stretched'
        end
      end

      # apply prescribed approach for stretched or dual bar
      if dual_bar_calc_approach == 'dual_bar'
        runner.registerInfo("Stretched  #{OpenStudio.toNeatString(OpenStudio.convert(dual_double_end_length, 'm', 'ft').get, 0, true)} ft x #{OpenStudio.toNeatString(OpenStudio.convert(dual_double_end_width, 'm', 'ft').get, 0, true)} ft rectangle has an area of #{OpenStudio.toNeatString(OpenStudio.convert(dual_double_end_length * dual_double_end_width, 'm^2', 'ft^2').get, 0, true)} ft^2. When split in two the perimeter will be #{OpenStudio.toNeatString(OpenStudio.convert(dual_double_end_length * 2 + dual_double_end_width * 4, 'm', 'ft').get, 0, true)} ft")
        if (target_area - dual_double_end_length * dual_double_end_width).abs > tol_testing || (target_perim - (dual_double_end_length * 2 + dual_double_end_width * 4)).abs > tol_testing
          runner.registerWarning('Unexpected values for dual rectangle.')
        end

        runner.registerInfo("For stretched split bar, to match target ns/ew aspect ratio #{OpenStudio.toNeatString(OpenStudio.convert(bar_a_length, 'm', 'ft').get, 0, true)} ft of bar should be horizontal, with #{OpenStudio.toNeatString(OpenStudio.convert(bar_b_length, 'm', 'ft').get, 0, true)} ft turned 90 degrees. Combined area is #{OpenStudio.toNeatString(OpenStudio.convert(area_a + area_b, 'm^2', 'ft^2').get, 0, true)} ft^2. Combined perimeter is #{OpenStudio.toNeatString(OpenStudio.convert(bar_a_length * 2 + bar_b_length * 2 + dual_double_end_width * 4, 'm', 'ft').get, 0, true)} ft")
        if (target_area - (area_a + area_b)).abs > tol_testing || (target_perim - (bar_a_length * 2 + bar_b_length * 2 + dual_double_end_width * 4)).abs > tol_testing
          runner.registerWarning('Unexpected values for rotated dual rectangle')
        end
      elsif dual_bar_calc_approach == 'adiabatic_ends_bar_b'
        runner.registerInfo("Can't hit target perimeter with two rectangles, need to make two ends adiabatic")

        runner.registerInfo("For dual bar with adiabatic ends on bar b, to reach target aspect ratio #{OpenStudio.toNeatString(OpenStudio.convert(adiabatic_bar_a_length, 'm', 'ft').get, 0, true)} ft of bar should be north/south, with #{OpenStudio.toNeatString(OpenStudio.convert(adiabatic_bar_b_length, 'm', 'ft').get, 0, true)} ft turned 90 degrees. Combined area is #{OpenStudio.toNeatString(OpenStudio.convert(adiabatic_area_a + adiabatic_area_b, 'm^2', 'ft^2').get, 0, true)} ft^2}. Combined perimeter is #{OpenStudio.toNeatString(OpenStudio.convert(adiabatic_bar_a_length * 2 + adiabatic_bar_b_length * 2 + adiabatic_dual_double_end_width * 2, 'm', 'ft').get, 0, true)} ft")
        if (target_area - (adiabatic_area_a + adiabatic_area_b)).abs > tol_testing || (target_perim - (adiabatic_bar_a_length * 2 + adiabatic_bar_b_length * 2 + adiabatic_dual_double_end_width * 2)).abs > tol_testing
          runner.registerWarning('Unexpected values for rotated dual rectangle adiabatic ends bar b')
        end
      else # stretched bar
        dual_bar = false

        stretched_length = 0.25 * (target_perim + Math.sqrt(target_perim**2 - 16 * footprint_si))
        stretched_width = footprint_si / stretched_length
        if (target_area - stretched_length * stretched_width).abs > tol_testing || (target_perim - (stretched_length + stretched_width) * 2) > tol_testing
          runner.registerWarning('Unexpected values for single stretched')
        end

        width = stretched_width
        length = stretched_length
        runner.registerInfo("Creating a dual bar to match the target minimum perimeter multiplier at the given aspect ratio would result in a bar with edge shorter than #{OpenStudio.toNeatString(OpenStudio.convert(min_allow_size, 'm', 'ft').get, 0, true)} ft. Will create a single stretched bar instead that hits the target perimeter with a slightly different ns/ew aspect ratio.")
      end
    end

    bars = {}
    bars['primary'] = {}
    if dual_bar
      if mirror_ns_ew && dual_bar_calc_approach == 'dual_bar'
        bars['primary'][:length] = dual_double_end_width
        bars['primary'][:width] = bar_a_length
      elsif dual_bar_calc_approach == 'dual_bar'
        bars['primary'][:length] = bar_a_length
        bars['primary'][:width] = dual_double_end_width
      elsif mirror_ns_ew
        bars['primary'][:length] = adiabatic_dual_double_end_width
        bars['primary'][:width] = adiabatic_bar_a_length
      else
        bars['primary'][:length] = adiabatic_bar_a_length
        bars['primary'][:width] = adiabatic_dual_double_end_width
      end
    else
      if mirror_ns_ew
        bars['primary'][:length] = width
        bars['primary'][:width] = length
      else
        bars['primary'][:length] = length
        bars['primary'][:width] = width
      end
    end
    bars['primary'][:floor_height_si] = floor_height_si # can make use of this when breaking out multi-height spaces
    bars['primary'][:num_stories] = num_stories
    bars['primary'][:center_of_footprint] = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    space_types_hash_secondary = {}
    if dual_bar
      # loop through each story and move portion for other bar to its own hash
      primary_footprint = bars['primary'][:length] * bars['primary'][:width]
      secondary_footprint = target_area - primary_footprint
      footprint_counter = primary_footprint
      secondary_footprint_counter = secondary_footprint
      story_counter = 0
      pri_sec_tol = 0.0001 # m^2
      pri_sec_min_area = 0.0001 # m^2
      space_types_hash.each do |k, v|
        space_type_left = v[:floor_area]

        # do not go to next space type until this one is evaulate, which may span stories
        until space_type_left == 0.0 || story_counter >= num_stories

          # use secondary footprint if any left
          if secondary_footprint_counter > 0.0
            hash_area = [space_type_left, secondary_footprint_counter].min

            # confirm that the part of space type use or what is left is greater than min allowed value
            projected_space_type_left = space_type_left - hash_area
            test_a = hash_area >= pri_sec_min_area
            test_b = projected_space_type_left >= pri_sec_min_area || projected_space_type_left == 0.0 ? true : false
            test_c = k == space_types_hash.keys.last # if last space type accept sliver, no other space to infil
            if (test_a && test_b) || test_c
              if space_types_hash_secondary.key?(k)
                # add to what was added for previous story
                space_types_hash_secondary[k][:floor_area] += hash_area
              else
                # add new space type to hash
                if v.key?(:children)
                  space_types_hash_secondary[k] = { floor_area: hash_area, space_type: v[:space_type], children: v[:children] }
                else
                  space_types_hash_secondary[k] = { floor_area: hash_area, space_type: v[:space_type] }
                end
              end
              space_types_hash[k][:floor_area] -= hash_area
              secondary_footprint_counter -= hash_area
              space_type_left -= hash_area
            else
              runner.registerInfo("Shifting space types between bars to avoid sliver of #{k.name}.")
            end
          end

          # remove space if entirely used up by secondary bar
          if space_types_hash[k][:floor_area] <= pri_sec_tol
            space_types_hash.delete(k)
            space_type_left = 0.0
          else
            # then look at primary bar
            hash_area_pri = [space_type_left, footprint_counter].min
            footprint_counter -= hash_area_pri
            space_type_left -= hash_area_pri
          end

          # reset counter when full
          if footprint_counter <= pri_sec_tol && secondary_footprint_counter <= pri_sec_tol
            # check if this is partial top floor
            story_counter += 1
            if num_stories < story_counter + 1
              footprint_counter = primary_footprint * (num_stories - story_counter)
              secondary_footprint_counter = secondary_footprint * (num_stories - story_counter)
            else
              footprint_counter = primary_footprint
              secondary_footprint_counter = secondary_footprint
            end
          end
        end
      end
    end

    # setup bar_hash and run create_bar
    bars['primary'][:space_types_hash] = space_types_hash
    bars['primary'][:args] = args
    v = bars['primary']
    bar_hash_setup_run(runner, model, v[:args], v[:length], v[:width], v[:floor_height_si], v[:center_of_footprint], v[:space_types_hash], v[:num_stories])

    # store offset value for multiple bars
    if args.key?('bar_sep_dist_mult') && args['bar_sep_dist_mult'] > 0.0
      offset_val = num_stories.ceil * floor_height_si * args['bar_sep_dist_mult']
    elsif args.key?('bar_sep_dist_mult')
      runner.registerWarning('Positive value is required for bar_sep_dist_mult, ignoring input and using value of 0.1')
      offset_val = num_stories.ceil * floor_height_si * 0.1
    else
      offset_val = num_stories.ceil * floor_height_si * 10.0
    end

    if dual_bar
      args2 = args.clone
      bars['secondary'] = {}
      if mirror_ns_ew && dual_bar_calc_approach == 'dual_bar'
        bars['secondary'][:length] = bar_b_length
        bars['secondary'][:width] = dual_double_end_width
      elsif dual_bar_calc_approach == 'dual_bar'
        bars['secondary'][:length] = dual_double_end_width
        bars['secondary'][:width] = bar_b_length
      elsif mirror_ns_ew
        bars['secondary'][:length] = adiabatic_bar_b_length
        bars['secondary'][:width] = adiabatic_dual_double_end_width
        args2['party_wall_stories_east'] = num_stories.ceil
        args2['party_wall_stories_west'] = num_stories.ceil
      else
        bars['secondary'][:length] = adiabatic_dual_double_end_width
        bars['secondary'][:width] = adiabatic_bar_b_length
        args2['party_wall_stories_south'] = num_stories.ceil
        args2['party_wall_stories_north'] = num_stories.ceil
      end
      bars['secondary'][:floor_height_si] = floor_height_si # can make use of this when breaking out multi-height spaces
      bars['secondary'][:num_stories] = num_stories
      bars['secondary'][:space_types_hash] = space_types_hash_secondary
      if dual_bar_calc_approach == 'adiabatic_ends_bar_b'
        # warn that combination of dual bar with low perimeter multiplier and use of party wall may result in discrepency between target and actual adiabatic walls
        if args['party_wall_fraction'] > 0 || args['party_wall_stories_north'] > 0 || args['party_wall_stories_south'] > 0 || args['party_wall_stories_east'] > 0 || args['party_wall_stories_west'] > 0
          runner.registerWarning('The combination of low perimeter multiplier and use of non zero party wall inputs may result in discrepency between target and actual adiabatic walls. This is due to the need to create adiabatic walls on secondary bar to maintian target building perimeter.')
        else
          runner.registerInfo('Adiabatic ends added to secondary bar because target perimeter multiplier could not be met with two full rectangular footprints.')
        end
        bars['secondary'][:center_of_footprint] = OpenStudio::Point3d.new(adiabatic_bar_a_length * 0.5 + adiabatic_dual_double_end_width * 0.5 + offset_val, adiabatic_bar_b_length * 0.5 + adiabatic_dual_double_end_width * 0.5 + offset_val, 0.0)
      else
        bars['secondary'][:center_of_footprint] = OpenStudio::Point3d.new(bar_a_length * 0.5 + dual_double_end_width * 0.5 + offset_val, bar_b_length * 0.5 + dual_double_end_width * 0.5 + offset_val, 0.0)
      end
      bars['secondary'][:args] = args2

      # setup bar_hash and run create_bar
      v = bars['secondary']
      bar_hash_setup_run(runner, model, v[:args], v[:length], v[:width], v[:floor_height_si], v[:center_of_footprint], v[:space_types_hash], v[:num_stories])

    end

    # future development (up against primary bar run intersection and surface matching after add all bars, avoid interior windows)
    # I could loop through each space type and give them unique height but for now will just take largest height and make bar of that height, which is fine for prototypes
    if !multi_height_space_types_hash.empty?
      args3 = args.clone
      bars['custom_height'] = {}
      if mirror_ns_ew
        bars['custom_height'][:length] = width_cust_height
        bars['custom_height'][:width] = length_cust_height
      else
        bars['custom_height'][:length] = length_cust_height
        bars['custom_height'][:width] = width_cust_height
      end
      if args['party_wall_stories_east'] + args['party_wall_stories_west'] + args['party_wall_stories_south'] + args['party_wall_stories_north'] > 0.0
        runner.registerWarning('Ignorning party wall inputs for custom height bar')
      end

      # disable party walls
      args3['party_wall_stories_east'] = 0
      args3['party_wall_stories_west'] = 0
      args3['party_wall_stories_south'] = 0
      args3['party_wall_stories_north'] = 0

      # setup stories
      args3['num_stories_below_grade'] = 0
      args3['num_stories_above_grade'] = 1

      bars['custom_height'][:floor_height_si] = floor_height_si # can make use of this when breaking out multi-height spaces
      bars['custom_height'][:num_stories] = num_stories
      bars['custom_height'][:center_of_footprint] = OpenStudio::Point3d.new(bars['primary'][:length] * -0.5 - length_cust_height * 0.5 - offset_val, 0.0, 0.0)
      bars['custom_height'][:floor_height_si] = OpenStudio.convert(custom_story_heights.max, 'ft', 'm').get
      bars['custom_height'][:num_stories] = 1
      bars['custom_height'][:space_types_hash] = multi_height_space_types_hash
      bars['custom_height'][:args] = args3

      v = bars['custom_height']
      bar_hash_setup_run(runner, model, v[:args], v[:length], v[:width], v[:floor_height_si], v[:center_of_footprint], v[:space_types_hash], v[:num_stories])
    end

    # diagnostic log
    sum_actual = 0.0
    sum_target = 0.0
    throw_error = false

    # check expected floor areas against actual
    model.getSpaceTypes.sort.each do |space_type|
      next if !target_areas.key? space_type # space type in model not part of building type(s), maybe issue warning

      # convert to IP
      actual_ip = OpenStudio.convert(space_type.floorArea, 'm^2', 'ft^2').get
      target_ip = OpenStudio.convert(target_areas[space_type], 'm^2', 'ft^2').get
      sum_actual += actual_ip
      sum_target += target_ip

      if (space_type.floorArea - target_areas[space_type]).abs >= 1.0

        if !args['bar_division_method'].include? 'Single Space Type'
          runner.registerError("#{space_type.name} doesn't have the expected floor area (actual #{OpenStudio.toNeatString(actual_ip, 0, true)} ft^2, target #{OpenStudio.toNeatString(target_ip, 0, true)} ft^2)")
          throw_error = true
        else
          # will see this if use Single Space type division method on multi-use building or single building type without whole building space type
          runner.registerWarning("#{space_type.name} doesn't have the expected floor area (actual #{OpenStudio.toNeatString(actual_ip, 0, true)} ft^2, target #{OpenStudio.toNeatString(target_ip, 0, true)} ft^2)")
        end

      end
    end

    # report summary then throw error
    if throw_error
      runner.registerError("Sum of actual floor area is #{sum_actual} ft^2, sum of target floor area is #{sum_target}.")
      return false
    end

    # check party wall fraction by looping through surfaces
    if args['party_wall_fraction'] > 0
      actual_ext_wall_area = model.getBuilding.exteriorWallArea
      actual_party_wall_area = 0.0
      model.getSurfaces.sort.each do |surface|
        next if surface.outsideBoundaryCondition != 'Adiabatic'
        next if surface.surfaceType != 'Wall'
        actual_party_wall_area += surface.grossArea * surface.space.get.multiplier
      end
      actual_party_wall_fraction = actual_party_wall_area / (actual_party_wall_area + actual_ext_wall_area)
      runner.registerInfo("Target party wall fraction is #{args['party_wall_fraction']}. Realized fraction is #{actual_party_wall_fraction.round(2)}")
      runner.registerValue('party_wall_fraction_actual', actual_party_wall_fraction)
    end

    # check ns/ew aspect ratio (harder to check when party walls are added)
    wall_and_window_by_orientation = OsLib_Geometry.getExteriorWindowAndWllAreaByOrientation(model, model.getSpaces)
    wall_ns = (wall_and_window_by_orientation['northWall'] + wall_and_window_by_orientation['southWall'])
    wall_ew = wall_and_window_by_orientation['eastWall'] + wall_and_window_by_orientation['westWall']
    wall_ns_ip = OpenStudio.convert(wall_ns, 'm^2', 'ft^2').get
    wall_ew_ip = OpenStudio.convert(wall_ew, 'm^2', 'ft^2').get
    runner.registerValue('wall_area_ip', wall_ns_ip + wall_ew_ip, 'ft^2')
    runner.registerValue('ns_wall_area_ip', wall_ns_ip, 'ft^2')
    runner.registerValue('ew_wall_area_ip', wall_ew_ip, 'ft^2')
    # for now using perimeter of ground floor and average story area (building area / num_stories)
    runner.registerValue('floor_area_to_perim_ratio', model.getBuilding.floorArea / (OsLib_Geometry.calculate_perimeter(model) * num_stories))
    runner.registerValue('bar_width', OpenStudio.convert(bars['primary'][:width], 'm', 'ft').get, 'ft')

    if args['party_wall_fraction'] > 0 || args['party_wall_stories_north'] > 0 || args['party_wall_stories_south'] > 0 || args['party_wall_stories_east'] > 0 || args['party_wall_stories_west'] > 0
      runner.registerInfo('Target facade area by orientation not validated when party walls are applied')
    elsif args['num_stories_above_grade'] != args['num_stories_above_grade'].ceil
      runner.registerInfo('Target facade area by orientation not validated when partial top story is used')
    elsif dual_bar_calc_approach == 'stretched'
      runner.registerInfo('Target facade area by orientation not validated when single stretched bar has to be used to meet target minimum perimeter multiplier')
    elsif defaulted_args.include?('floor_height') && args['custom_height_bar'] && !multi_height_space_types_hash.empty?
      runner.registerInfo('Target facade area by orientation not validated when a dedicated bar is added for space types with custom heights')
    elsif args['bar_width'] > 0
      runner.registerInfo('Target facade area by orientation not validated when a dedicated custom bar width is defined')
    else

      # adjust length versus width based on building rotation
      if mirror_ns_ew
        wall_target_ns_ip = 2 * OpenStudio.convert(width, 'm', 'ft').get * args['perim_mult'] * args['num_stories_above_grade'] * args['floor_height']
        wall_target_ew_ip = 2 * OpenStudio.convert(length, 'm', 'ft').get * args['perim_mult'] * args['num_stories_above_grade'] * args['floor_height']
      else
        wall_target_ns_ip = 2 * OpenStudio.convert(length, 'm', 'ft').get * args['perim_mult'] * args['num_stories_above_grade'] * args['floor_height']
        wall_target_ew_ip = 2 * OpenStudio.convert(width, 'm', 'ft').get  * args['perim_mult'] * args['num_stories_above_grade'] * args['floor_height']
      end
      flag_error = false
      if (wall_target_ns_ip - wall_ns_ip).abs > 0.1
        runner.registerError("North/South walls don't have the expected area (actual #{OpenStudio.toNeatString(wall_ns_ip, 4, true)} ft^2, target #{OpenStudio.toNeatString(wall_target_ns_ip, 4, true)} ft^2)")
        flag_error = true
      end
      if (wall_target_ew_ip - wall_ew_ip).abs > 0.1
        runner.registerError("East/West walls don't have the expected area (actual #{OpenStudio.toNeatString(wall_ew_ip, 4, true)} ft^2, target #{OpenStudio.toNeatString(wall_target_ew_ip, 4, true)} ft^2)")
        flag_error = true
      end
      if flag_error
        return false
      end
    end

    # test for excessive exterior roof area (indication of problem with intersection and or surface matching)
    ext_roof_area = model.getBuilding.exteriorSurfaceArea - model.getBuilding.exteriorWallArea
    expected_roof_area = args['total_bldg_floor_area'] / (args['num_stories_above_grade'] + args['num_stories_below_grade']).to_f
    if ext_roof_area > expected_roof_area && single_floor_area_si == 0.0 # only test if using whole-building area input
      runner.registerError('Roof area larger than expected, may indicate problem with inter-floor surface intersection or matching.')
      return false
    end

    # set building rotation
    initial_rotation = model.getBuilding.northAxis
    if args['building_rotation'] != initial_rotation
      model.getBuilding.setNorthAxis(args['building_rotation'])
      runner.registerInfo("Set Building Rotation to #{model.getBuilding.northAxis}. Rotation altered after geometry generation is completed, as a result party wall orientation and aspect ratio may not reflect input values.")
    end

    # report final condition of model
    runner.registerFinalCondition("The building finished with #{model.getSpaces.size} spaces.")

    return true
  end

  # typical
  # used for varieties of measures that create typical building from model
  def typical_building_from_model(model, runner, user_arguments)
    # assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments(model))
    if !args then return false end

    # lookup and replace argument values from upstream measures
    if args['use_upstream_args'] == true
      args.each do |arg, value|
        next if arg == 'use_upstream_args' # this argument should not be changed
        value_from_osw = OsLib_HelperMethods.check_upstream_measure_for_arg(runner, arg)
        if !value_from_osw.empty?
          runner.registerInfo("Replacing argument named #{arg} from current measure with a value of #{value_from_osw[:value]} from #{value_from_osw[:measure_name]}.")
          new_val = value_from_osw[:value]
          # TODO: - make code to handle non strings more robust. check_upstream_measure_for_arg coudl pass bakc the argument type
          if arg == 'total_bldg_floor_area'
            args[arg] = new_val.to_f
          elsif arg == 'num_stories_above_grade'
            args[arg] = new_val.to_f
          elsif arg == 'zipcode'
            args[arg] = new_val.to_i
          else
            args[arg] = new_val
          end
        end
      end
    end

    # validate fraction parking
    fraction = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => 1.0, 'min_eq_bool' => true, 'max_eq_bool' => true, 'arg_array' => ['onsite_parking_fraction'])
    if !fraction then return false end

    # validate unmet hours tolerance
    unmet_hours_tolerance_valid = OsLib_HelperMethods.checkDoubleAndIntegerArguments(runner, user_arguments, 'min' => 0.0, 'max' => 5.0, 'min_eq_bool' => true, 'max_eq_bool' => true, 'arg_array' => ['unmet_hours_tolerance'])
    if !unmet_hours_tolerance_valid then return false end

    # validate weekday hours of operation
    wkdy_op_hrs_start_time_hr = nil
    wkdy_op_hrs_start_time_min = nil
    wkdy_op_hrs_duration_hr = nil
    wkdy_op_hrs_duration_min = nil
    if args['modify_wkdy_op_hrs']
      # weekday start time hr
      wkdy_op_hrs_start_time_hr = args['wkdy_op_hrs_start_time'].floor
      if wkdy_op_hrs_start_time_hr < 0 || wkdy_op_hrs_start_time_hr > 24
        runner.registerError("Weekday operating hours start time hrs must be between 0 and 24.  #{args['wkdy_op_hrs_start_time']} was entered.")
        return false
      end

      # weekday start time min
      wkdy_op_hrs_start_time_min = (60.0 * (args['wkdy_op_hrs_start_time'] - args['wkdy_op_hrs_start_time'].floor)).floor
      if wkdy_op_hrs_start_time_min < 0 || wkdy_op_hrs_start_time_min > 59
        runner.registerError("Weekday operating hours start time mins must be between 0 and 59.  #{args['wkdy_op_hrs_start_time']} was entered.")
        return false
      end

      # weekday duration hr
      wkdy_op_hrs_duration_hr = args['wkdy_op_hrs_duration'].floor
      if wkdy_op_hrs_duration_hr < 0 || wkdy_op_hrs_duration_hr > 24
        runner.registerError("Weekday operating hours duration hrs must be between 0 and 24.  #{args['wkdy_op_hrs_duration']} was entered.")
        return false
      end

      # weekday duration min
      wkdy_op_hrs_duration_min = (60.0 * (args['wkdy_op_hrs_duration'] - args['wkdy_op_hrs_duration'].floor)).floor
      if wkdy_op_hrs_duration_min < 0 || wkdy_op_hrs_duration_min > 59
        runner.registerError("Weekday operating hours duration mins must be between 0 and 59.  #{args['wkdy_op_hrs_duration']} was entered.")
        return false
      end

      # check that weekday start time plus duration does not exceed 24 hrs
      if (wkdy_op_hrs_start_time_hr + wkdy_op_hrs_duration_hr + (wkdy_op_hrs_start_time_min + wkdy_op_hrs_duration_min) / 60.0) > 24.0
        runner.registerInfo("Weekday start time of #{args['wkdy_op_hrs_start']} plus duration of #{args['wkdy_op_hrs_duration']} is more than 24 hrs, hours of operation overlap midnight.")
      end
    end

    # validate weekend hours of operation
    wknd_op_hrs_start_time_hr = nil
    wknd_op_hrs_start_time_min = nil
    wknd_op_hrs_duration_hr = nil
    wknd_op_hrs_duration_min = nil
    if args['modify_wknd_op_hrs']
      # weekend start time hr
      wknd_op_hrs_start_time_hr = args['wknd_op_hrs_start_time'].floor
      if wknd_op_hrs_start_time_hr < 0 || wknd_op_hrs_start_time_hr > 24
        runner.registerError("Weekend operating hours start time hrs must be between 0 and 24.  #{args['wknd_op_hrs_start_time_change']} was entered.")
        return false
      end

      # weekend start time min
      wknd_op_hrs_start_time_min = (60.0 * (args['wknd_op_hrs_start_time'] - args['wknd_op_hrs_start_time'].floor)).floor
      if wknd_op_hrs_start_time_min < 0 || wknd_op_hrs_start_time_min > 59
        runner.registerError("Weekend operating hours start time mins must be between 0 and 59.  #{args['wknd_op_hrs_start_time_change']} was entered.")
        return false
      end

      # weekend duration hr
      wknd_op_hrs_duration_hr = args['wknd_op_hrs_duration'].floor
      if wknd_op_hrs_duration_hr < 0 || wknd_op_hrs_duration_hr > 24
        runner.registerError("Weekend operating hours duration hrs must be between 0 and 24.  #{args['wknd_op_hrs_duration']} was entered.")
        return false
      end

      # weekend duration min
      wknd_op_hrs_duration_min = (60.0 * (args['wknd_op_hrs_duration'] - args['wknd_op_hrs_duration'].floor)).floor
      if wknd_op_hrs_duration_min < 0 || wknd_op_hrs_duration_min > 59
        runner.registerError("Weekend operating hours duration min smust be between 0 and 59.  #{args['wknd_op_hrs_duration']} was entered.")
        return false
      end

      # check that weekend start time plus duration does not exceed 24 hrs
      if (wknd_op_hrs_start_time_hr + wknd_op_hrs_duration_hr + (wknd_op_hrs_start_time_min + wknd_op_hrs_duration_min) / 60.0) > 24.0
        runner.registerInfo("Weekend start time of #{args['wknd_op_hrs_start']} plus duration of #{args['wknd_op_hrs_duration']} is more than 24 hrs, hours of operation overlap midnight.")
      end
    end

    # report initial condition of model
    initial_objects = model.getModelObjects.size
    runner.registerInitialCondition("The building started with #{initial_objects} objects.")

    # open channel to log messages
    reset_log

    # Make the standard applier
    standard = Standard.build((args['template']).to_s)

    # validate climate zone
    if !args.key?('climate_zone') || args['climate_zone'] == 'Lookup From Model'
      climate_zone = standard.model_get_building_climate_zone_and_building_type(model)['climate_zone']
      runner.registerInfo("Using climate zone #{climate_zone} from model")
    else
      climate_zone = args['climate_zone']
      runner.registerInfo("Using climate zone #{climate_zone} from user arguments")
    end
    if climate_zone == ''
      runner.registerError("Could not determine climate zone from measure arguments or model.")
      return false
    end

    # make sure daylight savings is turned on up prior to any sizing runs being done.
    if args['enable_dst']
      start_date = '2nd Sunday in March'
      end_date = '1st Sunday in November'

      runperiodctrl_daylgtsaving = model.getRunPeriodControlDaylightSavingTime
      runperiodctrl_daylgtsaving.setStartDate(start_date)
      runperiodctrl_daylgtsaving.setEndDate(end_date)
    end

    # add internal loads to space types
    if args['add_space_type_loads']

      # remove internal loads
      if args['remove_objects']
        model.getSpaceLoads.sort.each do |instance|
          next if instance.name.to_s.include?('Elevator') # most prototype building types model exterior elevators with name Elevator
          next if instance.to_InternalMass.is_initialized
          next if instance.to_WaterUseEquipment.is_initialized
          instance.remove
        end
        model.getDesignSpecificationOutdoorAirs.each(&:remove)
        model.getDefaultScheduleSets.each(&:remove)
      end

      model.getSpaceTypes.sort.each do |space_type|
        # Don't add infiltration here; will be added later in the script
        test = standard.space_type_apply_internal_loads(space_type, true, true, true, true, true, false)
        if test == false
          runner.registerWarning("Could not add loads for #{space_type.name}. Not expected for #{args['template']}")
          next
        end

        # apply internal load schedules
        # the last bool test it to make thermostat schedules. They are now added in HVAC section instead of here
        standard.space_type_apply_internal_load_schedules(space_type, true, true, true, true, true, true, false)

        # extend space type name to include the args['template']. Consider this as well for load defs
        space_type.setName("#{space_type.name} - #{args['template']}")
        runner.registerInfo("Adding loads to space type named #{space_type.name}")
      end

      # warn if spaces in model without space type
      spaces_without_space_types = []
      model.getSpaces.sort.each do |space|
        next if space.spaceType.is_initialized
        spaces_without_space_types << space
      end
      if !spaces_without_space_types.empty?
        runner.registerWarning("#{spaces_without_space_types.size} spaces do not have space types assigned, and wont' receive internal loads from standards space type lookups.")
      end
    end

    # identify primary building type (used for construction, and ideally HVAC as well)
    building_types = {}
    model.getSpaceTypes.sort.each do |space_type|
      # populate hash of building types
      if space_type.standardsBuildingType.is_initialized
        bldg_type = space_type.standardsBuildingType.get
        if !building_types.key?(bldg_type)
          building_types[bldg_type] = space_type.floorArea
        else
          building_types[bldg_type] += space_type.floorArea
        end
      else
        runner.registerWarning("Can't identify building type for #{space_type.name}")
      end
    end
    primary_bldg_type = building_types.key(building_types.values.max) # TODO: - this fails if no space types, or maybe just no space types with standards
    lookup_building_type = standard.model_get_lookup_name(primary_bldg_type) # Used for some lookups in the standards gem
    model.getBuilding.setStandardsBuildingType(primary_bldg_type)

    # make construction set and apply to building
    if args['add_constructions']

      # remove default construction sets
      if args['remove_objects']
        model.getDefaultConstructionSets.each(&:remove)
      end

      # TODO: - allow building type and space type specific constructions set selection.
      if ['SmallHotel', 'LargeHotel', 'MidriseApartment', 'HighriseApartment'].include?(primary_bldg_type)
        is_residential = 'Yes'
        occ_type = 'Residential'
      else
        is_residential = 'No'
        occ_type = 'Nonresidential'
      end
      if !args.has_key?('climate_zone') || args['climate_zone'] == 'Lookup From Model'
        climate_zone = standard.model_get_building_climate_zone_and_building_type(model)['climate_zone']
        runner.registerInfo("Using climate zone #{climate_zone} from model")
      else
        climate_zone = args['climate_zone']
        runner.registerInfo("Using climate zone #{climate_zone} from user arguments")
      end

      # set FC factor constructions before adding other constructions
      standard.model_set_below_grade_wall_constructions(model, lookup_building_type, climate_zone)
      standard.model_set_floor_constructions(model, lookup_building_type, climate_zone)
      if model.getFFactorGroundFloorConstructions.empty?
        runner.registerInfo("Unable to determine FC factor value to use.  Using default ground construction instead.")
      else
        runner.registerInfo("Set FC factor constructions for slab and below grade walls.")
      end

      # adjust F factor constructions to avoid simulation errors
      model.getFFactorGroundFloorConstructions.each do |cons|
        # Rfilm_in = 0.135, Rfilm_out = 0.03, Rcons = 0.15/1.95
        if cons.area <= (0.135 + 0.03 + 0.15/1.95) * cons.perimeterExposed * cons.fFactor
          # set minimum Rfic to > 1e-3
          new_area = 0.233 * cons.perimeterExposed * cons.fFactor
          runner.registerInfo("F-factor fictitious resistance for #{cons.name.get} with Area=#{cons.area.round(2)}, Exposed Perimeter=#{cons.perimeterExposed.round(2)}, and F-factor=#{cons.fFactor.round(2)} will result in a negative value and a failed simulation. Construction area is adjusted to be #{new_area.round(2)}.")
          cons.setArea(new_area)
        end
      end

      # add construction set
      bldg_def_const_set = standard.model_add_construction_set(model, climate_zone, lookup_building_type, nil, is_residential)
      if bldg_def_const_set.is_initialized
        bldg_def_const_set = bldg_def_const_set.get
        if is_residential == 'Yes'
          bldg_def_const_set.setName("Res #{bldg_def_const_set.name}")
        end
        model.getBuilding.setDefaultConstructionSet(bldg_def_const_set)
        runner.registerInfo("Adding default construction set named #{bldg_def_const_set.name}")
      else
        runner.registerError("Could not create default construction set for the building type #{lookup_building_type} in climate zone #{climate_zone}.")
        log_messages_to_runner(runner, debug = true)
        return false
      end

      # Replace the construction of exterior walls with user-specified wall construction type
      wall_construction_type = args['wall_construction_type']
      unless wall_construction_type == 'Inferred'
        # Check that a default exterior construction set is defined
        if bldg_def_const_set.defaultExteriorSurfaceConstructions.empty?
          runner.registerError("Default construction set has no default exterior surface constructions.")
          log_messages_to_runner(runner, debug = true)
          return false
        end
        ext_surf_consts = bldg_def_const_set.defaultExteriorSurfaceConstructions.get

        # Check that a default exterior wall is defined
        if ext_surf_consts.wallConstruction.empty?
          runner.registerError("Default construction set has no default exterior wall construction.")
          log_messages_to_runner(runner, debug = true)
          return false
        end
        old_construction = ext_surf_consts.wallConstruction.get
        standards_info = old_construction.standardsInformation

        # Get the old wall construction type
        if standards_info.standardsConstructionType.empty?
          old_wall_construction_type = 'Not defined'
        else
          old_wall_construction_type = standards_info.standardsConstructionType.get
        end

        # Modify the default wall construction if different from measure input
        if old_wall_construction_type == wall_construction_type
          # Don’t modify if the default matches the user-specified wall construction type
          runner.registerInfo("Exterior wall construction type #{wall_construction_type} is the default for this building type.")
        else
          climate_zone_set = standard.model_find_climate_zone_set(model, climate_zone)
          new_construction = standard.model_find_and_add_construction(model,
                                                                      climate_zone_set,
                                                                      'ExteriorWall',
                                                                      wall_construction_type,
                                                                      occ_type)
          ext_surf_consts.setWallConstruction(new_construction)
          runner.registerInfo("Set exterior wall construction to #{new_construction.name}, replacing building type default #{old_construction.name}.")
        end
      end

      # Replace the construction of any outdoor-facing "AtticFloor" surfaces
      # with the "ExteriorRoof" - "IEAD" construction for the specific climate zone and template.
      # This prevents creation of buildings where the DOE Prototype building construction set
      # assumes an attic but the supplied geometry used does not have an attic.
      new_construction = nil
      climate_zone_set = standard.model_find_climate_zone_set(model, climate_zone)
      model.getSurfaces.sort.each do |surf|
        next unless surf.outsideBoundaryCondition == 'Outdoors'
        next unless surf.surfaceType == 'RoofCeiling'
        next if surf.construction.empty?
        construction = surf.construction.get
        standards_info = construction.standardsInformation
        next if standards_info.intendedSurfaceType.empty?
        next unless standards_info.intendedSurfaceType.get == 'AtticFloor'
        if new_construction.nil?
          new_construction = standard.model_find_and_add_construction(model,
                                                                      climate_zone_set,
                                                                      'ExteriorRoof',
                                                                      'IEAD',
                                                                      occ_type)
        end
        surf.setConstruction(new_construction)
        runner.registerInfo("Changed the construction for #{surf.name} from #{construction.name} to #{new_construction.name} to avoid outdoor-facing attic floor constructions in buildings with no attic space.")
      end

      # address any adiabatic surfaces that don't have hard assigned constructions
      model.getSurfaces.sort.each do |surface|
        next if surface.outsideBoundaryCondition != 'Adiabatic'
        next if surface.construction.is_initialized
        surface.setAdjacentSurface(surface)
        surface.setConstruction(surface.construction.get)
        surface.setOutsideBoundaryCondition('Adiabatic')
      end

      # modify the infiltration rates
      if args['remove_objects']
        model.getSpaceInfiltrationDesignFlowRates.each(&:remove)
      end
      standard.model_apply_infiltration_standard(model)
      standard.model_modify_infiltration_coefficients(model, primary_bldg_type, climate_zone)

      # set ground temperatures from DOE prototype buildings
      standard.model_add_ground_temperatures(model, primary_bldg_type, climate_zone)

    end

    # add elevators (returns ElectricEquipment object)
    if args['add_elevators']

      # remove elevators as spaceLoads or exteriorLights
      model.getSpaceLoads.sort.each do |instance|
        next if !instance.name.to_s.include?('Elevator') # most prototype building types model exterior elevators with name Elevator
        instance.remove
      end
      model.getExteriorLightss.sort.each do |ext_light|
        next if !ext_light.name.to_s.include?('Fuel equipment') # some prototype building types model exterior elevators by this name
        ext_light.remove
      end

      elevators = standard.model_add_elevators(model)
      if elevators.nil?
        runner.registerInfo('No elevators added to the building.')
      else
        elevator_def = elevators.electricEquipmentDefinition
        design_level = elevator_def.designLevel.get
        runner.registerInfo("Adding #{elevators.multiplier.round(1)} elevators each with power of #{OpenStudio.toNeatString(design_level, 0, true)} (W), plus lights and fans.")
        elevator_def.setFractionLatent(0.0)
        elevator_def.setFractionRadiant(0.0)
        elevator_def.setFractionLost(1.0)
      end
    end

    # add exterior lights (returns a hash where key is lighting type and value is exteriorLights object)
    if args['add_exterior_lights']

      if args['remove_objects']
        model.getExteriorLightss.sort.each do |ext_light|
          next if ext_light.name.to_s.include?('Fuel equipment') # some prototype building types model exterior elevators by this name
          ext_light.remove
        end
      end

      exterior_lights = standard.model_add_typical_exterior_lights(model, args['exterior_lighting_zone'].chars[0].to_i, args['onsite_parking_fraction'])
      exterior_lights.each do |k, v|
        runner.registerInfo("Adding Exterior Lights named #{v.exteriorLightsDefinition.name} with design level of #{v.exteriorLightsDefinition.designLevel} * #{OpenStudio.toNeatString(v.multiplier, 0, true)}.")
      end
    end

    # add_exhaust
    if args['add_exhaust']

      # remove exhaust objects
      if args['remove_objects']
        model.getFanZoneExhausts.each(&:remove)
      end

      zone_exhaust_fans = standard.model_add_exhaust(model, args['kitchen_makeup']) # second argument is strategy for finding makeup zones for exhaust zones
      zone_exhaust_fans.each do |k, v|
        max_flow_rate_ip = OpenStudio.convert(k.maximumFlowRate.get, 'm^3/s', 'cfm').get
        if v.key?(:zone_mixing)
          zone_mixing = v[:zone_mixing]
          mixing_source_zone_name = zone_mixing.sourceZone.get.name
          mixing_design_flow_rate_ip = OpenStudio.convert(zone_mixing.designFlowRate.get, 'm^3/s', 'cfm').get
          runner.registerInfo("Adding #{OpenStudio.toNeatString(max_flow_rate_ip, 0, true)} (cfm) of exhaust to #{k.thermalZone.get.name}, with #{OpenStudio.toNeatString(mixing_design_flow_rate_ip, 0, true)} (cfm) of makeup air from #{mixing_source_zone_name}")
        else
          runner.registerInfo("Adding #{OpenStudio.toNeatString(max_flow_rate_ip, 0, true)} (cfm) of exhaust to #{k.thermalZone.get.name}")
        end
      end
    end

    # add service water heating demand and supply
    if args['add_swh']

      # remove water use equipment and water use connections
      if args['remove_objects']
        # TODO: - remove plant loops used for service water heating
        model.getWaterUseEquipments.each(&:remove)
        model.getWaterUseConnectionss.each(&:remove)
      end

      # Infer the SWH type
      if args['swh_src'] == 'Inferred'
        if args['htg_src'] == 'NaturalGas' || args['htg_src'] == 'DistrictHeating'
          args['swh_src'] = 'NaturalGas' # If building has gas service, probably uses natural gas for SWH
        elsif args['htg_src'] == 'Electricity'
          args['swh_src'] == 'Electricity' # If building is doing space heating with electricity, probably used for SWH
        elsif args['htg_src'] == 'DistrictAmbient'
          args['swh_src'] == 'HeatPump' # If building has district ambient loop, it is fancy and probably uses HPs for SWH
        else
          args['swh_src'] = nil # Use inferences built into OpenStudio Standards for each building and space type
        end
      end

      typical_swh = standard.model_add_typical_swh(model, water_heater_fuel: args['swh_src'])
      midrise_swh_loops = []
      stripmall_swh_loops = []
      typical_swh.each do |loop|
        if loop.name.get.include?('MidriseApartment')
          midrise_swh_loops << loop
        elsif loop.name.get.include?('RetailStripmall')
          stripmall_swh_loops << loop
        else
          water_use_connections = []
          loop.demandComponents.each do |component|
            next if !component.to_WaterUseConnections.is_initialized
            water_use_connections << component
          end
          runner.registerInfo("Adding #{loop.name} to the building. It has #{water_use_connections.size} water use connections.")
        end
      end
      if !midrise_swh_loops.empty?
        runner.registerInfo("Adding #{midrise_swh_loops.size} MidriseApartment service water heating loops.")
      end
      if !stripmall_swh_loops.empty?
        runner.registerInfo("Adding #{stripmall_swh_loops.size} RetailStripmall service water heating loops.")
      end

      # Modify Pipe:Indoor objects to have an ambient temperature that's always
      # higher than the warmest Site:WaterMainsTemperature found in the year
      # TODO remove once this EnergyPlus issue is closed: https://github.com/NREL/EnergyPlus/issues/9650
      water_temp = model.getSiteWaterMainsTemperature
      mean_c = water_temp.annualAverageOutdoorAirTemperature.get
      max_delta_c = water_temp.maximumDifferenceInMonthlyAverageOutdoorAirTemperatures.get
      max_temp_c = mean_c + (0.5 * max_delta_c) + 3.0 # To ensure higher than mains temp
      max_temp_c = max_temp_c.round(1)
      max_temp_f = OpenStudio.convert(max_temp_c, 'C', 'F').get
      max_temp_f = max_temp_f.round(1)
      pipe_indoor_temp_sch = OpenStudio::Model::ScheduleConstant.new(model)
      pipe_indoor_temp_sch.setName("Temporary Pipe Indoor Ambient Temp #{max_temp_f}F")
      pipe_indoor_temp_sch.setValue(max_temp_c)
      model.getPipeIndoors.each do |heat_loss_pipe|
        # TODO schedule type registry error for this setter
        # heat_loss_pipe.setAmbientTemperatureSchedule(pipe_indoor_temp_sch)
        heat_loss_pipe.setPointer(7, pipe_indoor_temp_sch.handle)
      end
      runner.registerWarning("Set Pipe:Indoor ambient temp schedules to #{max_temp_f}F to avoid E+ issue 9650, remove once fixed.")
    end

    # add_daylighting_controls (since outdated measure don't have this default to true if arg not found)
    if !args.has_key?('add_daylighting_controls')
      args['add_daylighting_controls'] = true
    end
    if args['add_daylighting_controls']
      # remove add_daylighting_controls objects
      if args['remove_objects']
        model.getDaylightingControls.each(&:remove)
      end

      # add daylight controls, need to perform a sizing run for 2010
      if args['template'] == '90.1-2010' || args['template'] == 'ComStock 90.1-2010'
        if standard.model_run_sizing_run(model, "#{Dir.pwd}/create_typical_building_from_model_SR0") == false
          log_messages_to_runner(runner, debug = true)
          return false
        end
      end
      standard.model_add_daylighting_controls(model)
    end

    # add refrigeration
    if args['add_refrigeration']

      # remove refrigeration equipment
      if args['remove_objects']
        model.getRefrigerationSystems.each(&:remove)
      end

      # Add refrigerated cases and walkins
      standard.model_add_typical_refrigeration(model, primary_bldg_type)
    end

    # add internal mass
    if args['add_internal_mass']

      if args['remove_objects']
        model.getSpaceLoads.sort.each do |instance|
          next unless instance.to_InternalMass.is_initialized
          instance.remove
        end
      end

      # add internal mass to conditioned spaces; needs to happen after thermostats are applied
      standard.model_add_internal_mass(model, primary_bldg_type)
    end

    # TODO: - add slab modeling and slab insulation

    # TODO: - fuel customization for cooking and laundry
    # works by switching some fraction of electric loads to gas if requested (assuming base load is electric)

    # add thermostats
    if args['add_thermostat']

      # remove thermostats
      if args['remove_objects']
        model.getThermostatSetpointDualSetpoints.each(&:remove)
      end

      model.getSpaceTypes.sort.each do |space_type|
        # create thermostat schedules
        # skip un-recognized space types
        next if standard.space_type_get_standards_data(space_type).empty?
        # the last bool test it to make thermostat schedules. They are added to the model but not assigned
        standard.space_type_apply_internal_load_schedules(space_type, false, false, false, false, false, false, true)

        # identify thermal thermostat and apply to zones (apply_internal_load_schedules names )
        model.getThermostatSetpointDualSetpoints.sort.each do |thermostat|
          next if thermostat.name.to_s != "#{space_type.name} Thermostat"
          next if !thermostat.coolingSetpointTemperatureSchedule.is_initialized
          next if !thermostat.heatingSetpointTemperatureSchedule.is_initialized
          runner.registerInfo("Assigning #{thermostat.name} to thermal zones with #{space_type.name} assigned.")
          space_type.spaces.sort.each do |space|
            next if !space.thermalZone.is_initialized
            space.thermalZone.get.setThermostatSetpointDualSetpoint(thermostat)
          end
        end
      end
    end

    # add hvac system
    if args['add_hvac']

      # remove HVAC objects
      if args['remove_objects']
        standard.model_remove_prm_hvac(model)
      end

      case args['system_type']
      when 'Inferred'

        # Get the hvac delivery type enum
        hvac_delivery = case args['hvac_delivery_type']
                        when 'Forced Air'
                          'air'
                        when 'Hydronic'
                          'hydronic'
                        end

        # Group the zones by occupancy type.  Only split out non-dominant groups if their total area exceeds the limit.
        sys_groups = standard.model_group_zones_by_type(model, OpenStudio.convert(20_000, 'ft^2', 'm^2').get)

        # For each group, infer the HVAC system type.
        sys_groups.each do |sys_group|
          # Infer the primary system type
          # runner.registerInfo("template = #{args['template']}, climate_zone = #{climate_zone}, occ_type = #{sys_group['type']}, hvac_delivery = #{hvac_delivery}, htg_src = #{args['htg_src']}, clg_src = #{args['clg_src']}, area_ft2 = #{sys_group['area_ft2']}, num_stories = #{sys_group['stories']}")
          sys_type, central_htg_fuel, zone_htg_fuel, clg_fuel = standard.model_typical_hvac_system_type(model,
                                                                                                        climate_zone,
                                                                                                        sys_group['type'],
                                                                                                        hvac_delivery,
                                                                                                        args['htg_src'],
                                                                                                        args['clg_src'],
                                                                                                        OpenStudio.convert(sys_group['area_ft2'], 'ft^2', 'm^2').get,
                                                                                                        sys_group['stories'])

          # Infer the secondary system type for multizone systems
          sec_sys_type = case sys_type
                         when 'PVAV Reheat', 'VAV Reheat'
                           'PSZ-AC'
                         when 'PVAV PFP Boxes', 'VAV PFP Boxes'
                           'PSZ-HP'
                         else
                           sys_type # same as primary system type
                         end

          # Group zones by story
          story_zone_lists = standard.model_group_zones_by_story(model, sys_group['zones'])

          # On each story, add the primary system to the primary zones
          # and add the secondary system to any zones that are different.
          story_zone_lists.each do |story_group|
            # Differentiate primary and secondary zones, based on
            # operating hours and internal loads (same as 90.1 PRM)
            pri_sec_zone_lists = standard.model_differentiate_primary_secondary_thermal_zones(model, story_group)
            system_zones = pri_sec_zone_lists['primary']

            # if the primary system type is PTAC, filter to cooled zones to prevent sizing error if no cooling
            if sys_type == 'PTAC'
              heated_and_cooled_zones = system_zones.select { |zone| standard.thermal_zone_heated?(zone) && standard.thermal_zone_cooled?(zone) }
              cooled_only_zones = system_zones.select { |zone| !standard.thermal_zone_heated?(zone) && standard.thermal_zone_cooled?(zone) }
              system_zones = heated_and_cooled_zones + cooled_only_zones
            end

            # Add the primary system to the primary zones
            unless standard.model_add_hvac_system(model, sys_type, central_htg_fuel, zone_htg_fuel, clg_fuel, system_zones)
              runner.registerError("HVAC system type '#{sys_type}' not recognized. Check input system type argument against Model.hvac.rb for valid hvac system type names.")
              return false
            end

            # Add the secondary system to the secondary zones (if any)
            if !pri_sec_zone_lists['secondary'].empty?
              system_zones = pri_sec_zone_lists['secondary']
              if (sec_sys_type == 'PTAC') || (sec_sys_type == 'PSZ-AC')
                heated_and_cooled_zones = system_zones.select { |zone| standard.thermal_zone_heated?(zone) && standard.thermal_zone_cooled?(zone) }
                cooled_only_zones = system_zones.select { |zone| !standard.thermal_zone_heated?(zone) && standard.thermal_zone_cooled?(zone) }
                system_zones = heated_and_cooled_zones + cooled_only_zones
              end
              unless standard.model_add_hvac_system(model, sec_sys_type, central_htg_fuel, zone_htg_fuel, clg_fuel, system_zones)
                runner.registerError("HVAC system type '#{sys_type}' not recognized. Check input system type argument against Model.hvac.rb for valid hvac system type names.")
                return false
              end
            end
          end
        end

      else # HVAC system_type specified

        # Group the zones by occupancy type.  Only split out non-dominant groups if their total area exceeds the limit.
        sys_groups = standard.model_group_zones_by_type(model, OpenStudio.convert(20_000, 'ft^2', 'm^2').get)
        sys_groups.each do |sys_group|
          # Group the zones by story
          story_groups = standard.model_group_zones_by_story(model, sys_group['zones'])

          # Add the user specified HVAC system for each story.
          # Single-zone systems will get one per zone.
          story_groups.each do |zones|
            unless model.add_cbecs_hvac_system(standard, args['system_type'], zones)
              runner.registerError("HVAC system type '#{args['system_type']}' not recognized. Check input system type argument against Model.hvac.rb for valid hvac system type names.")
              return false
            end
          end
        end
      end
    end

    # hours of operation
    if args['modify_wkdy_op_hrs'] || args['modify_wknd_op_hrs']
      # Infer the current hours of operation schedule for the building
      op_sch = standard.model_infer_hours_of_operation_building(model)

      # Convert existing schedules in the model to parametric schedules based on current hours of operation
      standard.model_setup_parametric_schedules(model)

      # Create start and end times from start time and duration supplied
      wkdy_start_time = nil
      wkdy_end_time = nil
      wknd_start_time = nil
      wknd_end_time = nil
      # weekdays
      if args['modify_wkdy_op_hrs']
        wkdy_start_time = OpenStudio::Time.new(0, wkdy_op_hrs_start_time_hr, wkdy_op_hrs_start_time_min, 0)
        wkdy_end_time = wkdy_start_time + OpenStudio::Time.new(0, wkdy_op_hrs_duration_hr, wkdy_op_hrs_duration_min, 0)
      end
      # weekends
      if args['modify_wknd_op_hrs']
        wknd_start_time = OpenStudio::Time.new(0, wknd_op_hrs_start_time_hr, wknd_op_hrs_start_time_min, 0)
        wknd_end_time = wknd_start_time + OpenStudio::Time.new(0, wknd_op_hrs_duration_hr, wknd_op_hrs_duration_min, 0)
      end

      # Modify hours of operation, using weekdays values for all weekdays and weekend values for Saturday and Sunday
      standard.schedule_ruleset_set_hours_of_operation(op_sch,
                                                       wkdy_start_time: wkdy_start_time,
                                                       wkdy_end_time: wkdy_end_time,
                                                       sat_start_time: wknd_start_time,
                                                       sat_end_time: wknd_end_time,
                                                       sun_start_time: wknd_start_time,
                                                       sun_end_time: wknd_end_time)

      # Apply new operating hours to parametric schedules to make schedules in model reflect modified hours of operation
      parametric_schedules = standard.model_apply_parametric_schedules(model, error_on_out_of_order: false)
      runner.registerInfo("Updated #{parametric_schedules.size} schedules with new hours of operation.")
    end

    # set hvac controls and efficiencies (this should be last model articulation element)
    if args['add_hvac']
      # set additional properties for building
      props = model.getBuilding.additionalProperties
      props.setFeature('hvac_system_type', (args['system_type']).to_s)

      case args['system_type']
      when 'Ideal Air Loads'

      else
        # Set the heating and cooling sizing parameters
        standard.model_apply_prm_sizing_parameters(model)

        # Perform a sizing run
        if standard.model_run_sizing_run(model, "#{Dir.pwd}/create_typical_building_from_model_SR1") == false
          log_messages_to_runner(runner, debug = true)
          return false
        end

        # If there are any multizone systems, reset damper positions
        # to achieve a 60% ventilation effectiveness minimum for the system
        # following the ventilation rate procedure from 62.1
        standard.model_apply_multizone_vav_outdoor_air_sizing(model)

        # Apply the prototype HVAC assumptions
        standard.model_apply_prototype_hvac_assumptions(model, primary_bldg_type, climate_zone)

        # Apply the HVAC efficiency standard
        standard.model_apply_hvac_efficiency_standard(model, climate_zone)
      end
    end

    # add internal mass
    if args['add_internal_mass']

      if args['remove_objects']
        model.getSpaceLoads.sort.each do |instance|
          next unless instance.to_InternalMass.is_initialized
          instance.remove
        end
      end

      # add internal mass to conditioned spaces; needs to happen after thermostats are applied
      standard.model_add_internal_mass(model, primary_bldg_type)
    end

    # set unmet hours tolerance
    unmet_hrs_tol_r = args['unmet_hours_tolerance']
    unmet_hrs_tol_k = OpenStudio.convert(unmet_hrs_tol_r, 'R', 'K').get
    tolerances = model.getOutputControlReportingTolerances
    tolerances.setToleranceforTimeHeatingSetpointNotMet(unmet_hrs_tol_k)
    tolerances.setToleranceforTimeCoolingSetpointNotMet(unmet_hrs_tol_k)

    # remove everything but spaces, zones, and stub space types (extend as needed for additional objects, may make bool arg for this)
    if args['remove_objects']
      model.purgeUnusedResourceObjects
      objects_after_cleanup = initial_objects - model.getModelObjects.size
      if objects_after_cleanup > 0
        runner.registerInfo("Removing #{objects_after_cleanup} objects from model")
      end
    end

    # disable HVAC Sizing Simulation for Sizing Periods, not used for the type of PlantLoop sizing used in ComStock
    if model.version >= OpenStudio::VersionString.new('3.0.0')
      sim_control = model.getSimulationControl
      sim_control.setDoHVACSizingSimulationforSizingPeriodsNoFail(false)
    end

    # report final condition of model
    runner.registerFinalCondition("The building finished with #{model.getModelObjects.size} objects.")

    # log messages to info messages
    log_messages_to_runner(runner, debug = false)

    return true
  end

  # wizard
  # used for varieties of measures that create space type and construction set wizard
  def wizard(model, runner, user_arguments)
    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    building_type = runner.getStringArgumentValue('building_type', user_arguments)
    template = runner.getStringArgumentValue('template', user_arguments)
    climate_zone = runner.getStringArgumentValue('climate_zone', user_arguments)
    create_space_types = runner.getBoolArgumentValue('create_space_types', user_arguments)
    create_construction_set = runner.getBoolArgumentValue('create_construction_set', user_arguments)
    set_building_defaults = runner.getBoolArgumentValue('set_building_defaults', user_arguments)

    # reporting initial condition of model
    starting_spaceTypes = model.getSpaceTypes.sort
    starting_constructionSets = model.getDefaultConstructionSets.sort
    runner.registerInitialCondition("The building started with #{starting_spaceTypes.size} space types and #{starting_constructionSets.size} construction sets.")

    # lookup space types for specified building type (false indicates not to use whole building type only)
    space_type_hash = get_space_types_from_building_type(building_type, template, false)
    if space_type_hash == false
      runner.registerError("#{building_type} is an unexpected building type.")
      return false
    end

    # create space_type_map from array
    space_type_map = {}
    default_space_type_name = nil
    space_type_hash.each do |space_type_name, hash|
      next if hash[:space_type_gen] == false # space types like undeveloped and basement are skipped.
      space_type_map[space_type_name] = [] # no spaces to pass in
      if hash[:default]
        default_space_type_name = space_type_name
      end
    end

    # Make the standard applier
    standard = Standard.build(template)

    # mapping building_type name is needed for a few methods
    lookup_building_type = standard.model_get_lookup_name(building_type)

    # remap small medium and large office to office
    if building_type.include?('Office') then building_type = 'Office' end

    # get array of new space types
    space_types_new = []

    # create_space_types
    if create_space_types

      # array of starting space types
      space_types_starting = model.getSpaceTypes.sort

      # create stub space types
      space_type_hash.each do |space_type_name, hash|
        next if hash[:space_type_gen] == false # space types like undeveloped and basement are skipped.

        # create space type
        space_type = OpenStudio::Model::SpaceType.new(model)
        space_type.setStandardsBuildingType(building_type)
        space_type.setStandardsSpaceType(space_type_name)
        space_type.setName("#{building_type} #{space_type_name}")

        # add to array of new space types
        space_types_new << space_type

        # add internal loads (the nil check isn't ncessary, but I will keep it in as a warning instad of an error)
        test = standard.space_type_apply_internal_loads(space_type, true, true, true, true, true, true)
        if test.nil?
          runner.registerWarning("Could not add loads for #{space_type.name}. Not expected for #{template} #{lookup_building_type}")
        end

        # the last bool test it to make thermostat schedules. They are added to the model but not assigned
        standard.space_type_apply_internal_load_schedules(space_type, true, true, true, true, true, true, true)

        # assign colors
        standard.space_type_apply_rendering_color(space_type)

        # exend space type name to include the template. Consider this as well for load defs
        space_type.setName("#{space_type.name} - #{template}")
        runner.registerInfo("Added space type named #{space_type.name}")
      end

    end

    # add construction sets
    bldg_def_const_set = nil
    if create_construction_set

      # Make the default construction set for the building
      is_residential = 'No' # default is nonresidential for building level
      bldg_def_const_set = standard.model_add_construction_set(model, climate_zone, lookup_building_type, nil, is_residential)
      if bldg_def_const_set.is_initialized
        bldg_def_const_set = bldg_def_const_set.get
        runner.registerInfo("Added default construction set named #{bldg_def_const_set.name}")
      else
        runner.registerError('Could not create default construction set for the building.')
        return false
      end

      # make residential construction set as unused resource
      if ['SmallHotel', 'LargeHotel', 'MidriseApartment', 'HighriseApartment'].include?(building_type)
        res_const_set = standard.model_add_construction_set(model, climate_zone, lookup_building_type, nil, 'Yes')
        if res_const_set.is_initialized
          res_const_set = res_const_set.get
          res_const_set.setName("#{bldg_def_const_set.name} - Residential ")
          runner.registerInfo("Added residential construction set named #{res_const_set.name}")
        else
          runner.registerError('Could not create residential construction set for the building.')
          return false
        end
      end

    end

    # set_building_defaults
    if set_building_defaults

      # identify default space type
      space_type_standards_info_hash = OsLib_HelperMethods.getSpaceTypeStandardsInformation(space_types_new)
      default_space_type = nil
      space_type_standards_info_hash.each do |space_type, standards_array|
        standards_space_type = standards_array[1]
        if default_space_type_name == standards_space_type
          default_space_type = space_type
        end
      end

      # set default space type
      building = model.getBuilding
      if !default_space_type.nil?
        building.setSpaceType(default_space_type)
        runner.registerInfo("Setting default Space Type for building to #{building.spaceType.get.name}")
      end

      # default construction
      if !bldg_def_const_set.nil?
        building.setDefaultConstructionSet(bldg_def_const_set)
        runner.registerInfo("Setting default Construction Set for building to #{building.defaultConstructionSet.get.name}")
      end

      # set climate zone
      os_climate_zone = climate_zone.gsub('ASHRAE 169-2013-', '')
      # trim off letter from climate zone 7 or 8
      if (os_climate_zone[0] == '7') || (os_climate_zone[0] == '8')
        os_climate_zone = os_climate_zone[0]
      end
      climate_zone = model.getClimateZones.setClimateZone('ASHRAE', os_climate_zone)
      runner.registerInfo("Setting #{climate_zone.institution} Climate Zone to #{climate_zone.value}")

      # set building type
      # use lookup_building_type so spaces like MediumOffice will map to Office (Supports baseline automation)
      building.setStandardsBuildingType(lookup_building_type)
      runner.registerInfo("Setting Standards Building Type to #{building.standardsBuildingType}")

      # rename building if it is named "Building 1"
      if model.getBuilding.name.to_s == 'Building 1'
        model.getBuilding.setName("#{building_type} #{template} #{os_climate_zone}")
        runner.registerInfo("Renaming building to #{model.getBuilding.name}")
      end

    end

    # reporting final condition of model
    finishing_spaceTypes = model.getSpaceTypes.sort
    finishing_constructionSets = model.getDefaultConstructionSets.sort
    runner.registerFinalCondition("The building finished with #{finishing_spaceTypes.size} space types and #{finishing_constructionSets.size} construction sets.")

    return true
  end
end