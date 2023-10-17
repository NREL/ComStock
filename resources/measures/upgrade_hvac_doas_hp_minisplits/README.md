

###### (Automatically generated documentation)

# hvac_doas_hp_minisplits

## Description
TODO

## Modeler Description
TODO

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Building Maximum Area for Applicability, SF
Maximum building size for applicability of measure. Mini-split heat pumps are often only appropriate for small commerical applications, so it is recommended to keep this value under 20,000sf.
**Name:** area_limit_sf,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### DOAS Heating Fuel Source
Heating fuel source for DOAS, either gas furnace or electric resistance. DOAS will provide minimal preheating to provide reasonable nuetral air supplied to zone. The ERV/HRV will first try to accomodate this, with the heating coil addressing any additional load. Note that the zone heat pumps are still responsible for maintaining thermostat setpoints.
**Name:** doas_htg_fuel,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

**Choice Display Names** ["gas_furnace", "electric_resistance"]


### Maximum Performance Oversizing Factor
When heating design load exceeds cooling design load, the design cooling capacity of the unit will only be allowed to increase up to this factor to accomodate additional heating capacity. Oversizing the compressor beyond 25% can cause cooling cycling issues, even with variable speed compressors. Set this value to 10 if you do not want a limit placed on oversizing, noting that backup heat may still occur if the design temperature is below the compressor cutoff temperature of -15F.
**Name:** performance_oversizing_factor,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false






