

###### (Automatically generated documentation)

# refrig_compressors

## Description
This measure substitutes refrigeration compressor curves with more efficient ones.

## Modeler Description
This measures looks for refrigeration compressors, checks the efficiency level and changes the curves with more efficient ones.
            - It starts looping through each refrigeration system.
            - For each of them it checks if it is Low Temperature or Medium Temperature, checking the operating temperature of a refrigeration case or walkin.
            - It checks what is the refrigerant for the system. This measure works only for the following refrigerants: 507, 404a, R22.
            - It extracts the compressors from the JSON file, corresponding to the appropriate system type (LT/MT) and refrigerant.
            - The following compressors were employed (https://climate.emerson.com/online-product-information/OPIServlet):
                  MT:  404 -> Copeland ZS33KAE-PFV (single phase, 200/240 V, 60HZ)
                       507 -> Copeland ZS33KAE-PFV (single phase, 200/240 V, 60HZ)
                       R22 -> Copeland CS18K6E-PFV (single phase, 200/240 V, 60HZ)
                  LT:  404 -> Copeland RFT32C1E-CAV (single phase, 200/240 V, 60HZ)
                       507 -> Copeland ZF15K4E-PFV (single phase, 200/240 V, 60HZ)
                       R22 -> Copeland LAHB-0311-CAB (single phase, 200/240 V, 60HZ)
               The EER for each compressor is listed in the JSON file.
            - Then the current compressors listed in the model are analyzed. The EERs are calculated and the average EER for the whole compressor rack is calculated.
            - If the average current EER is lower than the referenced EER in the JSON file, the compressors in the system are stripped away.
            - The total compressor capacity is calculated and the proper number of new, more efficient compressors is added to the system.
            - The EER and the total compressor capacities are calculated using power and capacity curves at the rating conditions (http://www.ahrinet.org/App_Content/ahri/files/STANDARDS/AHRI/AHRI_Standard_540_I-P_and_SI_2015.pdf).

## Measure Type
ModelMeasure

## Taxonomy


## Arguments




This measure does not have any user arguments


