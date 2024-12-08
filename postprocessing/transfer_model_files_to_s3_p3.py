import comstockpostproc as cspp

#yml_path = '/lustre/eaglefs/projects/enduse/comstock/ymls/euss_fy23/euss_full_350k_short_3of3-116402.yml'
yml_path = "/kfs2/projects/eusscom/ymls/euss_fy25/euss_2024_r2/full_runs/euss_2024_r2_3of4_37331.yml"

#s3_output_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2023/comstock_amy2018_release_1/building_energy_models/'
s3_output_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2024/comstock_amy2018_release_2/building_energy_models/'
#oedi_metadata_dir = 's3://oedi-data-lake/nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/2023/comstock_amy2018_release_1/metadata/'

#oedi_metadata_dir = 's3://eulp/euss_com/sdr_2024_r2_149325_combined/sdr_2024_r2_149325_combined/baseline/'

oedi_metadata_dir = 's3://com-sdr/euss_com/sdr_2024_r2_149325_combined/sdr_2024_r2_149325_combined/baseline/'

output_dir = s3_output_dir
# Extract model files from run and transfer to S3
cspp.utils.hpc.transfer_model_files_to_s3(yml_path, output_dir, oedi_metadata_dir)
