

###### (Automatically generated documentation)

# swh_elec_storage_eff

## Description
This measure improves the Energy Factor of small electric water heaters with a value defined by the user.

## Modeler Description
This measure goes each water heater, if it finds a small (<12kW, <50gal, as defined on the MICS database), electric non-heatpump water heater it checks its Energy Factor.
            The equations for calculating EF through UA are listed here:
            http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf (Appendix A: Service Water Heating).
            If the current EF is lower than the chosen one, UA is changed accordingly to increase the EF of the water heater.
            The new UA is calculated using the equations here:
            https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/Standards.WaterHeaterMixed.rb#L90-L102
            Basically RE and EF are related by a regression equations, then the same equation listed in the above PNNL document is employed.  

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Energy Factor Choice:

**Name:** ef_choice,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false




