"""Time the bills stage for fanfix chunk 0 with whichever comstockpostproc is on PYTHONPATH.
Usage: python time_stage.py <label> <output dir> [full]"""
import shutil
import sys
import time

import fsspec
import polars as pl

import comstockpostproc as cspp
from comstockpostproc.comstock import ComStock as N

label, out = sys.argv[1], sys.argv[2]
RUN = 'C:/Users/ccaradon/Documents/GitHub/ComStock/postprocessing/output/ComStock str_100k_new_sample_plugfix_fanfix'
STATES = ['CA', 'DC', 'LA', 'MN', 'NE', 'SC', 'SD']
FULL = len(sys.argv) > 3 and sys.argv[3] == 'full'
shutil.rmtree(out, ignore_errors=True)
cs = N.__new__(N)
cs.output_dir = {'fs': fsspec.filesystem('file'), 'fs_path': out, 'storage_options': None}
cs.truth_data_dir = 'C:/Users/ccaradon/Documents/GitHub/ComStock/postprocessing/truth_data/v01'
cs.tract_to_util_map_file_name = 'tract_to_elec_util_v2.csv'
cs.weighted_utility_units = 'billion_usd'
cs.unweighted_weighted_map = {}
cs.data = pl.scan_parquet(f'{RUN}/cached_simulation_outputs/upgrade=0/*.parquet').with_columns(pl.lit(0).cast(pl.Int64).alias(N.UPGRADE_ID))
cs.get_sim_outs_for_upgrade = lambda u: cs.data
cs.get_allocated_weights_scaled_to_cbecs_for_upgrade = lambda u: (
    pl.scan_parquet(f'{RUN}/cached_ComStock_alloc_wts_scaled_to_cbecs.parquet')
    .with_columns(pl.lit(u).cast(pl.Int64).alias(N.UPGRADE_ID)).filter(pl.col(N.STATE_ABBRV).is_in(STATES) | pl.lit(FULL)))
t0 = time.time()
cs.create_allocated_weights_plus_util_bills_for_upgrade(0)
import psutil
m = psutil.Process().memory_info()
print(f'{label}: {time.time() - t0:.1f}s, peak commit {m.peak_pagefile / 1e9:.1f} GB, peak working set {m.peak_wset / 1e9:.1f} GB ({cspp.__file__})', flush=True)
shutil.rmtree(out, ignore_errors=True)
