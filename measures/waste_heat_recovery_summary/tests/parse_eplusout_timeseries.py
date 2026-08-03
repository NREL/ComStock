#!/usr/bin/env python3
"""Extract selected EnergyPlus timeseries variables from eplusout.sql.

By default this exports variables containing either:
- Heating Coil Heating Energy
- Cooling Coil Total Cooling Energy
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path


DEFAULT_PATTERNS = [
    "Heating Coil Heating Energy",
    "Cooling Coil Total Cooling Energy",
]

HEATING_VAR = "Heating Coil Heating Energy"
COOLING_VAR = "Cooling Coil Total Cooling Energy"
PLUGIN_VAR_NAME = "PythonPlugin:OutputVariable"
PLUGIN_HEATING_KEY = "total_heating_coil_energy"
PLUGIN_COOLING_KEY = "total_cooling_coil_energy"


def pick_existing_table(conn: sqlite3.Connection, candidates: list[str]) -> str:
    existing = {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
    }
    for name in candidates:
        if name in existing:
            return name
    raise ValueError(f"None of these tables exist: {candidates}")


def table_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def first_existing(columns: set[str], names: list[str], label: str) -> str:
    for name in names:
        if name in columns:
            return name
    raise ValueError(f"Could not find {label}. Tried: {names}")


def get_schema_info(conn: sqlite3.Connection) -> dict[str, str]:
    dict_table = pick_existing_table(
        conn,
        ["ReportDataDictionary", "ReportVariableDataDictionary"],
    )
    data_table = pick_existing_table(conn, ["ReportData", "ReportVariableData"])
    time_table = pick_existing_table(conn, ["Time"])

    dict_cols = table_columns(conn, dict_table)
    data_cols = table_columns(conn, data_table)
    time_cols = table_columns(conn, time_table)

    return {
        "dict_table": dict_table,
        "data_table": data_table,
        "time_table": time_table,
        "dict_id_col": first_existing(
            dict_cols,
            ["ReportDataDictionaryIndex", "ReportVariableDataDictionaryIndex"],
            "dictionary ID column",
        ),
        "data_dict_id_col": first_existing(
            data_cols,
            ["ReportDataDictionaryIndex", "ReportVariableDataDictionaryIndex"],
            "data->dictionary ID column",
        ),
        "data_time_col": first_existing(
            data_cols,
            ["TimeIndex"],
            "data time index column",
        ),
        "data_value_col": first_existing(
            data_cols,
            ["VariableValue", "Value"],
            "data value column",
        ),
        "variable_name_col": first_existing(
            dict_cols,
            ["VariableName", "Name"],
            "variable name column",
        ),
        "key_value_col": first_existing(
            dict_cols,
            ["KeyValue", "KeyName"],
            "key value column",
        ),
        "units_col": first_existing(dict_cols, ["VariableUnits", "Units"], "units column"),
        "freq_col": first_existing(
            dict_cols,
            ["ReportingFrequency", "Frequency"],
            "reporting frequency column",
        ),
        "time_year_col": "Year" if "Year" in time_cols else "NULL",
        "time_month_col": "Month" if "Month" in time_cols else "NULL",
        "time_day_col": "Day" if "Day" in time_cols else "NULL",
        "time_hour_col": "Hour" if "Hour" in time_cols else "NULL",
        "time_minute_col": "Minute" if "Minute" in time_cols else "NULL",
        "time_interval_col": "Interval" if "Interval" in time_cols else "NULL",
        "time_simdays_col": "SimulationDays" if "SimulationDays" in time_cols else "NULL",
        "time_env_col": "EnvironmentPeriodIndex" if "EnvironmentPeriodIndex" in time_cols else "NULL",
        "time_warmup_col": "WarmupFlag" if "WarmupFlag" in time_cols else "NULL",
    }


def print_comparison(label: str, component_sum: float, plugin_total: float) -> None:
    delta = component_sum - plugin_total
    percent = (delta / plugin_total * 100.0) if plugin_total != 0 else 0.0
    print(
        f"{label}: components={component_sum:.6g}, "
        f"plugin={plugin_total:.6g}, delta={delta:.6g}, delta_pct={percent:.6f}%"
    )


def extract_timeseries(
    sql_path: Path,
    output_csv: Path,
    variable_patterns: list[str],
) -> int:
    conn = sqlite3.connect(sql_path)
    try:
        schema = get_schema_info(conn)
        dict_table = schema["dict_table"]
        data_table = schema["data_table"]
        time_table = schema["time_table"]
        dict_id_col = schema["dict_id_col"]
        data_dict_id_col = schema["data_dict_id_col"]
        data_time_col = schema["data_time_col"]
        data_value_col = schema["data_value_col"]
        variable_name_col = schema["variable_name_col"]
        key_value_col = schema["key_value_col"]
        units_col = schema["units_col"]
        freq_col = schema["freq_col"]

        where_clauses = " OR ".join(
            [f"d.{variable_name_col} LIKE ?" for _ in variable_patterns]
        )
        where_params = [f"%{pattern}%" for pattern in variable_patterns]

        # Guard against duplicate time rows per TimeIndex in some SQL variants.
        time_cte = f"""
            time_index_dedup AS (
                SELECT
                    TimeIndex AS time_index,
                    MIN({schema['time_year_col']}) AS year,
                    MIN({schema['time_month_col']}) AS month,
                    MIN({schema['time_day_col']}) AS day,
                    MIN({schema['time_hour_col']}) AS hour,
                    MIN({schema['time_minute_col']}) AS minute,
                    MIN({schema['time_interval_col']}) AS interval_minutes,
                    MIN({schema['time_simdays_col']}) AS simulation_day,
                    MIN({schema['time_env_col']}) AS environment_period_index,
                    MIN({schema['time_warmup_col']}) AS warmup_flag
                FROM {time_table}
                GROUP BY TimeIndex
            )
        """

        sql = f"""
            WITH {time_cte}
            SELECT
                d.{variable_name_col} AS variable_name,
                d.{key_value_col} AS key_value,
                d.{units_col} AS units,
                d.{freq_col} AS reporting_frequency,
                t.time_index AS time_index,
                t.month AS month,
                t.day AS day,
                t.hour AS hour,
                t.minute AS minute,
                t.interval_minutes AS interval_minutes,
                t.simulation_day AS simulation_day,
                t.environment_period_index AS environment_period_index,
                r.{data_value_col} AS value
            FROM {data_table} r
            JOIN {dict_table} d
              ON r.{data_dict_id_col} = d.{dict_id_col}
            LEFT JOIN time_index_dedup t
              ON r.{data_time_col} = t.time_index
            WHERE ({where_clauses})
            ORDER BY
                d.{variable_name_col},
                d.{key_value_col},
                t.environment_period_index,
                t.simulation_day,
                t.time_index
        """

        output_csv.parent.mkdir(parents=True, exist_ok=True)
        with output_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "variable_name",
                    "key_value",
                    "units",
                    "reporting_frequency",
                    "environment_period_index",
                    "simulation_day",
                    "month",
                    "day",
                    "hour",
                    "minute",
                    "interval_minutes",
                    "time_index",
                    "value",
                ]
            )

            count = 0
            for row in conn.execute(sql, where_params):
                writer.writerow(row)
                count += 1

        return count
    finally:
        conn.close()


def compare_component_and_plugin_totals(sql_path: Path, frequency: str) -> None:
    conn = sqlite3.connect(sql_path)
    try:
        schema = get_schema_info(conn)
        dict_table = schema["dict_table"]
        data_table = schema["data_table"]
        dict_id_col = schema["dict_id_col"]
        data_dict_id_col = schema["data_dict_id_col"]
        data_value_col = schema["data_value_col"]
        variable_name_col = schema["variable_name_col"]
        key_value_col = schema["key_value_col"]
        freq_col = schema["freq_col"]

        component_query = f"""
            SELECT d.{variable_name_col}, COALESCE(SUM(r.{data_value_col}), 0.0)
            FROM {data_table} r
            JOIN {dict_table} d
              ON r.{data_dict_id_col} = d.{dict_id_col}
            WHERE d.{freq_col} = ?
              AND d.{variable_name_col} IN (?, ?)
            GROUP BY d.{variable_name_col}
        """
        component_rows = conn.execute(
            component_query,
            [
                frequency,
                HEATING_VAR,
                COOLING_VAR,
            ],
        ).fetchall()
        sums = {name: float(total) for name, total in component_rows}

        plugin_query = f"""
            SELECT d.{key_value_col}, COALESCE(SUM(r.{data_value_col}), 0.0)
            FROM {data_table} r
            JOIN {dict_table} d
              ON r.{data_dict_id_col} = d.{dict_id_col}
            WHERE d.{freq_col} = ?
              AND d.{variable_name_col} = ?
              AND d.{key_value_col} IN (?, ?)
            GROUP BY d.{key_value_col}
        """
        plugin_rows = conn.execute(
            plugin_query,
            [
                frequency,
                PLUGIN_VAR_NAME,
                PLUGIN_HEATING_KEY,
                PLUGIN_COOLING_KEY,
            ],
        ).fetchall()
        plugin_sums = {name: float(total) for name, total in plugin_rows}

        missing = [name for name in [HEATING_VAR, COOLING_VAR] if name not in sums]
        missing_plugin = [
            name
            for name in [PLUGIN_HEATING_KEY, PLUGIN_COOLING_KEY]
            if name not in plugin_sums
        ]
        if missing or missing_plugin:
            missing_msg = []
            if missing:
                missing_msg.append("component variables: " + ", ".join(missing))
            if missing_plugin:
                missing_msg.append("plugin keys: " + ", ".join(missing_plugin))
            raise ValueError(
                "Missing required variables at frequency "
                f"'{frequency}': {'; '.join(missing_msg)}"
            )

        print(f"Comparison frequency: {frequency}")
        print_comparison(
            "Heating coil energy check",
            sums[HEATING_VAR],
            plugin_sums[PLUGIN_HEATING_KEY],
        )
        print_comparison(
            "Cooling coil energy check",
            sums[COOLING_VAR],
            plugin_sums[PLUGIN_COOLING_KEY],
        )
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract heating/cooling coil energy timeseries from eplusout.sql"
    )
    parser.add_argument("input_sql", type=Path, help="Path to eplusout.sql")
    parser.add_argument("output_csv", type=Path, help="Path to output CSV")
    parser.add_argument(
        "--pattern",
        action="append",
        default=[],
        help=(
            "Variable name substring filter. Can be repeated. "
            "Defaults to heating and cooling coil patterns."
        ),
    )
    parser.add_argument(
        "--comparison-frequency",
        default="Zone Timestep",
        help="ReportingFrequency to use for component vs plugin total comparison.",
    )
    parser.add_argument(
        "--skip-comparison",
        action="store_true",
        help="Skip aggregate comparison against PythonPlugin total variables.",
    )
    args = parser.parse_args()

    patterns = args.pattern if args.pattern else DEFAULT_PATTERNS
    count = extract_timeseries(args.input_sql, args.output_csv, patterns)
    print(f"Extracted {count} rows to {args.output_csv}")
    print("Patterns used:")
    for pattern in patterns:
        print(f"- {pattern}")

    if not args.skip_comparison:
        compare_component_and_plugin_totals(
            args.input_sql,
            args.comparison_frequency,
        )


if __name__ == "__main__":
    main()
