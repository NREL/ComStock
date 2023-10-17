

###### (Automatically generated documentation)

# Set NIST Infiltration Correlations

## Description
This measure incorporates infiltration that varies with weather and HVAC operation, and takes into account building geometry (height, above-ground exterior surface area, and volume). It is based on work published by Ng et al. (2018) <a href='https://doi.org/10.1016/j.buildenv.2017.10.029'>'Weather correlations to calculate infiltration rates for U.S. commercial building energy models'</a> and Ng et al. (2021) <a href='https://doi.org/10.1016/j.buildenv.2021.107783'>'Evaluating potential benefits of air barriers in commercial buildings using NIST infiltration correlations in EnergyPlus'</a>. This method of calculating infiltration was developed using eleven of the DOE commercial prototype building models (<a href='https://www.energycodes.gov/development/commercial/prototype_models'>Goel et al. 2014</a>) and TMY3 weather files for eight climate zones (CZ). Guidance on implementing the infiltration correlations are explained in the NIST technical report <a href='https://doi.org/10.6028/NIST.TN.2221'>'Implementing NIST Infiltration Correlations'</a>. Ng et al. (2018) shows that when analyzing the benefits of building envelope airtightening, greater HVAC energy savings were predicted using the infiltration inputs included in this Measure compared with using the default inputs that are included in the prototype building models. Brian Polidoro (NIST) first developed this Measure in 2015 and updated it in 2018 and 2019. Matthew Dahlhausen (NREL) updated the 2019 Measure and published this current version in 2023. To provide feedback on the NIST infiltration correlations, please email infiltration@list.nist.gov or lisa.ng@nist.gov. For measure implementation questions or issues, contact matthew.dahlhausen@nrel.gov.

## Modeler Description
This measure will remove any existing infiltration objects (OS:SpaceInfiltration:DesignFlowRate and OS:SpaceInfiltration:EffectiveLeakageArea). Every zone will then get two OS:SpaceInfiltration:DesignFlowRate objects that add infiltration using the 'Flow per Exterior Surface Area' input option, one infiltration object when the HVAC system is on and one object when the HVAC system is off. The method assumes that HVAC operation is set by a schedule, though it may not reflect actual simulation/operation when fan operation may depend on internal loads and temperature setpoints. By default, interior zones will receive no infiltration. The user may enter a design building envelope airtightness at a specific design pressure, and whether the design value represents a 4-sided, 5-sided, or 6-sided normalization.  By default, the measure assumes an airtightness design value of 13.8 (m^3/h-m^2) at 75 Pa. The measure assumes that infiltration is evenly distributed across the entire building envelope, including the roof. The user may select the HVAC system operating schedule in the model, or infer it based on the availability schedule of the air loop that serves the largest amount of floor area. The measure will make a copy of the HVAC operating schedule, 'Infiltration HVAC On Schedule', which is used with the HVAC on infiltration correlations.  The measure will also make an 'Infiltration HVAC Off Schedule' with inverse operation, used with the HVAC off infiltration correlations. OS:SpaceInfiltration:DesignFlowRate object coefficients (A, B, C, and D) come from Ng et al. (2018). The user may select the Building Type and Climate Zone, or the measure will infer them from the model.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Airtightness design value (m^3/h-m^2)
The airtightness design value from a building pressurization test. Use 5.0 (m^3/h-m^2) as a default for buildings with air barriers. Convert (cfm/ft^2) to (m^3/h-m^2) by multiplying by 18.288 (m-min/ft-hr). (0.3048 m/ft)*(60 min/hr) = 18.288 (m-min/ft-hr).
**Name:** airtightness_value,
**Type:** Double,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Airtightness design pressure (Pa)
The corresponding pressure for the airtightness design value, typically 75 Pa for commercial buildings and 50 Pa for residential buildings.
**Name:** airtightness_pressure,
**Type:** Double,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Airtightness exterior surface area scope
Airtightness measurements are weighted by exterior surface area. 4-sided values divide infiltration by exterior wall area.  5-sided values additionally include roof area. 6-sided values additionally include floor and ground area.
**Name:** airtightness_area,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** false

**Choice Display Names** ["4-sided", "5-sided", "6-sided"]


### Does the building have an air barrier?
Buildings with air barriers use a different set of coefficients.
**Name:** air_barrier,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### HVAC Operating Schedule
Choose the HVAC Operating Schedule for the building. The schedule must be a Schedule Constant or Schedule Ruleset object. Lookup From Model will use the operating schedule from the largest airloop by floor area served. If the largest airloop serves less than 5% of the building, the measure will attempt to use the Building Hours of Operation schedule instead.
**Name:** hvac_schedule,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### Climate Zone
Specify the ASHRAE climate zone. CEC climate zones are not supported.
**Name:** climate_zone,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** false

**Choice Display Names** ["1A", "1B", "2A", "2B", "3A", "3B", "3C", "4A", "4B", "4C", "5A", "5B", "5C", "6A", "6B", "7A", "8A", "Lookup From Model"]


### Building Type
If the building type is not available, pick the one with the most similar geometry and exhaust fan flow rates.
**Name:** building_type,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** false

**Choice Display Names** ["SecondarySchool", "PrimarySchool", "SmallOffice", "MediumOffice", "SmallHotel", "LargeHotel", "RetailStandalone", "RetailStripmall", "Hospital", "MidriseApartment", "HighriseApartment", "Lookup From Model"]






