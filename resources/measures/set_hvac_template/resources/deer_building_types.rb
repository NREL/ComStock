# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
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

  # HVAC type abbreviation to long name map
  def hvac_sys_to_long
    return {
      'DXGF' => 'Split or Packaged DX Unit with Gas Furnace',
      'DXEH' => 'Split or Packaged DX Unit with Electric Heat',
      'DXHP' => 'Split or Packaged DX Unit with Heat Pump',
      'WLHP' => 'Water Loop Heat Pump',
      'NCEH' => 'No Cooling with Electric Heat',
      'NCGF' => 'No Cooling with Gas Furnace',
      'PVVG' => 'Packaged VAV System with Gas Boiler',
      'PVVE' => 'Packaged VAV System with Electric Heat',
      'SVVG' => 'Built-Up VAV System with Gas Boiler',
      'SVVE' => 'Built-Up VAV System with Electric Reheat',
      'Unc' => 'No HVAC (Unconditioned)',
      'PTAC' => 'Packaged Terminal Air Conditioner',
      'PTHP' => 'Packaged Terminal Heat Pump',
      'FPFC' => 'Four Pipe Fan Coil',
      'DDCT' => 'Dual Duct System',
      'EVAP' => 'Evaporative Cooling with Separate Gas Furnace'
    }
  end

  # Valid building type/hvac type combos
  def building_type_to_hvac_systems
    return {
      'Asm' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'ECC' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'EPr' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'WLHP'
      ],
      'ERC' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'ESe' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'EUn' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG'
      ],
      'Gro' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'Hsp' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG'
      ],
      'Nrs' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'FPFC',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG'
      ],
      'Htl' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'Mtl' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'MBT' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'MFm' => [
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'MLI' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'OfL' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'OfS' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'RFF' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'RSD' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'Rt3' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF',
        'PVVE',
        'PVVG',
        'SVVE',
        'SVVG',
        'WLHP'
      ],
      'RtL' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'RtS' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'SCn' => [
        'DXEH',
        'DXGF',
        'DXHP',
        'NCEH',
        'NCGF'
      ],
      'SUn' => ['Unc'],
      'WRf' => ['DXGF']
    }
  end
end
