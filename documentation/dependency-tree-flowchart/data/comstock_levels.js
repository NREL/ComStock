const famdata = [

  {id: 0, parents: [], title: 'year_of_simulation', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: ''},
  {id: 3, parents: [], title: 'climate_zone', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: ''},
  {id: 1, parents: [], title: 'rotation', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: ''},

  {id: 4, parents: [3], title: 'county_id', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: ''},

  {id: 5, parents: [4], title: 'building_type', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: 'Description of item here'},

  {id: 6, parents: [4], title: 'state_id', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: 'Description of item here'},

  {id: 301, parents: [5], title: 'heating_fuel', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd', description: 'Description of item here'},

  {id: 7, parents: [5], title: 'hvac_tst_htg_delta_f', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 8, parents: [5], title: 'hvac_tst_clg_delta_f', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 9, parents: [5], title: 'plugload_sch_base_peak_ratio_type', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 170, parents: [9, 5], title: 'plugload_sch_weekday_base_peak_ratio', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 171, parents: [9, 5], title: 'plugload_sch_weekend_base_peak_ratio', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 10, parents: [5], title: 'ltg_sch_base_peak_ratio_type', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 172, parents: [10, 5], title: 'ltg_sch_weekday_base_peak_ratio', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 173, parents: [10, 5], title: 'ltg_sch_weekend_base_peak_ratio', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 11, parents: [4, 5], title: 'number_stories', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 12, parents: [4, 5], title: 'year_built', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 174, parents: [12], title: 'year_bin_of_original_building_construction', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 175, parents: [0, 12], title: 'year_bin_of_last_exterior_lighting_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 176, parents: [0, 12], title: 'year_bin_of_last_hvac_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 177, parents: [0, 12], title: 'year_bin_of_last_interior_equipment_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 178, parents: [0, 12], title: 'year_bin_of_last_interior_lighting_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 179, parents: [0, 12], title: 'year_bin_of_last_roof_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 180, parents: [0, 12], title: 'year_bin_of_last_service_water_heating_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 181, parents: [0, 12], title: 'year_bin_of_last_walls_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 182, parents: [0, 12], title: 'year_bin_of_last_windows_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 13, parents: [4, 5], title: 'rentable_area', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 15, parents: [5, 23, 301], title: 'hvac_system_type', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 16, parents: [5, 301], title: 'service_water_heating_fuel', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 17, parents: [5], title: 'weekday_start_time', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 18, parents: [17], title: 'weekday_duration', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 19, parents: [5], title: 'weekend_start_time', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 20, parents: [19], title: 'weekend_duration', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 21, parents: [5], title: 'hvac_tst_htg_sp_f', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 22, parents: [5], title: 'hvac_tst_clg_sp_f', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 25, parents: [15], title: 'hvac_night_variability', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 23, parents: [6], title: 'region', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 156, parents: [6], title: 'energy_code_compliance_during_original_building_construction', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 157, parents: [6], title: 'energy_code_compliance_exterior_lighting', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 158, parents: [6], title: 'energy_code_compliance_hvac', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 159, parents: [6], title: 'energy_code_compliance_interior_equipment', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 160, parents: [6], title: 'energy_code_compliance_interior_lighting', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 161, parents: [6], title: 'energy_code_compliance_roof', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 162, parents: [6], title: 'energy_code_compliance_service_water_heating', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 163, parents: [6], title: 'energy_code_compliance_walls', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 164, parents: [6], title: 'energy_code_compliance_windows', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 152, parents: [5], title: 'building_subtype', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 153, parents: [5], title: 'building_shape', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 154, parents: [153], title: 'aspect_ratio', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 190, parents: [174, 6], title: 'energy_code_in_force_during_original_building_construction', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 191, parents: [175, 6], title: 'energy_code_in_force_during_last_exterior_lighting_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 192, parents: [176, 6], title: 'energy_code_in_force_during_last_hvac_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 193, parents: [177, 6], title: 'energy_code_in_force_during_last_interior_equipment_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 194, parents: [178, 6], title: 'energy_code_in_force_during_last_interior_lighting_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 195, parents: [179, 6], title: 'energy_code_in_force_during_last_roof_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 196, parents: [180, 6], title: 'energy_code_in_force_during_last_service_water_heating_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 197, parents: [181, 6], title: 'energy_code_in_force_during_last_walls_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 198, parents: [182, 6], title: 'energy_code_in_force_during_last_windows_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 200, parents: [190, 156], title: 'energy_code_followed_during_original_building_construction', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 202, parents: [191, 157], title: 'energy_code_followed_during_last_exterior_lighting_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 203, parents: [192, 158], title: 'energy_code_followed_during_last_hvac_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 204, parents: [193, 159], title: 'energy_code_followed_during_last_interior_equipment_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 205, parents: [194, 160], title: 'energy_code_followed_during_last_interior_lighting_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 206, parents: [195, 161], title: 'energy_code_followed_during_last_roof_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 207, parents: [196, 162], title: 'energy_code_followed_during_last_service_water_heating_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 208, parents: [197, 163], title: 'energy_code_followed_during_last_walls_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},
  {id: 209, parents: [198, 164], title: 'energy_code_followed_during_last_windows_replacement', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  {id: 201, parents: [190, 5, 13], title: 'window_wall_ratio', itemTitleColor: '#ddd', groupTitle: 'tsv', groupTitleColor: '#ddd'},

  // bldg stock

  {id: 27, parents: [172], title: 'ltg_sch_weekday_base_peak_ratio', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 28, parents: [173], title: 'ltg_sch_weekend_base_peak_ratio', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  /*{id: 120, parents: [10], title: 'ltg_sch_base_peak_ratio_type', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/
  /*{id: 24, parents: [156], title: 'energy_code_compliance_during_original_building_construction', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 110, parents: [157], title: 'energy_code_compliance_exterior_lighting', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 111, parents: [158], title: 'energy_code_compliance_hvac', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 112, parents: [159], title: 'energy_code_compliance_interior_equipment', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 113, parents: [160], title: 'energy_code_compliance_interior_lighting', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 114, parents: [161], title: 'energy_code_compliance_roof', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 115, parents: [162], title: 'energy_code_compliance_service_water_heating', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 116, parents: [163], title: 'energy_code_compliance_walls', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 117, parents: [164], title: 'energy_code_compliance_windows', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  {id: 130, parents: [200], title: 'energy_code_followed_during_original_building_construction', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  /*{id: 32, parents: [190], title: 'energy_code_in_force_during_original_building_construction', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  /*{id: 140, parents: [191], title: 'energy_code_in_force_during_last_exterior_lighting_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 141, parents: [192], title: 'energy_code_in_force_during_last_hvac_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 142, parents: [193], title: 'energy_code_in_force_during_last_interior_equipment_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 143, parents: [194], title: 'energy_code_in_force_during_last_interior_lighting_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 144, parents: [195], title: 'energy_code_in_force_during_last_roof_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 145, parents: [196], title: 'energy_code_in_force_during_last_service_water_heating_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 146, parents: [197], title: 'energy_code_in_force_during_last_walls_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 147, parents: [198], title: 'energy_code_in_force_during_last_windows_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  {id: 33, parents: [202], title: 'energy_code_followed_during_last_exterior_lighting_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 90, parents: [203], title: 'energy_code_followed_during_last_hvac_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 91, parents: [204], title: 'energy_code_followed_during_last_interior_equipment_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 92, parents: [205], title: 'energy_code_followed_during_last_interior_lighting_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 93, parents: [206], title: 'energy_code_followed_during_last_roof_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 94, parents: [207], title: 'energy_code_followed_during_last_service_water_heating_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 95, parents: [208], title: 'energy_code_followed_during_last_walls_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 96, parents: [209], title: 'energy_code_followed_during_last_windows_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  {id: 83, parents: [154], title: 'aspect_ratio', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  /*{id: 84, parents: [153], title: 'building_shape', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', placementType: primitives.AdviserPlacementType.Right, groupTitleColor: '#a7e3f4'},*/
  {id: 85, parents: [5], title: 'building_type', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 88, parents: [152], title: 'building_subtype', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 86, parents: [3], title: 'climate_zone', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 87, parents: [4], title: 'county_id', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  {id: 36, parents: [11], title: 'number_stories', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  /*{id: 38, parents: [9], title: 'plugload_sch_base_peak_ratio_type', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/
  {id: 39, parents: [170], title: 'plugload_sch_weekday_base_peak_ratio', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 40, parents: [171], title: 'plugload_sch_weekend_base_peak_ratio', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  {id: 127, parents: [301], title: 'heating_fuel', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  {id: 121, parents: [15], title: 'hvac_system_type', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 122, parents: [8], title: 'hvac_tst_clg_delta_f', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 123, parents: [22], title: 'hvac_tst_clg_sp_f', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 124, parents: [7], title: 'hvac_tst_htg_delta_f', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 125, parents: [21], title: 'hvac_tst_htg_sp_f', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 126, parents: [25], title: 'hvac_night_variability', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  /*{id: 42, parents: [23], title: 'region', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/
  {id: 43, parents: [13], title: 'rentable_area', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 44, parents: [1], title: 'rotation', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  {id: 45, parents: [16], title: 'service_water_heating_fuel', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  /*{id: 300, parents: [6], isVisible: false},*/

  /*{id: 46, parents: [6], title: 'state_id', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  {id: 47, parents: [18], title: 'weekday_duration', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 48, parents: [17], title: 'weekday_start_time', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 49, parents: [20], title: 'weekend_duration', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 50, parents: [19], title: 'weekend_start_time', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 51, parents: [201], title: 'window_wall_ratio', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},

  /*{id: 60, parents: [174], title: 'year_bin_of_original_building_construction', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  /*{id: 52, parents: [175], title: 'year_bin_of_last_exterior_lighting_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 53, parents: [176], title: 'year_bin_of_last_hvac_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 54, parents: [177], title: 'year_bin_of_last_interior_equipment_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 55, parents: [178], title: 'year_bin_of_last_interior_lighting_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 56, parents: [179], title: 'year_bin_of_last_roof_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 57, parents: [180], title: 'year_bin_of_last_service_water_heating_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 58, parents: [181], title: 'year_bin_of_last_walls_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},
  {id: 59, parents: [182], title: 'year_bin_of_last_windows_replacement', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  /*{id: 61, parents: [12], title: 'year_built', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', groupTitleColor: '#a7e3f4'},*/

  {id: 62, parents: [0], title: 'year_of_simulation', itemTitleColor: '#a7e3f4', groupTitle: 'BStock', description: '', groupTitleColor: '#a7e3f4'},

  // measures subs
  {id: 63, parents: [62], title: 'add_blinds_to_selected_windows', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 64, parents: [126], title: 'add_hvac_nighttime_operation_variability', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 65, parents: [122, 123, 124, 125], title: 'add_thermostat_setpoint_variability', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},

  {id: 66, parents: [62, 87], title: 'ChangeBuildingLocation', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},

  {
    id: 67,
    parents: [33, 36, 43, 44, 51, 90, 91, 92, 93, 94, 95, 96, 35, 43, 44, 51, 83, 85, 86, 88, 130, 202],
    title: 'create_bar_from_building_type_ratios',
    itemTitleColor: '#d1f7cd',
    groupTitle: 'measure',
    groupTitleColor: '#d1f7cd'
  },
  {
    id: 68,
    parents: [33, 45, 47, 48, 49, 50, 90, 91, 92, 93, 94, 95, 96, 35, 36, 45, 47, 48, 49, 50, 86, 121, 130],
    title: 'create_typical_building_from_model',
    itemTitleColor: '#d1f7cd',
    groupTitle: 'measure',
    groupTitleColor: '#d1f7cd'
  },

  {id: 69, parents: [39, 40], title: 'set_electric_equipment_bpr', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 70, parents: [33, 86, 90, 97, 131], title: 'set_exterior_lighting_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 71, parents: [127], title: 'set_heating_fuel', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 72, parents: [86, 90, 132], title: 'set_hvac_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 73, parents: [86, 99], title: 'set_interior_equipment_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 74, parents: [27, 28], title: 'set_interior_lighting_bpr', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 75, parents: [86, 92], title: 'set_interior_lighting_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 76, parents: [86, 93, 101], title: 'set_roof_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', placementType: primitives.AdviserPlacementType.Right, groupTitleColor: '#d1f7cd'},
  {id: 77, parents: [45], title: 'set_service_water_heating_fuel', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 78, parents: [86, 94, 102], title: 'set_service_water_heating_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 79, parents: [62], title: 'set_space_type_load_subcategories', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 80, parents: [86, 95, 103], title: 'set_wall_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},
  {id: 81, parents: [86, 96], title: 'set_window_template', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'},

  {id: 82, parents: [62], title: 'simulation_settings', itemTitleColor: '#d1f7cd', groupTitle: 'measure', groupTitleColor: '#d1f7cd'}

];
