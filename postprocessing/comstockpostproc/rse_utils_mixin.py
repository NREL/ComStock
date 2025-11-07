# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

import re
import numpy as np
import pandas as pd
from functools import lru_cache
from typing import Iterable, Optional, Union, Tuple

"""
CBECS Replicate-Weight RSE Utilities
====================================

This module implements Relative Standard Error (RSE) and confidence-interval
calculations using the CBECS (Commercial Buildings Energy Consumption Survey)
jackknife replicate weights. CBECS provides one main weight and ~150 replicate
weights that encode the survey’s complex sampling and stratification. Following
the U.S. Energy Information Administration’s published variance methodology
(see: EIA, *CBECS 2018 Technical Documentation*, "Use of Replicate Weights"),
variance is computed as:

    Var(θ) = κ × Σ_r (θ_r – θ)²

where θ is the full-sample estimate, θ_r are replicate estimates, and κ is the
jackknife variance coefficient. By default κ = (R-1)/R, but we allow calibration
via `calibrate_kappa_for_total()` if a known RSE target is available.

The module provides groupwise RSEs for totals, means, and ratios, returning
estimates, standard errors, RSEs (%), and 95 % confidence intervals for plotting
and QA. This supports ComStock/CBECS comparison charts and internal validation
of survey-derived uncertainty.

References
----------
• EIA, *Commercial Buildings Energy Consumption Survey (CBECS) 2018: Technical
  Documentation – Use of Replicate Weights*, https://www.eia.gov/consumption/commercial/data/2018/
• Lohr, S. L. (2022). *Sampling: Design and Analysis*, 3rd ed. (Jackknife
  replication overview)

"""


## Regex to identify replicate weight columns (CBECS format)
_REP_RE = re.compile(r"^Unknown Eligibility and Nonresponse Adjusted Replicate Weight (\d+)$")

# Get sorted list of replicate weight columns
def _rep_cols(df: pd.DataFrame) -> list[str]:
    # Find all replicate weight columns in the DataFrame
    cols = [c for c in df.columns if _REP_RE.match(c)]
    if not cols:
        raise ValueError("No CBECS replicate weight columns found.")
    # Sort columns numerically by replicate number
    cols.sort(key=lambda c: int(_REP_RE.match(c).group(1)))
    return cols

# Convert series to numeric, coercing errors to NaN
def _to_num(s: pd.Series) -> pd.Series:
    return pd.to_numeric(s, errors="coerce")

# Compute point estimate and replicate estimates for totals
def _theta_and_reps(val: pd.Series, w: pd.Series, rep_w: pd.DataFrame) -> Tuple[float, np.ndarray]:
    x = val.to_numpy(); wf = w.to_numpy()
    theta = float(np.nansum(x * wf))
    rep_thetas = np.array([np.nansum(x * rep_w[c].to_numpy()) for c in rep_w.columns], float)
    return theta, rep_thetas

# Jackknife variance calculation for replicate weights
def _jk_var(theta: float, rep_thetas: np.ndarray, kappa: float) -> float:
    return float(kappa * np.sum((rep_thetas - theta) ** 2))

## RSE calculation methods
# Calculate RSE for total estimate by group
def rse_by_group_total(
    df: pd.DataFrame,
    value_col: str,
    by: Union[str, Iterable[str]],
    universe_mask: Optional[pd.Series] = None,
    weight_col: str = "weight",
    kappa: Optional[float] = None,
    already_weighted: bool = False,
) -> pd.DataFrame:
    """
    Total = sum(w*x); SE via JK replicate totals.
    If already_weighted=True, value_col is already weighted (i.e., x*w), so we divide by weight to recover x.
    """
    reps = _rep_cols(df)
    if universe_mask is None: universe_mask = pd.Series(True, index=df.index)
    if isinstance(by, str): by = [by]

    cols = list(by) + [value_col, weight_col] + reps
    sub = df.loc[universe_mask, cols].copy()
    sub[value_col] = _to_num(sub[value_col]); sub[weight_col] = _to_num(sub[weight_col])
    for c in reps: sub[c] = _to_num(sub[c])
    sub = sub.replace([np.inf, -np.inf], np.nan).dropna(subset=[value_col, weight_col])

    # If already_weighted, recover unweighted value for correct RSE calculation
    if already_weighted:
        # Avoid division by zero
        sub["_unweighted_value"] = sub[value_col] / sub[weight_col].replace(0, np.nan)
        value_col_for_calc = "_unweighted_value"
    else:
        value_col_for_calc = value_col

    if kappa is None:
        R = len(reps); kappa = (R - 1) / R

    rows = []
    # Group by requested columns and calculate RSE/CI for each group
    for keys, g in sub.groupby(list(by), dropna=False, observed = False):
        theta, rep_thetas = _theta_and_reps(g[value_col_for_calc], g[weight_col], g[reps])
        var = _jk_var(theta, rep_thetas, kappa)
        se = float(np.sqrt(var))  # Standard error
        rse = 100.0 * se / theta if theta else np.nan  # RSE as percent
        ci_low = max(theta - 1.96*se, 0)  # CI lower bound capped at zero
        ci_high = theta + 1.96*se
        rows.append({**{b: (keys[i] if isinstance(keys, tuple) else keys) for i, b in enumerate(by)},
                     "estimate": theta, "se": se, "rse_pct": rse,
                     "ci95_low": ci_low, "ci95_high": ci_high})
    return pd.DataFrame(rows)

