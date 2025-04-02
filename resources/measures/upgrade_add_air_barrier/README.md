

###### (Automatically generated documentation)

# AddAirBarrier

## Description
This measure incorporates infiltration that varies with weather and HVAC operation, and takes into account building geometry (height, above-ground exterior surface area, and volume). It is based on work published by Ng et al. (2018) 'Weather correlations to calculate infiltration rates for U.S. commercial building energy models' and Ng et al. (2021) 'Evaluating potential benefits of air barriers in commercial buildings using NIST infiltration correlations in EnergyPlus'. This method of calculating infiltration was developed using eleven of the DOE commercial prototype building models (Goel et al. 2014) and TMY3 weather files for eight climate zones (CZ). Guidance on implementing the infiltration correlations are explained in the NIST technical report 'Implementing NIST Infiltration Correlations'. Ng et al. (2018) shows that when analyzing the benefits of building envelope airtightening, greater HVAC energy savings were predicted using the infiltration inputs included in this Measure compared with using the default inputs that are included in the prototype building models. Brian Polidoro (NIST) first developed this Measure in 2015 and updated it in 2018 and 2019. Matthew Dahlhausen (NREL) updated the 2019 Measure and published this current version in 2023. To provide feedback on the NIST infiltration correlations, please email infiltration@list.nist.gov or lisa.ng@nist.gov. For measure implementation questions or issues, contact matthew.dahlhausen@nrel.gov.

## Modeler Description
This measure will remove any existing infiltration objects (OS:SpaceInfiltration:DesignFlowRate and OS:SpaceInfiltration:EffectiveLeakageArea). Every zone will then get two OS:SpaceInfiltration:DesignFlowRate objects that add infiltration using the 'Flow per Exterior Surface Area' input option, one infiltration object when the HVAC system is on and one object when the HVAC system is off. The method assumes that HVAC operation is set by a schedule, though it may not reflect actual simulation/operation when fan operation may depend on internal loads and temperature setpoints. By default, interior zones will receive no infiltration. The user may enter a design building envelope airtightness at a specific design pressure, and whether the design value represents a 4-sided, 5-sided, or 6-sided normalization.  By default, the measure assumes an airtightness design value of 13.8 (m^3/h-m^2) at 75 Pa. The measure assumes that infiltration is evenly distributed across the entire building envelope, including the roof. The user may select the HVAC system operating schedule in the model, or infer it based on the availability schedule of the air loop that serves the largest amount of floor area. The measure will make a copy of the HVAC operating schedule, 'Infiltration HVAC On Schedule', which is used with the HVAC on infiltration correlations.  The measure will also make an 'Infiltration HVAC Off Schedule' with inverse operation, used with the HVAC off infiltration correlations. OS:SpaceInfiltration:DesignFlowRate object coefficients (A, B, C, and D) come from Ng et al. (2018). The user may select the Building Type and Climate Zone, or the measure will infer them from the model.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments




This measure does not have any user arguments



