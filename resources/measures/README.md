# ComStock Workflow and Upgrade Measures

There are **TWO** measure directories on this GitHub repository.
This measure repository is for workflow and upgrade measures that require input arguments defined in the [`options_lookup.tsv`](https://github.com/NREL/ComStock/blob/develop/resources/options_lookup.tsv).

Meta and reporting measures are located under [`measures/`](https://github.com/NREL/ComStock/tree/main/measures).

# Workflow Measures
Measures are added to the workflow in order they first appear in the [`options_lookup.tsv`](https://github.com/NREL/ComStock/blob/develop/resources/options_lookup.tsv) (Additional arguments may be passed to a measure later in the `options_lookup.tsv`, but the order depends on the order of first appearance).

## Baseline Workflow Steps

| Measure Name                             | Measure Actions |
|------------------------------------------|-----------------|
| ChangeBuildingLocation                   | Sets the weather file |
| simulation_settings                      | Modifies year and start day of week to match weather files |
| create_bar_from_building_type_ratios     | Makes geometry and assigns stub space types |
| create_typical_building_from_model       | Add space types with lights, people, equipment, and ventilation requirements per template of original construction |
|                                          | Add schedules for all space types and associated loads |
|                                          | Add constructions and set properties per template of original construction |
|                                          | Add elevators |
|                                          | Add exterior lights |
|                                          | Add zone exhaust fans |
|                                          | Add SWH |
|                                          | Add daylighting controls |
|                                          | Add refrigeration |
|                                          | Add internal mass |
|                                          | Add thermostat for zones based on associated space types |
|                                          | Add HVAC system with default efficiencies and properties |
|                                          | Modify the schedules to match new hours of operation |
|                                          | Apply 90.1 PRM sizing parameters |
|                                          | Do a sizing run, which populates the SQL file with the EnergyPlus-calculated capacities and flows |
|                                          | Reset minimum damper positions for VAV systems per 62.1 VRP |
|                                          | Apply DOE prototype HVAC assumptions, which sets fan pressure rises and efficiencies based on flow rates, pump part-load curves, and economizer types |
|                                          | Apply HVAC controls and efficiencies per template of original construction based on equipment capacities and flow rates |
|                                          | Remove unused objects from the model |
| set_wall_template                        | Updates wall construction properties if template is newer than the template of original construction |
| set_roof_template                        | Updates roof construction properties if template is newer than the template of original construction |
| set_exterior_lighting_template           | Updates exterior lighting properties if template is newer than the template of original construction |
| set_interior_equipment_template          | Updates interior equipment properties if template is newer than the template of original construction |
| set_service_water_heating_template       | Updates SWH equipment efficiencies and controls if template is newer than the template of original construction |
| set_hvac_template                        | Move to next measure unless template is newer than template of original construction |
|                                          | Do a sizing run, which populates the SQL file with the EnergyPlus-calculated capacities and flows 
|                                          | Updates HVAC equipment efficiencies and controls based on updated equipment sizes. |
| add_blinds_to_selected_windows           | For CA buildings only, adds blinds to a fraction of the windows in the model based on building type |
| prototype_space_type_assignment          | Adds AdditionalProperties info to space types. No changes to EnergyPlus model inputs. |
| set_space_type_load_subcategories        | Adds subcategory names to interior lights and plug loads for reporting purposes. No changes to model results. |
| set_service_water_heating_fuel           | If service water heating fuel is fuel oil or propane, changes natural gas water heaters to this fuel. If service water heating fuel is district heating, changes electric water heaters to this fuel. No change for models with electricity or natural gas SWH fuel (most models) |
| set_heating_fuel                         | If space heating fuel is fuel oil or propane, changes natural gas coils and boilers to this fuel. No change for models with other fuel types (most models). |
| set_interior_lighting_technology         | Replaces interior lighting in model (originally based on code) with lighting based on a specific technology type (T12, LED, etc.) |
| set_interior_lighting_bpr                | Changes the base-to-peak ratio for interior lighting schedules, which modifies night-time lighting operation. |
| set_electric_equipment_bpr               | Changes the base-to-peak ratio for interior equipment schedules, which modifies night-time plug load operation. |
| add_hvac_nighttime_operation_variability | Sets nighttime fan and OA behavior, which may modify operation or OA damper schedules from those previously applied by a standard. |
| set_nist_infiltration_correlations       | Sets infiltration rates, coefficients, and schedules based on NIST-derived data. |
| add_thermostat_setpoint_variability      | Modifies the heating and cooling setpoints and setbacks/setups. |
| set_primary_kitchen_equipment            | Replaces kitchen equiment with discrete equipment assumptions |
| replace_baseline_windows                 | Replaces windows in model (originally based on code) with windows of a specific technology type (single-pane, double-pane, etc.) |
| hardsize_model                           | Do a sizing run, which populates the SQL file with the EnergyPlus-calculated capacities and flows |
|                                          | Hard-size HVAC and SWH equipment in the model based on EnergyPlus-calculated capacities and flows. No model changes from here forward will be reflected in the sizing of HVAC equipment unless done intentionally as part of an upgrade. |
| fault_hvac_economizer_damper_stuck       | Models a stuck economizer damper fault |
| fault_hvac_economizer_changeover_temperature | Models an economizer changeover temperature fault |

# Upgrade Measures
Upgrade measures are tagged with `upgrade_`. Full measures descriptions are available on the [ComStock website](https://nrel.github.io/ComStock.github.io/docs/resources/references/upgrade_measures/upgrade_measures.html).
