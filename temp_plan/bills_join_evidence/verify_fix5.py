"""The bills stage on hospital_resampling/str_100k_new_sample_fix5, the newest run, against its results dashboard.

This branch's base code (main) cannot build fix5's simulation-output cache (the run names floor area
by the custom building spec, which only the dashboard branch aliases), and the bills stage needs
only a few columns. So the inputs are built straight from the run's files on S3: the bill strings,
floor area, building type and site totals from results_up00.parquet, the sampling region from
buildstock.csv. fix5 is on the same sample as fanfix (checked below), so the allocation draw is
fanfix's scaled draw, the shared draw of the new-sample runs. Steps, one per process, with
PYTHONPATH=<worktree>/postprocessing:

    python verify_fix5.py inputs        write the stage inputs and check the sample against fanfix
    python verify_fix5.py build-old <k> main's bills join (3c103063), state chunk k of 6
    python verify_fix5.py compare       floor area and energy: main's join, this code, the dashboard

check_both_ways.py <OUT>/fix5_inputs <OUT>/fix5_both_ways ... builds this code's stage (level A)
on the same inputs, both ways.
"""
import glob
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time

import fsspec
import polars as pl
import pyarrow.parquet as pq

import comstockpostproc as cspp
from comstockpostproc.comstock import ComStock

assert 'great-kalam-502c41' in cspp.__file__, cspp.__file__
N = ComStock
HERE = os.path.dirname(os.path.abspath(__file__)).replace('\\', '/')
WT = os.path.normpath(os.path.join(HERE, '..', '..')).replace('\\', '/')
OUT = f'{WT}/postprocessing/output'
INPUTS = f'{OUT}/fix5_inputs'
OLD_OUT = f'{OUT}/fix5_old'
BOTH = f'{OUT}/fix5_both_ways'
S3 = 's3://eulp/euss_com/hospital_resampling/str_100k_new_sample_fix5/str_100k_new_sample_fix5'
MAIN_PP = 'C:/Users/ccaradon/Documents/GitHub/ComStock/postprocessing'
FANFIX = f'{MAIN_PP}/output/ComStock str_100k_new_sample_plugfix_fanfix'
DASHBOARD = 'C:/Users/ccaradon/Downloads/dashboard 5.html'
REF = '3c103063'
CHUNKS = 6
STATE, W, ROW = N.STATE_ABBRV, N.BLDG_WEIGHT, '_row_id'
RAW = {
    'building_id': N.BLDG_ID,
    'build_existing_model.create_custom_building_from_spec_total_bldg_floor_area': N.FLR_AREA,
    'build_existing_model.building_type': N.BLDG_TYPE,
    'utility_bills.electricity_utility_bill_results': N.UTIL_BILL_ELEC_RESULTS,
    'utility_bills.state_avg_electricity_cost_results': N.UTIL_BILL_STATE_ELEC_RESULTS,
    'utility_bills.state_avg_naturalgas_cost_results': N.UTIL_BILL_STATE_GAS_RESULTS,
    'utility_bills.state_avg_propane_cost_results': N.UTIL_BILL_STATE_PROPANE_RESULTS,
    'utility_bills.state_avg_fueloil_cost_results': N.UTIL_BILL_STATE_FUEL_OIL_RESULTS,
    'simulation_output_report.total_site_electricity_kwh': 'elec_kwh',
    'simulation_output_report.total_site_natural_gas_therm': 'gas_therm',
    'simulation_output_report.total_site_energy_mbtu': 'site_mbtu',
}


