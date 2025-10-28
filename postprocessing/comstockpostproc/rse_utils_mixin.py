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
jackknife replicate weights. CBECS provides one main weight and 96 replicate
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


# Regex to identify replicate weight columns
_REP_RE = re.compile(r"^Unknown Eligibility and Nonresponse Adjusted Replicate Weight (\d+)$")

# Get sorted list of replicate weight columns
def _rep_cols(df: pd.DataFrame) -> list[str]:
    cols = [c for c in df.columns if _REP_RE.match(c)]
    if not cols:
        raise ValueError("No CBECS replicate weight columns found.")
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

# Compute jackknife variance
def _jk_var(theta: float, rep_thetas: np.ndarray, kappa: float) -> float:
    return float(kappa * np.sum((rep_thetas - theta) ** 2))

## Calibrate kappa for total estimate to achieve target RSE TODO enable if needed but currently estimates appear to work well without calibration
# def calibrate_kappa_for_total(
#     df: pd.DataFrame,
#     value_col: str,
#     weight_col: str = "weight",
#     universe_mask: Optional[pd.Series] = None,
#     target_rse: Optional[float] = None,  # e.g. 0.031 for 3.1%
# ) -> float:
#     """If target_rse is None -> default JK coeff (R-1)/R. Otherwise solve for kappa."""
#     reps = _rep_cols(df)
#     if universe_mask is None:
#         universe_mask = pd.Series(True, index=df.index)

#     sub = df.loc[universe_mask, [value_col, weight_col] + reps].copy()
#     sub[value_col] = _to_num(sub[value_col]); sub[weight_col] = _to_num(sub[weight_col])
#     for c in reps: sub[c] = _to_num(sub[c])
#     sub = sub.replace([np.inf, -np.inf], np.nan).dropna(subset=[value_col, weight_col])

#     theta, rep_thetas = _theta_and_reps(sub[value_col], sub[weight_col], sub[reps])
#     R = len(reps)
#     if not target_rse:
#         return (R - 1) / R

#     target_var = (target_rse * theta) ** 2
#     ss = float(np.sum((rep_thetas - theta) ** 2))
#     if ss == 0:
#         raise ValueError("Cannot calibrate kappa: replicate deviations are all zero.")
#     return target_var / ss


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

    # If already_weighted, recover unweighted value
    if already_weighted:
        # Avoid division by zero
        sub["_unweighted_value"] = sub[value_col] / sub[weight_col].replace(0, np.nan)
        value_col_for_calc = "_unweighted_value"
    else:
        value_col_for_calc = value_col

    if kappa is None:
        R = len(reps); kappa = (R - 1) / R

    rows = []
    for keys, g in sub.groupby(list(by), dropna=False):
        theta, rep_thetas = _theta_and_reps(g[value_col_for_calc], g[weight_col], g[reps])
        var = _jk_var(theta, rep_thetas, kappa)
        se = float(np.sqrt(var)); rse = 100.0 * se / theta if theta else np.nan
        ci_low = max(theta - 1.96*se, 0)
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
    for keys, g in sub.groupby(list(by), dropna=False):
        w = g[weight_col]; x = g[value_col]
        num = float(np.nansum(w*x)); den = float(np.nansum(w))
        theta = num/den if den else np.nan
        rep_t = []
        for c in reps:
            wr = g[c]; num_r = float(np.nansum(wr*x)); den_r = float(np.nansum(wr))
            rep_t.append(num_r/den_r if den_r else np.nan)
        rep_t = np.array(rep_t, float)
        var = _jk_var(theta, rep_t, kappa)
        se = float(np.sqrt(var)); rse = 100.0*se/theta if theta else np.nan
        ci_low = max(theta - 1.96*se, 0)
        ci_high = theta + 1.96*se
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
    for keys, g in sub.groupby(list(by), dropna=False):
        w = g[weight_col]
        num = float(np.nansum(w*g[numer_col])); den = float(np.nansum(w*g[denom_col]))
        theta = num/den if den else np.nan
        rep_t = []
        for c in reps:
            wr = g[c]
            num_r = float(np.nansum(wr*g[numer_col])); den_r = float(np.nansum(wr*g[denom_col]))
            rep_t.append(num_r/den_r if den_r else np.nan)
        rep_t = np.array(rep_t, float)
        var = _jk_var(theta, rep_t, kappa)
        se = float(np.sqrt(var)); rse = 100.0*se/theta if theta else np.nan
        ci_low = max(theta - 1.96*se, 0)
        ci_high = theta + 1.96*se
        rows.append({**{b: (keys[i] if isinstance(keys, tuple) else keys) for i, b in enumerate(by)},
                     "estimate": theta, "se": se, "rse_pct": rse,
                     "ci95_low": ci_low, "ci95_high": ci_high})
    return pd.DataFrame(rows)
