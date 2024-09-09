

###### (Automatically generated documentation)

# set_primary_kitchen_equipment

## Description
Measure adds specific primary kitchen equipment to kitchen space type based on user inputs. Primary kitchen equipment includes griddles, ovens, fryers, steamers, ranges, and stoves. Equipment can be either gas or electric based on user-specified inputs. Exisiting kitchen equipment will be removed, but new equipment will follow the same schedule as the equipment originally in the model.

## Modeler Description
Measure adds specific primary kitchen equipment to kitchen space type based on user inputs. Primary kitchen equipment includes griddles, ovens, fryers, steamers, ranges, and stoves. Equipment can be either gas or electric based on user-specified inputs. Exisiting kitchen equipment will be removed, but new equipment will follow the same schedule as the equipment originally in the model.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### cook_dining_type
Food service type in building; this will determine major cooking equipment distribution.
**Name:** cook_dining_type,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fuel_broiler
Fuel type of broilers in building. All broilers will be the same fuel type.
**Name:** cook_fuel_broiler,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_broilers_counts
Quantity of broilers in building.
**Name:** cook_broilers_counts,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fuel_griddle
Fuel type of griddles in building. All griddles will be the same fuel type.
**Name:** cook_fuel_griddle,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_griddles_counts
Quantity of griddles in building.
**Name:** cook_griddles_counts,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fuel_fryer
Fuel type of fryers in building. All fryer will be the same fuel type.
**Name:** cook_fuel_fryer,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fryers_counts
Quantity of fryer in building.
**Name:** cook_fryers_counts,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fuel_oven
Fuel type of oven in building. All oven will be the same fuel type.
**Name:** cook_fuel_oven,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_ovens_counts
Quantity of oven in building.
**Name:** cook_ovens_counts,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fuel_range
Fuel type of range in building. All range will be the same fuel type.
**Name:** cook_fuel_range,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_ranges_counts
Quantity of range in building.
**Name:** cook_ranges_counts,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_fuel_steamer
Fuel type of steamer in building. All steamer will be the same fuel type.
**Name:** cook_fuel_steamer,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### cook_steamers_counts
Quantity of steamer in building.
**Name:** cook_steamers_counts,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false




