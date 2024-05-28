import comstockpostproc as cspp

yml_path = '/projects/enduse/comstock/ymls/comstock_fy22/com_os340_newbsb_test.yml'

# Extract and summarize failed runs
cspp.utils.hpc.summarize_failures(yml_path)

# Extract models - add building IDs to my_run_name/building_id_list.csv, header=building_id
output_vars_to_add_to_idfs = [
    'Facility Total Building Electric Demand Power',
    'Lights Electric Power',
    'Electric Equipment Electric Power',
    'People Occupant Count',
    ['System Node Standard Density Volume Flow Rate','.* OA NODE','Detailed'],
    ['System Node Mass Flow Rate','','RunPeriod']
]
cspp.utils.hpc.extract_models_from_simulation_output(yml_path, up_id='up00', output_vars=output_vars_to_add_to_idfs)

# Run extracted IDFs with EnergyPlus
cspp.utils.hpc.run_extracted_models(yml_path, energyplus_version='22.1.0')

# Extract and summarize warnings in eplusout.err files
cspp.utils.hpc.extract_energyplus_error_files_from_jobs(yml_path)
cspp.utils.hpc.summarize_energyplus_error_files(yml_path)

# Extract runtime summary from singularity_output.log files
cspp.utils.hpc.parse_and_generate_profiling(yml_path)

# Summarize HPC usage (runtime and AUs)
cspp.utils.hpc.summarize_hpc_usage(yml_path)