def inputs():
    t0 = time.time()
    fs = fsspec.filesystem('s3')  # s3fs, with the default (SSO) profile
    with fs.open(f'{S3}/baseline/results_up00.parquet', 'rb') as f:
        res = pl.from_arrow(pq.read_table(f, columns=list(RAW) + ['completed_status']))
    res = (res.filter(pl.col('completed_status') == 'Success').select(list(RAW)).rename(RAW)
           .with_columns(pl.col(N.BLDG_ID).cast(pl.Int64),
                         pl.col(N.FLR_AREA, 'elec_kwh', 'gas_therm', 'site_mbtu').cast(pl.Float64)))
    with fs.open(f'{S3}/buildstock_csv/buildstock.csv', 'rb') as f:
        bs = pl.read_csv(f, columns=['Building', 'sampling_region'],
                         schema_overrides={'Building': pl.Int64, 'sampling_region': pl.String})
    sim = res.join(bs.rename({'Building': N.BLDG_ID, 'sampling_region': N.SAMPLING_REGION}), on=N.BLDG_ID, how='left')
    assert sim[N.SAMPLING_REGION].null_count() == 0
    # The same sample as fanfix: every fanfix model's region, building type and floor area match
    ff = pl.scan_parquet(f'{FANFIX}/cached_simulation_outputs/upgrade=0/*.parquet').select(
        N.BLDG_ID, pl.col(N.SAMPLING_REGION).cast(pl.String).alias('_r'), pl.col(N.BLDG_TYPE).cast(pl.String).alias('_t'),
        pl.col(N.FLR_AREA).alias('_a')).collect()
    j = ff.join(sim.select(N.BLDG_ID, N.SAMPLING_REGION, pl.col(N.BLDG_TYPE).cast(pl.String).alias('_raw_t'), N.FLR_AREA),
                on=N.BLDG_ID, how='inner')
    same = j.filter((pl.col('_r') == pl.col(N.SAMPLING_REGION)) & ((pl.col('_a') - pl.col(N.FLR_AREA)).abs() < 0.5)).height
    # The results name building types in the measure's terms (strip_mall); postprocessing maps them to
    # ComStock's (RetailStripmall), which fanfix's cache carries model by model
    one_to_one = j.select('_raw_t', '_t').unique().group_by('_raw_t').len()['len'].max() == 1
    print(f'fix5 successful models {sim.height:,}; fanfix models {ff.height:,}, of which in fix5 {j.height:,}, with the same '
          f'region and floor area {same:,}; raw building types map one-to-one onto fanfix\'s: {one_to_one}; '
          f'fix5 models not in fanfix: {sim.join(ff, on=N.BLDG_ID, how="anti").height:,}')
    sim = sim.drop(N.BLDG_TYPE).join(ff.select(N.BLDG_ID, pl.col('_t').alias(N.BLDG_TYPE)), on=N.BLDG_ID, how='left')
    os.makedirs(f'{INPUTS}/cached_simulation_outputs/upgrade=0', exist_ok=True)
    sim.write_parquet(f'{INPUTS}/cached_simulation_outputs/upgrade=0/sim.parquet')
    shutil.copyfile(f'{FANFIX}/cached_ComStock_alloc_wts_scaled_to_cbecs.parquet', f'{INPUTS}/cached_ComStock_alloc_wts_scaled_to_cbecs.parquet')
    draw = pl.scan_parquet(f'{INPUTS}/cached_ComStock_alloc_wts_scaled_to_cbecs.parquet')
    missing = draw.join(sim.lazy().select(N.BLDG_ID), on=N.BLDG_ID, how='anti').select(pl.len()).collect().item()
    print(f'draw rows {draw.select(pl.len()).collect().item():,}; draw rows whose model is not in fix5: {missing:,} ({time.time() - t0:.0f}s)')


def chunk_states():
    counts = pl.scan_parquet(f'{INPUTS}/cached_ComStock_alloc_wts_scaled_to_cbecs.parquet').group_by(STATE).len() \
        .sort('len', descending=True).collect().rows()
    groups = [[0, []] for _ in range(CHUNKS)]
    for st, n in counts:
        g = min(groups, key=lambda x: x[0])
        g[0] += n
        g[1].append(st)
    return [sorted(g[1]) for g in groups]


