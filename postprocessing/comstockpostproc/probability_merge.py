# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
"""Validated join of a probability TSV onto building-level data.

Added 2026-09 (stock-estimation ``docs/plans/2026-09-cbecs-fuel-hvac-rebuild``, WS1). Kept free of AWS imports so
it can be unit-tested and reused outside the apportionment class.
"""
import logging

import pandas as pd

logger = logging.getLogger(__name__)


def merge_probability_table(df, prob, left_on, right_on, option_cols, label, fallback_on=None, area_col=None):
    """Join a probability table onto ``df`` without ever duplicating or dropping a row of ``df``.

    The previous inner ``merge`` in ``Apportion.upsample_hvac_system_fuel_types`` silently double-counted every
    building whose key matched two TSV rows (the shipped ``hvac_system_type_v4.tsv`` carried 52 duplicated
    Propane keys, about 1.1 billion ft2 of phantom stock in the 2025 R3 estimate) and silently dropped every
    building whose key had no TSV row (about 1.2% of floor area: district heating, strip mall in the Mountain
    division, hospital electric).

    :param df: building-level data (one row per bootstrapped building)
    :param prob: probability table with columns ``right_on`` + ``option_cols``
    :param left_on: key columns in ``df``
    :param right_on: key columns in ``prob``, same order as ``left_on``
    :param option_cols: probability columns to bring across
    :param label: name used in log messages and diagnostics
    :param fallback_on: optional list of key subsets (column names of ``prob``), tried in order, that unmatched
        rows fall back to: ``option_cols`` are averaged over the TSV rows sharing that subset and renormalised.
        ``None`` means an unmatched row is an error.
    :param area_col: optional floor-area column of ``df`` used to report the share of stock affected
    :return: ``(merged, diagnostics)`` where ``merged`` has exactly ``len(df)`` rows in the original order
    """
    dup = prob.duplicated(right_on, keep=False)
    if dup.any():
        examples = prob.loc[dup, right_on].drop_duplicates().head(5).to_dict(orient='records')
        raise ValueError(
            f'{label}: {int(prob.duplicated(right_on).sum())} duplicated dependency keys in the probability table; '
            f'each building would be double-counted. Examples: {examples}. Fix the TSV rather than the merge.')

    n_in = len(df)
    area = df[area_col].to_numpy(dtype=float) if area_col and area_col in df.columns else None
    total_area = float(area.sum()) if area is not None else 0.0

    def _share(mask):
        return float(area[mask].sum() / total_area) if area is not None and total_area else None

    merged = df.merge(prob, how='left', left_on=left_on, right_on=right_on, validate='many_to_one')
    if len(merged) != n_in:
        raise RuntimeError(f'{label}: merge changed the row count {n_in} -> {len(merged)}')

    unmatched = merged[option_cols].isna().all(axis=1).to_numpy()
    diag = {'label': label, 'rows': int(n_in), 'unmatched_rows': int(unmatched.sum()),
            'unmatched_area_share': _share(unmatched), 'fallback': []}
    if unmatched.any():
        missing_keys = merged.loc[unmatched, left_on].drop_duplicates()
        share = diag['unmatched_area_share']
        logger.warning('%s: %d of %d rows (%s of floor area) have no probability row; keys: %s%s', label,
                       diag['unmatched_rows'], n_in, 'n/a' if share is None else f'{100 * share:.2f}%',
                       missing_keys.head(10).to_dict(orient='records'), ' ...' if len(missing_keys) > 10 else '')

    for keys in (fallback_on or []):
        if not unmatched.any():
            break
        keys = list(keys)
        left_keys = [left_on[right_on.index(k)] for k in keys]
        fb = prob.groupby(keys, as_index=False)[option_cols].mean()
        fb[option_cols] = fb[option_cols].div(fb[option_cols].sum(axis=1), axis=0)
        need = merged.loc[unmatched, left_keys].reset_index()
        fill = need.merge(fb, how='left', left_on=left_keys, right_on=keys)
        got = fill[option_cols].notna().all(axis=1).to_numpy()
        idx = fill.loc[got, 'index'].to_numpy()
        merged.loc[idx, option_cols] = fill.loc[got, option_cols].to_numpy()
        filled = pd.Series(False, index=merged.index)
        filled.loc[idx] = True
        diag['fallback'].append({'keys': keys, 'rows': int(got.sum()), 'area_share': _share(filled.to_numpy())})
        logger.warning('%s: %d rows filled from the mean of TSV rows sharing %s', label, int(got.sum()), keys)
        unmatched = merged[option_cols].isna().all(axis=1).to_numpy()

    if unmatched.any():
        missing_keys = merged.loc[unmatched, left_on].drop_duplicates()
        raise ValueError(
            f'{label}: {int(unmatched.sum())} rows have no probability row and no fallback matched; '
            f'keys: {missing_keys.head(10).to_dict(orient="records")}. Extend the TSV or pass fallback_on.')
    return merged, diag
