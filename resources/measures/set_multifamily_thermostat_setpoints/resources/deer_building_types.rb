# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# Defines the mapping between the abbreviations used for building type
# and HVAC in DEER to user-readable names.
module DEERBuildingTypes
  # Building type abbreviation to long name map
  def building_type_to_long
    return {
      'Asm' => 'Assembly',
      'DMo' => 'Residential Mobile Home',
      'ECC' => 'Education - Community College',
      'EPr' => 'Education - Primary School',
      'ERC' => 'Education - Relocatable Classroom',
      'ESe' => 'Education - Secondary School',
      'EUn' => 'Education - University',
      'GHs' => 'Greenhouse',
      'Gro' => 'Grocery',
      'Hsp' => 'Health/Medical - Hospital',
      'Htl' => 'Lodging - Hotel',
      'MBT' => 'Manufacturing Biotech',
      'MFm' => 'Residential Multi-family',
      'MLI' => 'Manufacturing Light Industrial',
      'Mtl' => 'Lodging - Motel',
      'Nrs' => 'Health/Medical - Nursing Home',
      'OfL' => 'Office - Large',
      'OfS' => 'Office - Small',
      'RFF' => 'Restaurant - Fast-Food',
      'RSD' => 'Restaurant - Sit-Down',
      'Rt3' => 'Retail - Multistory Large',
      'RtL' => 'Retail - Single-Story Large',
      'RtS' => 'Retail - Small',
      'SCn' => 'Storage - Conditioned',
      'SFm' => 'Residential Single Family',
      'SUn' => 'Storage - Unconditioned',
      'WRf' => 'Warehouse - Refrigerated'
    }
  end

  # Building template to vintage abbreviation
  # vintages beyond 2020 use 2020 values for thermostat setpoints
  def template_to_vintage
    return {
      'DEER Pre-1975' => '1975',
      'DEER 1985' => '1985',
      'DEER 1996' => '1996',
      'DEER 2003' => '2003',
      'DEER 2007' => '2007',
      'DEER 2011' => '2011',
      'DEER 2014' => '2014',
      'DEER 2015' => '2015',
      'DEER 2017' => '2017',
      'DEER 2020' => '2020',
      'DEER 2025' => '2020',
      'DEER 2030' => '2020',
      'DEER 2035' => '2020',
      'DEER 2040' => '2020',
      'DEER 2045' => '2020',
      'DEER 2050' => '2020',
      'DEER 2055' => '2020',
      'DEER 2060' => '2020',
      'DEER 2065' => '2020',
      'DEER 2070' => '2020',
      'DEER 2075' => '2020'
    }
  end

  # Building climate zone to climate zone abbreviation
  def climate_zone_to_short
    return {
        'CEC T24-CEC1' => 'CZ01',
        'CEC T24-CEC2' => 'CZ02',
        'CEC T24-CEC3' => 'CZ03',
        'CEC T24-CEC4' => 'CZ04',
        'CEC T24-CEC5' => 'CZ05',
        'CEC T24-CEC6' => 'CZ06',
        'CEC T24-CEC7' => 'CZ07',
        'CEC T24-CEC8' => 'CZ08',
        'CEC T24-CEC9' => 'CZ09',
        'CEC T24-CEC10' => 'CZ10',
        'CEC T24-CEC11' => 'CZ11',
        'CEC T24-CEC12' => 'CZ12',
        'CEC T24-CEC13' => 'CZ14',
        'CEC T24-CEC14' => 'CZ14',
        'CEC T24-CEC15' => 'CZ15',
        'CEC T24-CEC16' => 'CZ16'
    }
  end
end