def main_comstock_class():
    src = f'{OUT}/bv_ref/comstock_{REF}.py'
    if not os.path.exists(src):
        os.makedirs(os.path.dirname(src), exist_ok=True)
        code = subprocess.run(['git', '-C', WT, 'show', f'{REF}:postprocessing/comstockpostproc/comstock.py'],
                              capture_output=True, check=True).stdout
        with open(src, 'wb') as f:
            f.write(code)
    spec = importlib.util.spec_from_file_location(f'comstockpostproc.comstock_{REF}', src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod.ComStock


def build_old(k):
    states = chunk_states()[k]
    cls = main_comstock_class()
    cs = cls.__new__(cls)
    cs.output_dir = {'fs': fsspec.filesystem('file'), 'fs_path': f'{OLD_OUT}/c{k}', 'storage_options': None}
    cs.truth_data_dir = f'{MAIN_PP}/truth_data/v01'
    cs.tract_to_util_map_file_name = 'tract_to_elec_util_v2.csv'
    cs.weighted_utility_units = 'billion_usd'
    cs.unweighted_weighted_map = {}
    cs.data = pl.scan_parquet(f'{INPUTS}/cached_simulation_outputs/upgrade=0/sim.parquet').with_columns(
        pl.lit(0).cast(pl.Int64).alias(N.UPGRADE_ID))
    cs.get_sim_outs_for_upgrade = lambda u: cs.data
    cs.get_allocated_weights_scaled_to_cbecs_for_upgrade = lambda u: (
        pl.scan_parquet(f'{INPUTS}/cached_ComStock_alloc_wts_scaled_to_cbecs.parquet')
        .with_columns(pl.int_range(pl.len(), dtype=pl.UInt32).alias(ROW), pl.lit(u).cast(pl.Int64).alias(N.UPGRADE_ID))
        .filter(pl.col(STATE).is_in(states)))
    t0 = time.time()
    cs.create_allocated_weights_plus_util_bills_for_upgrade(0)
    print(f'old chunk {k}: built in {time.time() - t0:.0f}s', flush=True)


def dashboard_fix5():
    s = open(DASHBOARD, encoding='utf-8', errors='replace').read()
    i = s.index('window.__DASHBOARD__ = ') + len('window.__DASHBOARD__ = ')
    d, _ = json.JSONDecoder().raw_decode(s, i)
    return (pl.DataFrame(d['byDim']['building_type'], infer_schema_length=None)
            .filter(pl.col('run') == 'str_100k_new_sample_fix5')
            .select(pl.col('category').alias(N.BLDG_TYPE), 'metric', 'comstock_value', 'cbecs_value'))


def compare():
    sim = pl.read_parquet(f'{INPUTS}/cached_simulation_outputs/upgrade=0/sim.parquet').select(
        N.BLDG_ID, pl.col(N.BLDG_TYPE).cast(pl.String), N.FLR_AREA, 'elec_kwh', 'gas_therm', 'site_mbtu')
    stages = {
        'main': glob.glob(f'{OLD_OUT}/c*/cached_allocated_weights_plus_bills/upgrade=0/in.state=*/*.parquet'),
        'this code': glob.glob(f'{BOTH}/order/c*/cached_allocated_weights_plus_bills/upgrade=0/in.state=*/*.parquet'),
    }
    totals = []
    for name, files in stages.items():
        st = (pl.scan_parquet(files).select(N.BLDG_ID, W, N.UTIL_BILL_ELEC).collect()
              .group_by(N.BLDG_ID).agg(pl.col(W).sum(), (pl.col(W) * pl.col(N.UTIL_BILL_ELEC)).sum().alias('bill')))
        t = (st.join(sim, on=N.BLDG_ID, how='left').group_by(N.BLDG_TYPE).agg(
            (pl.col(W) * pl.col(N.FLR_AREA)).sum().alias('sqft'),
            (pl.col(W) * pl.col('elec_kwh')).sum().mul(3412.14 / 1e12).alias('electricity.total'),
            (pl.col(W) * pl.col('gas_therm')).sum().mul(1e5 / 1e12).alias('natural_gas.total'),
            (pl.col(W) * pl.col('site_mbtu')).sum().mul(1e6 / 1e12).alias('site_energy.total'),
            pl.col('bill').sum().alias('elec_bill_usd'))
            .with_columns(pl.lit(name).alias('stage')))
        totals.append(t)
    t = pl.concat(totals)
    t = pl.concat([t, t.group_by('stage').agg(pl.exclude(N.BLDG_TYPE, 'stage').sum()).with_columns(pl.lit('All').alias(N.BLDG_TYPE))],
                  how='diagonal')
    dash = dashboard_fix5()
    cbecs = dash.filter(pl.col('metric') == 'sqft').select(N.BLDG_TYPE, pl.col('cbecs_value').alias('cbecs_sqft'))
    rows = []
    for metric in ['sqft', 'electricity.total', 'natural_gas.total', 'site_energy.total']:
        dm = dash.filter(pl.col('metric') == metric).select(N.BLDG_TYPE, pl.col('comstock_value').alias('dashboard'))
        wide = t.pivot(on='stage', index=N.BLDG_TYPE, values=metric).join(dm, on=N.BLDG_TYPE, how='left')
        rows.append(wide.with_columns(pl.lit(metric).alias('metric')))
    out = pl.concat(rows, how='diagonal').join(cbecs, on=N.BLDG_TYPE, how='left')
    out.write_csv(f'{HERE}/fix5_vs_dashboard.csv', float_precision=4)
    with pl.Config(tbl_rows=80, tbl_width_chars=200, float_precision=2):
        sq = out.filter(pl.col('metric') == 'sqft').with_columns(
            ((pl.col('dashboard') / pl.col('cbecs_sqft') - 1) * 100).alias('dashboard_vs_cbecs_pct'),
            ((pl.col('main') / pl.col('cbecs_sqft') - 1) * 100).alias('main_vs_cbecs_pct'),
            ((pl.col('this code') / pl.col('cbecs_sqft') - 1) * 100).alias('this_code_vs_cbecs_pct'))
        print('floor area vs CBECS 2018 (%):')
        print(sq.select(N.BLDG_TYPE, 'dashboard_vs_cbecs_pct', 'main_vs_cbecs_pct', 'this_code_vs_cbecs_pct').sort(N.BLDG_TYPE))
        print('national totals (TBtu): the dashboard, main\'s join on these inputs, this code')
        print(out.filter(pl.col(N.BLDG_TYPE) == 'All').select('metric', 'dashboard', 'main', 'this code').with_columns(
            ((pl.col('this code') / pl.col('main') - 1) * 100).alias('this_code_vs_main_pct')))
    eb = t.filter(pl.col(N.BLDG_TYPE) == 'All').select('stage', 'elec_bill_usd').rows()
    print('national electricity bill:', {k: f'${v / 1e9:,.2f}B' for k, v in eb})


if __name__ == '__main__':
    step = sys.argv[1]
    if step == 'inputs':
        inputs()
    elif step == 'build-old':
        build_old(int(sys.argv[2]))
    elif step == 'compare':
        compare()
