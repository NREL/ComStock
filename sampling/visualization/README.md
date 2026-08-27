# Sampling TSV visualizations

Interactive viewers built directly from the sampling TSVs in `sampling/tsvs/tsvs-v*.zip`.
Each generator embeds its distributions in a single self-contained HTML file — no server, no
network access, no external libraries.

- [Building operating hours](#building-operating-hours) — `generate_operating_hours_viz.py`
- [Energy code at last HVAC replacement](#energy-code-at-last-hvac-replacement) — `generate_energy_code_viz.py`

Both scripts share helpers from `generate_operating_hours_viz.py`, so run them from this
directory (or with it on `PYTHONPATH`).

## Building operating hours

`generate_operating_hours_viz.py` builds a single self-contained HTML file showing, for each
building type, the distribution of **start time** and **end time** on weekdays and weekends.

It reads four TSVs out of the chosen archive:

| TSV | Dependencies | Options |
| --- | --- | --- |
| `weekday_start_time` / `weekend_start_time` | `building_type` | start hour of day |
| `weekday_duration` / `weekend_duration` | `building_type`, `<daytype>_start_time` | operating hours |

End time is `start time + duration`, so the end-time distribution for a building type is the
start-weighted mixture of the conditional duration distributions:

```
P(end = e | building_type) = Σ_s P(start = s) · P(duration = e − s | s)
```

### Running

```bash
conda activate comstockpostproc312
```

```bash
python sampling/visualization/generate_operating_hours_viz.py
```

With no arguments it uses the highest-numbered `tsvs-v*.zip` in `sampling/tsvs` and writes
`sampling/visualization/operating_hours_<version>.html`. Options:

- `--version v33` — pick a specific TSV version
- `--zip path/to/tsvs-v33.zip` — point at an archive anywhere on disk
- `--out viewer.html` — choose the output path

Open the resulting HTML in any browser; it has no external dependencies and works offline.

### Using the viewer

- **Building type** dropdown drives all four charts.
- The **end-time chart defaults to the total distribution**, weighted across every start time.
- **Hover a start-time bar** to replace it with the end-time distribution conditional on that
  start time; the dashed outline keeps the total visible for comparison. **Click** to pin the
  selection, arrow keys step between start times, <kbd>Esc</kbd> clears it.
- **KDE bandwidth** controls the Gaussian kernel density estimate overlaid on each histogram.
  The KDE is a density, scaled by the 15-minute bin width so it shares the bars' y-axis.
- Stats under each chart are probability-weighted mean, median and p10–p90; `mean duration`
  respects the current start-time selection.

### A note on data gaps

A handful of `(building_type, start_time)` pairs in the source TSVs have a non-zero start
probability but an all-zero duration row — the sampler can pick that start time, but there is no
duration distribution behind it. That mass cannot be placed on the end-time axis, so:

- the generator logs these pairs at `WARNING` when it runs,
- the end-time mixture is renormalized over the start times that *do* have duration data, and
  the excluded share is reported under the end-time chart,
- selecting such a start time shows an explicit "no duration distribution" message instead of an
  empty plot.

In `tsvs-v33` this affects 6 weekday and 12 weekend pairs; the largest single one is
`library` @ 8:30 AM on weekends, at 2.8% of that building type.

### Editing

The page markup, CSS and JavaScript live in `operating_hours_template.html`; the generator
substitutes the distribution payload into its `__DATA__` placeholder. Edit the template, not the
generated HTML — the latter is overwritten on every run.


## Energy code at last HVAC replacement

`generate_energy_code_viz.py` builds a stacked bar chart of the energy code version in force when
a building last replaced its HVAC, stacked by year of original construction, with building type
and state filters and a summary of the total probability of each code version.

### The dependency chain

`energy_code_in_force_during_last_hvac_replacement.tsv` depends on `state_id` and
`year_bin_of_last_hvac_replacement`; that TSV in turn depends on `year_of_simulation` and
`year_built`. Composing them gives the quantity plotted in each column:

```
P(code | state, construction year) = Σ_bin P(bin | sim year, construction year) · P(code | state, bin)
```

**Neither TSV depends on building type.** With a single state selected, the building type filter
therefore does not change the shares within a construction year — it changes how much stock sits
behind each year, which moves the summary chart and the stock strip. With *All states* selected it
also shifts the state mixture, so it moves the within-year shares too. The viewer says which case
you are in under the filter row.

Stock weights come from the sampler's own chain, since `tract`, `year_built` and
`building_area` are all drawn independently given (region, building type, size bin):

```
P(bt, state, year) = Σ_region Σ_size P(region)·P(bt|region)·P(size|region,bt)
                                     ·P(state|region,bt,size)·P(year|region,bt,size)
```

State is the four-character prefix of the tract GISJOIN id; display names come from
`sampling/resources/spatial_tract_lookup_table_publish_v10.csv`.

### Buildings vs floor area

The **Weight by** control switches every share on the page between counting buildings and
counting floor area. `building_area` shares the same (region, building type, size bin)
conditioning, so a cell's expected building area is

```
E[area | region, bt, size] = Σ_range P(range | region, bt, size) · total_bldg_floor_area(range)
```

with the per-range areas read from the repo's `resources/options_lookup.tsv` (`_1000` → 1,000 ft²,
`over_1mil` → 1,100,000 ft², and so on). Multiplying each cell's contribution by that expectation
turns the building-count weights into floor-area weights; both are carried in the payload and the
toggle picks between them. The implied stock-average building is 22,238 ft², which the generator
logs as a sanity check.

The two weightings differ a lot, because building size correlates with both type and vintage —
hospitals are 0.07% of buildings but 0.80% of floor area, large offices 0.89% vs 10.1%, quick
service restaurants 3.2% vs 0.5%. Newer buildings are larger, so floor-area weighting shifts the
stock later: 53.2% of *buildings* predate 1980 against 44.3% of *floor area*.

Note that with a single state selected the weighting cannot change the shares within a
construction year (the conditional P(code | state, year) has no size term) — it changes the stock
behind each year, and so the summary and the strip. With all states pooled it also shifts the
state mixture, which does move the within-year shares.

### Running

```bash
python sampling/visualization/generate_energy_code_viz.py
```

Same options as the operating-hours generator (`--version`, `--zip`, `--out`); the default output
is `energy_code_hvac_<version>.html`. Reading `tract.json` and `year_built.json` makes this one
slower and the output larger (~1.5 MB) than the operating-hours viewer.

### Using the viewer

- **Building type** and **State** default to "all"; both scope every chart on the page.
- **Weight by** switches between building counts and floor area, and scopes the plot, the strip,
  the summary and the table.
- **Stacking** switches between *share within year* (each column normalized to 100%, with a strip
  underneath showing where the stock actually is) and *share of selected stock* (column height is
  that year's share of the selection).
- Hovering a column gives the year's stock share and its code breakdown; hovering a row in the
  summary isolates that code across every year. Arrow keys step between years, <kbd>Esc</kbd> clears.
- **Show years back to 1800** disables the default trim, which hides the leading construction
  years holding less than 0.5% of the selection.
- **Show data table** puts the summary numbers in a table, so nothing is encoded by colour alone.

### Colours

Codes are an *ordered* variable, so hue carries the code family and lightness carries the vintage
within it: gray for the DOE reference vintages, blue for ASHRAE 90.1, magenta for DEER before
2003, orange for DEER 2003 and later. The ramps are generated in OKLCH at page load and all eight
(four families × light/dark) pass the ordinal checks in the `dataviz` skill's
`validate_palette.js` — monotone lightness, adjacent ΔL ≥ 0.06, and the light end clear of the
surface. Splitting into four families is what keeps any single ramp short enough to stay
readable; a single 18-step ramp cannot.

Note that a selection can still put more than the ~7 colour classes that read comfortably on
screen into one stack — *All states* shows all 18, since DEER codes appear only in California and
the others everywhere else. The legend, the isolate-on-hover, the tooltip and the table view all
exist so identity never rests on colour discrimination alone.

### Known data quirks

- `year_of_simulation` is 2018 in `tsvs-v33`, so construction year 2019 has no replacement-year
  row and is dropped from the axis (the generator logs this).
- The energy code TSV and the year-bin TSV list the replacement-year bins in opposite order; the
  generator aligns them by label rather than by position.

### Editing

As with the operating-hours viewer, the page lives in `energy_code_template.html` and the
generator substitutes the payload into its `__DATA__` placeholder. Edit the template, not the
generated HTML.