# Calculate RSE for mean estimate by group
def rse_by_group_mean(
    df: pd.DataFrame,
    value_col: str,
    by: Union[str, Iterable[str]],
    universe_mask: Optional[pd.Series] = None,
    weight_col: str = "weight",
    kappa: Optional[float] = None,
) -> pd.DataFrame:
    """Weighted mean = (sum w*x)/(sum w); compute same in each replicate."""
    reps = _rep_cols(df)
    if universe_mask is None: universe_mask = pd.Series(True, index=df.index)
    if isinstance(by, str): by = [by]

    cols = list(by) + [value_col, weight_col] + reps
    sub = df.loc[universe_mask, cols].copy()
    sub[value_col] = _to_num(sub[value_col]); sub[weight_col] = _to_num(sub[weight_col])
    for c in reps: sub[c] = _to_num(sub[c])
    sub = sub.replace([np.inf, -np.inf], np.nan).dropna(subset=[value_col, weight_col])

    if kappa is None:
        R = len(reps); kappa = (R - 1) / R

    rows = []
    # Group by requested columns and calculate weighted mean, RSE, and CI for each group
    for keys, g in sub.groupby(list(by), dropna=False, observed=False):
        w = g[weight_col]; x = g[value_col]
        num = float(np.nansum(w*x)); den = float(np.nansum(w))
        theta = num/den if den else np.nan  # Weighted mean
        rep_t = []
        for c in reps:
            wr = g[c]; num_r = float(np.nansum(wr*x)); den_r = float(np.nansum(wr))
            rep_t.append(num_r/den_r if den_r else np.nan)
        rep_t = np.array(rep_t, float) # Replicate means
        var = _jk_var(theta, rep_t, kappa) # Calculate variance
        se = float(np.sqrt(var)) # Standard error
        rse = 100.0*se/theta if theta else np.nan # RSE as percent
        ci_low = max(theta - 1.96*se, 0) # CI lower bound capped at zero
        ci_high = theta + 1.96*se # CI upper bound
        rows.append({**{b: (keys[i] if isinstance(keys, tuple) else keys) for i, b in enumerate(by)},
                     "estimate": theta, "se": se, "rse_pct": rse,
                     "ci95_low": ci_low, "ci95_high": ci_high})
    return pd.DataFrame(rows)

# Calculate RSE for ratio estimate by group
def rse_by_group_ratio(
    df: pd.DataFrame,
    numer_col: str,
    denom_col: str,
    by: Union[str, Iterable[str]],
    universe_mask: Optional[pd.Series] = None,
    weight_col: str = "weight",
    kappa: Optional[float] = None,
) -> pd.DataFrame:
    """Ratio = (sum w*numer)/(sum w*denom); compute same in each replicate."""
    reps = _rep_cols(df)
    if universe_mask is None: universe_mask = pd.Series(True, index=df.index)
    if isinstance(by, str): by = [by]

    cols = list(by) + [numer_col, denom_col, weight_col] + reps
    sub = df.loc[universe_mask, cols].copy()
    for c in [numer_col, denom_col, weight_col] + reps:
        sub[c] = _to_num(sub[c])
    sub = sub.replace([np.inf, -np.inf], np.nan).dropna(subset=[numer_col, denom_col, weight_col])

    if kappa is None:
        R = len(reps); kappa = (R - 1) / R

    rows = []
    # Group by requested columns and calculate weighted ratio, RSE, and CI for each group
    for keys, g in sub.groupby(list(by), dropna=False, observed=False):
        w = g[weight_col]
        num = float(np.nansum(w*g[numer_col])); den = float(np.nansum(w*g[denom_col]))
        theta = num/den if den else np.nan  # Weighted ratio
        rep_t = []
        for c in reps:
            wr = g[c]
            num_r = float(np.nansum(wr*g[numer_col])); den_r = float(np.nansum(wr*g[denom_col]))
            rep_t.append(num_r/den_r if den_r else np.nan)
        rep_t = np.array(rep_t, float)  # Replicate ratios
        var = _jk_var(theta, rep_t, kappa) # Calculate variance
        se = float(np.sqrt(var)) # Standard error
        rse = 100.0*se/theta if theta else np.nan # RSE as percent
        ci_low = max(theta - 1.96*se, 0) # CI lower bound capped at zero
        ci_high = theta + 1.96*se # CI upper bound
        rows.append({**{b: (keys[i] if isinstance(keys, tuple) else keys) for i, b in enumerate(by)},
                     "estimate": theta, "se": se, "rse_pct": rse,
                     "ci95_low": ci_low, "ci95_high": ci_high})
    return pd.DataFrame(rows)
