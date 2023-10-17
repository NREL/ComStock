# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest
import logging

import comstockpostproc.cbecs

def test_cbecs_2012(caplog):
    caplog.set_level(logging.INFO)
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year=2012,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=False
        )

    # Check the total square footage against published EIA tabulations
    # https://www.eia.gov/consumption/commercial/data/2012/bc/cfm/b7.php
    eia_sqft = 87_093_000_000
    total_sqft = cbecs.data[cbecs.col_name_to_weighted(cbecs.FLR_AREA)].sum()
    assert total_sqft == pytest.approx(eia_sqft, rel=0.01)

    # Check total energy consumption against published EIA tabulations
    # https://www.eia.gov/consumption/commercial/data/2012/c&e/cfm/c1.php
    eia_site_electricity_TBtu = 4_241
    site_electricity_TBtu = cbecs.data[cbecs.col_name_to_weighted(cbecs.ANN_TOT_ELEC_KBTU, 'tbtu')].sum()
    assert site_electricity_TBtu == pytest.approx(eia_site_electricity_TBtu, rel=0.01)

    eia_site_natural_gas_TBtu = 2_248
    site_natural_gas_TBtu = cbecs.data[cbecs.col_name_to_weighted(cbecs.ANN_TOT_GAS_KBTU, 'tbtu')].sum()
    assert site_natural_gas_TBtu == pytest.approx(eia_site_natural_gas_TBtu, rel=0.01)

    # Check for self-consistency in weighted and unweighted energy
    engy_tol = 0.00001

    # Pairs of total column and list of corresponding enduse columns
    tot_col_enduse_cols = [
        [cbecs.ANN_TOT_GAS_KBTU, cbecs.COLS_GAS_ENDUSE],  # Total natural gas vs. sum of end uses
        [cbecs.ANN_TOT_ELEC_KBTU, cbecs.COLS_ELEC_ENDUSE],  # Total electricity vs. sum of end uses
        [cbecs.ANN_TOT_ENGY_KBTU, [cbecs.ANN_TOT_ELEC_KBTU,  # Total energy vs. sum of all fuels
                                        cbecs.ANN_TOT_GAS_KBTU,
                                        cbecs.ANN_TOT_OTHFUEL_KBTU,
                                        cbecs.ANN_TOT_DISTHTG_KBTU,
                                        cbecs.ANN_TOT_DISTCLG_KBTU]]
    ]

    for tot_col, enduse_cols in tot_col_enduse_cols:
        # Unweighted
        sum_tot_col = cbecs.data[tot_col].sum()
        sum_enduses = cbecs.data[enduse_cols].sum().sum()
        assert sum_enduses == pytest.approx(sum_tot_col, rel=engy_tol), f'Error in unweighted {tot_col}'
        # Weighted
        wtd_tot_col = cbecs.col_name_to_weighted(tot_col, cbecs.weighted_energy_units)
        wtd_enduse_cols = [cbecs.col_name_to_weighted(c, cbecs.weighted_energy_units) for c in enduse_cols]
        sum_tot_col = cbecs.data[wtd_tot_col].sum()
        sum_enduses = cbecs.data[wtd_enduse_cols].sum().sum()
        assert sum_enduses == pytest.approx(sum_tot_col, rel=engy_tol), f'Error in weighted {tot_col}'

    cbecs.export_to_csv_wide()

def test_cbecs_2018(caplog):
    caplog.set_level(logging.INFO)
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year=2018,
        truth_data_version='v01',
        color_hex='#16f0b4',
        reload_from_csv=False
        )

    # Check the total square footage against published EIA tabulations
    # https://www.eia.gov/consumption/commercial/data/2018/bc/html/b7.php
    eia_sqft = 96_423_000_000
    total_sqft = cbecs.data[cbecs.col_name_to_weighted(cbecs.FLR_AREA)].sum()
    assert total_sqft == pytest.approx(eia_sqft, rel=0.01)

    # Check total energy consumption against published EIA tabulations
    # https://www.eia.gov/consumption/commercial/data/2018/ce/xls/c1.xlsx
    eia_site_electricity_TBtu = 4_081
    site_electricity_TBtu = cbecs.data[cbecs.col_name_to_weighted(cbecs.ANN_TOT_ELEC_KBTU, 'tbtu')].sum()
    assert site_electricity_TBtu == pytest.approx(eia_site_electricity_TBtu, rel=0.01)

    eia_site_natural_gas_TBtu = 2_300
    site_natural_gas_TBtu = cbecs.data[cbecs.col_name_to_weighted(cbecs.ANN_TOT_GAS_KBTU, 'tbtu')].sum()
    assert site_natural_gas_TBtu == pytest.approx(eia_site_natural_gas_TBtu, rel=0.01)

    # Check for self-consistency in weighted and unweighted energy
    engy_tol = 0.00001

    # Pairs of total column and list of corresponding enduse columns
    tot_col_enduse_cols = [
        [cbecs.ANN_TOT_GAS_KBTU, cbecs.COLS_GAS_ENDUSE],  # Total natural gas vs. sum of end uses
        [cbecs.ANN_TOT_ELEC_KBTU, cbecs.COLS_ELEC_ENDUSE],  # Total electricity vs. sum of end uses
        [cbecs.ANN_TOT_ENGY_KBTU, [cbecs.ANN_TOT_ELEC_KBTU,  # Total energy vs. sum of all fuels
                                        cbecs.ANN_TOT_GAS_KBTU,
                                        cbecs.ANN_TOT_OTHFUEL_KBTU,
                                        cbecs.ANN_TOT_DISTHTG_KBTU,
                                        cbecs.ANN_TOT_DISTCLG_KBTU]]
    ]

    for tot_col, enduse_cols in tot_col_enduse_cols:
        # Unweighted
        sum_tot_col = cbecs.data[tot_col].sum()
        sum_enduses = cbecs.data[enduse_cols].sum().sum()
        print(f'{tot_col} = {sum_tot_col}, sum of enduses = {sum_enduses}')
        assert sum_enduses == pytest.approx(sum_tot_col, rel=engy_tol), f'Error in unweighted {tot_col}'
        # Weighted
        wtd_tot_col = cbecs.col_name_to_weighted(tot_col, cbecs.weighted_energy_units)
        wtd_enduse_cols = [cbecs.col_name_to_weighted(c, cbecs.weighted_energy_units) for c in enduse_cols]
        sum_tot_col = cbecs.data[wtd_tot_col].sum()
        sum_enduses = cbecs.data[wtd_enduse_cols].sum().sum()
        assert sum_enduses == pytest.approx(sum_tot_col, rel=engy_tol), f'Error in weighted {tot_col}'

    cbecs.export_to_csv_wide()
