

###### (Automatically generated documentation)

# upgrade_hvac_rtu_adv

## Description
replaces exisiting RTUs with top-of-the-line RTUs in the current (as of 7/30/2025) market. Improvements are from increased rated efficiencies, off-rated performances, and part-load performances.

## Modeler Description
The high-efficiency RTU measure is applicable to ComStock models with either gas furnace RTUs (“PSZ-AC with gas coil”), electric resistance RTUs (“PSZ-AC with electric coil”), gas boilers (“PSZ-AC with gas boiler”), or district heating (“PSZ-AC with district hot water”). This analysis includes only products that meet or exceed current building energy codes while representing the highest-performing models available on the market today. If the building currently uses gas for space heating, the upgraded RTU will be equipped with a gas furnace. If the building uses electricity for space heating, the RTU will include electric resistance heating. Heat/Energy Recovery Ventilator (H/ERVs) can be included in this measure, and the implementation and modeling will follow the approach used in previous H/ERV work. Demand Control Ventilation (DCV) can be included in this measure, and the implementation and modeling will follow the approach used in previous DCV work.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Add Energy Recovery?

**Name:** hr,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add Demand Control Ventilation?

**Name:** dcv,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Enable Debugging Outputs?

**Name:** debug_verbose,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false






