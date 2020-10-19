

###### (Automatically generated documentation)

# swh_gas_storage_eff

## Description
This measure improves the Energy Factor of small gas water heaters with a value defined by the user.

## Modeler Description
This measure goes each water heater, if it finds a small (<75BTU/h, <50gal, as defined on the MICS database), natural gas water heater it checks its Energy Factor (using calculate_ef(ua_btu_h_per_F, q_btu_h)).
            The equations for calculating EF through UA and vice-versa are listed here:
            http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf (Appendix A: Service Water Heating).
            If the current EF is lower than the chosen one, UA is changed accordingly to increase the EF of the water heater (using calculate_ua(ef, q_btu_h)).
            The RE formula has been taken from here:
            https://github.com/NREL/openstudio-standards/blob/95fe2261b63e5b3db2a230c9712f1dac224e1b67/lib/openstudio-standards/standards/necb/NECB2011/service_water_heating.rb 

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




