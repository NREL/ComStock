

###### (Automatically generated documentation)

# swh_hpwh

## Description
This measure swaps electric water heaters with HeatPump water heaters.

## Modeler Description
This measure goes each water heater, if it finds a small (<50gal, as defined on the MICS database), electric non-heatpump water heater, it calculates the COP corresponding to a EF=3.5

            The equations for calculating EF and UA are listed here:
            http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf (Appendix A: Service Water Heating).
            https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/Standards.WaterHeaterMixed.rb#L90-L102
            First a UA corresponding to a high EF for a standard electric SWH is calculated.
            With that UA value and a EF=3.5 (as listed in common commercially available HP water heaters), the water heater thermal efficiency (corresponding to the COP in this case) is calculated,
            through eq. on line 102 in the github page.
            This number is used for the COP in the partial-load curve assigned to the new HP water heater.
            https://www.energystar.gov/productfinder/product/certified-water-heaters/?formId=0d5ff0a5-d583-4bb4-a6d5-76436de5b169&scrollTo=9&search_text=&fuel_filter=&type_filter=Heat+Pump&brand_name_isopen=&input_rate_thousand_btu_per_hour_isopen=&markets_filter=United+States&zip_code_filter=&product_types=Select+a+Product+Category&sort_by=uniform_energy_factor_uef&sort_direction=DESC&currentZipCode=80401&page_number=0&lastpage=0

## Measure Type
ModelMeasure

## Taxonomy


## Arguments




This measure does not have any user arguments


