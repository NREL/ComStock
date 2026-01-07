#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import os

from comstockpostproc.gap.commercialgap import CommercialGap

logging.basicConfig(level='DEBUG')  # Use DEBUG, INFO, or WARNING
logger = logging.getLogger(__name__)

def main():
    gap_model = CommercialGap(
                    truth_data_version='v01', # Version of truth data
                    reload_from_saved=False,
                    resstock_version='2024_amy2018_release_2',
                    comstock_version='amy2018_r3_2025',
                    basis_lrd_name='First Energy PA',
                    res_allocation_method='EIA',
                    com_allocation_method='EIA',
                    gap_allocation_method='CBECS',
                    trim_negative_gap=True)

    gap_model.save_gap_profiles()
    gap_model.plot_profiles('BA', ['PJM', 'ERCO', 'CISO'])
    gap_model.annual_comparison_plot()
    gap_model.monthly_comparison_plot()

if __name__ == "__main__":
    main()