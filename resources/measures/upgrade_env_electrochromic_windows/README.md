

###### (Automatically generated documentation)

# Electrochromic Windows Modulating

## Description
Adds electrochromic windows. SHGC and VLT will modulate linearly between specified clear and tinted properties.

## Modeler Description
Adds electrochromic windows. SHGC and VLT will modulate linearly between specified clear and tinted properties.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Dynamic SGS Upgrade
Identify electrochromic secondary glazing technology to be applied to entire building.
**Name:** dynamic_sgs_upgrade,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### U-value (Btu/h·ft2·°F)
Replaces u-value of existing applicable windows with this value. Use IP units.
**Name:** u_value,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Maximum Allowable Radiation (W/m^2)
Windows will switch to a darker state if threshold is exceeded.
**Name:** max_rad_w_per_m2,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Maximum Allowable Glare Index
Sets maximum glare index allowance for EC windows.
**Name:** gi,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Minimum Temperature for EC Tinting (F)
Sets minimum temperature to allow for EC tinting. A low value will mitigate heating penalties.
**Name:** min_temp,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Prioritize Glare Or Temperature?
Select whether to prioritize glare or outdoor temperature when deciding EC state.
**Name:** ec_priority_logic,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Apply electrochromic glazing to North facade windows.

**Name:** North,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false

### Apply electrochromic glazing to East facade windows.

**Name:** East,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false

### Apply electrochromic glazing to South facade windows.

**Name:** South,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false

### Apply electrochromic glazing to West facade windows.

**Name:** West,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false




