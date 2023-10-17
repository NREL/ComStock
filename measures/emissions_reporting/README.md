

###### (Automatically generated documentation)

# Emissions Reporting

## Description
This measure calculates annual and hourly CO2e emissions from a model.

## Modeler Description
This measure calculates the hourly CO2e emissions for a model given an electricity grid region and emissions scenario.  Hourly emissions data comes from the Cambium dataset.  Grid regions and emissions scenarios are detailed in the Cambium documentation.  The measure also calculates annual CO2e emissions from annual eGrid factors for comparison.

## Measure Type
ReportingMeasure

## Taxonomy


## Arguments


### Grid Region
Cambium electric grid region, or eGrid region for Alaska and Hawaii
**Name:** grid_region,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

**Choice Display Names** ["AZNMc", "AKGD", "AKMS", "CAMXc", "ERCTc", "FRCCc", "HIMS", "HIOA", "MROEc", "MROWc", "NEWEc", "NWPPc", "NYSTc", "RFCEc", "RFCMc", "RFCWc", "RMPAc", "SPNOc", "SPSOc", "SRMVc", "SRMWc", "SRSOc", "SRTVc", "SRVCc", "Lookup from model"]


### U.S. State

**Name:** grid_state,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

**Choice Display Names** ["AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "PR", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY", "Lookup from model"]


### Emissions Scenario
Cambium emissions scenario to use for hourly emissions calculation
**Name:** emissions_scenario,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

**Choice Display Names** ["AER_95DecarbBy2035", "AER_95DecarbBy2050", "AER_HighRECost", "AER_LowRECost", "AER_MidCase", "LRMER_95DecarbBy2035_15", "LRMER_95DecarbBy2035_30", "LRMER_95DecarbBy2035_15_2025start", "LRMER_95DecarbBy2035_25_2025start", "LRMER_95DecarbBy2050_15", "LRMER_95DecarbBy2050_30", "LRMER_HighRECost_15", "LRMER_HighRECost_30", "LRMER_LowRECost_15", "LRMER_LowRECost_30", "LRMER_LowRECost_15_2025start", "LRMER_LowRECost_25_2025start", "LRMER_MidCase_15", "LRMER_MidCase_30", "LRMER_MidCase_15_2025start", "LRMER_MidCase_25_2025start", "All"]





