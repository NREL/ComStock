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

# Maps the DEER vintages to year ranges
module DEERVintages
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

  # Age range to DEER template
  def template_to_age_range
    return {
      'DEER Pre-1975' => 'Before 1978',
      'DEER 1985' => '1978-1992',
      'DEER 1996' => '1993-2001',
      'DEER 2003' => '2002-2005',
      'DEER 2007' => '2006-2009',
      'DEER 2011' => '2010-2013',
      'DEER 2014' => '2014',
      'DEER 2015' => '2015-2016',
      'DEER 2017' => '2017 or Later'
    }
  end
end
