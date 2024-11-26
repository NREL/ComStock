

###### (Automatically generated documentation)

# ChangeBuildingLocation

## Description


## Modeler Description


## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Weather File Name
Name of the weather file to change to. This is the filename with the extension (e.g. NewWeather.epw). Optionally this can include the full file path, but for most use cases should just be file name.
**Name:** weather_file_name,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Weather File Year
Year of the weather file to use.
**Name:** year,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Climate Zone.

**Name:** climate_zone,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Grid Region
Cambium electric grid region, or eGrid region for Alaska and Hawaii
**Name:** grid_region,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Soil Conductivity

**Name:** soil_conductivity,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false




