"""
Query templates and builders for ComStock data extraction from Athena.

This module provides SQL query templates and builder functions to construct
Athena queries for various ComStock analysis needs, separating query logic
from the main ComStock processing classes.
"""

import logging
from typing import Dict, List, Optional, Union

logger = logging.getLogger(__name__)


class ComStockQueryBuilder:
    """
    Builder class for creating SQL queries to extract ComStock data from Athena.

    This class provides templated queries that can be customized with parameters
    for different analysis needs while maintaining consistent query structure.
    """

    def __init__(self, athena_table_name: str):
        """
        Initialize the query builder with the base Athena table name.

        Args:
            athena_table_name: Base name of the Athena table (without _timeseries or _baseline suffix)
        """
        self.athena_table_name = athena_table_name
        self.timeseries_table = f"{athena_table_name}_timeseries"
        self.baseline_table = f"{athena_table_name}_baseline"

    def get_monthly_energy_consumption_query(self,
                                           upgrade_ids: Optional[List[Union[int, str]]] = None,
                                           states: Optional[List[str]] = None,
                                           building_types: Optional[List[str]] = None) -> str:
        """
        Build query for monthly natural gas and electricity consumption by state and building type.

        Args:
            upgrade_ids: List of upgrade IDs to filter on (optional)
            states: List of state IDs to filter on (optional)
            building_types: List of building types to filter on (optional)

        Returns:
            SQL query string
        """

        ## Build WHERE clause conditions
        #where_conditions = ['"build_existing_model.building_type" IS NOT NULL']

        #if upgrade_ids:
        #    upgrade_list = ', '.join([f'"{uid}"' for uid in upgrade_ids])
        #    where_conditions.append(f'"upgrade" IN ({upgrade_list})')

        #if states:
        #    state_list = ', '.join([f'"{state}"' for state in states])
        #    where_conditions.append(f'SUBSTRING("build_existing_model.county_id", 2, 2) IN ({state_list})')

        #if building_types:
        #    btype_list = ', '.join([f'"{bt}"' for bt in building_types])
        #    where_conditions.append(f'"build_existing_model.create_bar_from_building_type_ratios_bldg_type_a" IN ({btype_list})')

        #where_clause = ' AND '.join(where_conditions)

        #query = f"""
        #    SELECT
        #        "upgrade",
        #        "month",
        #        "state_id",
        #        "building_type",
        #        sum("total_site_gas_kbtu") AS "total_site_gas_kbtu",
        #        sum("total_site_electricity_kwh") AS "total_site_electricity_kwh"
        #    FROM
        #    (
        #        SELECT
        #            EXTRACT(MONTH from "time") as "month",
        #            SUBSTRING("build_existing_model.county_id", 2, 2) AS "state_id",
        #            "build_existing_model.create_bar_from_building_type_ratios_bldg_type_a" as "building_type",
        #            "upgrade",
        #            "total_site_gas_kbtu",
        #            "total_site_electricity_kwh"
        #        FROM
        #            "{self.timeseries_table}"
        #        JOIN "{self.baseline_table}"
        #            ON "{self.timeseries_table}"."building_id" = "{self.baseline_table}"."building_id"
        #        WHERE {where_clause}
        #    )
        #    GROUP BY
        #        "upgrade",
        #        "month",
        #        "state_id",
        #        "building_type"
        #"""

        #return query.strip()

    def get_timeseries_aggregation_query(self,
                                       upgrade_id: Union[int, str],
                                       enduses: List[str],
                                       restrictions: List[tuple] = None,
                                       timestamp_grouping: str = 'hour',
                                       building_ids: Optional[List[int]] = None,
                                       weight_view_table: Optional[str] = None,
                                       include_sample_stats: bool = True) -> str:
        """
        Build query for timeseries data aggregation similar to buildstock query functionality.

        This matches the pattern from working buildstock queries that join timeseries data
        with a weight view table for proper weighting and aggregation.

        Args:
            upgrade_id: Upgrade ID to filter on
            enduses: List of end use columns to select
            restrictions: List of (column, values) tuples for filtering
            timestamp_grouping: How to group timestamps ('hour', 'day', 'month')
            building_ids: Specific building IDs to filter on (optional)
            weight_view_table: Name of the weight view table (e.g., 'rtuadv_v11_md_agg_national_by_state_vu')
            include_sample_stats: Whether to include sample_count, units_count, rows_per_sample

        Returns:
            SQL query string
        """

        # If no weight view table provided, construct default name
        if weight_view_table is None:
            weight_view_table = f"{self.athena_table_name}_md_agg_national_by_state_vu" #TODO: make table name dynamic to aggregation level

        # Build timestamp grouping with date_trunc and time adjustment (like buildstock does)
        if timestamp_grouping == 'hour':
            time_select = f"date_trunc('hour', date_add('second', -900, {self.timeseries_table}.time)) AS time"
            time_group = '1'
        elif timestamp_grouping == 'day':
            time_select = f"date_trunc('day', {self.timeseries_table}.time) AS time"
            time_group = '1'
        elif timestamp_grouping == 'month':
            time_select = f"date_trunc('month', {self.timeseries_table}.time) AS time"
            time_group = '1'
        else:
            time_select = f"{self.timeseries_table}.time AS time"
            time_group = '1'

        # Build SELECT clause with sample statistics (matching buildstock pattern)
        select_clauses = [time_select]

        if include_sample_stats:
            select_clauses.extend([
                f"count(distinct({self.timeseries_table}.building_id)) AS sample_count",
                f"(count(distinct({self.timeseries_table}.building_id)) * sum(1 * {weight_view_table}.weight)) / sum(1) AS units_count",
                f"sum(1) / count(distinct({self.timeseries_table}.building_id)) AS rows_per_sample"
            ])

        # Build weighted enduse aggregations
        for enduse in enduses:
            weighted_sum = f"sum({self.timeseries_table}.{enduse} * 1 * {weight_view_table}.weight) AS {enduse}"
            select_clauses.append(weighted_sum)

        select_clause = ',\n    '.join(select_clauses)

        # Build WHERE clause - join conditions first, then filters
        where_conditions = [
            f'{weight_view_table}."bldg_id" = {self.timeseries_table}.building_id',
            f'{weight_view_table}.upgrade = {self.timeseries_table}.upgrade',
            f'{weight_view_table}.upgrade = {upgrade_id}'
        ]

        if building_ids:
            bldg_list = ', '.join([str(bid) for bid in building_ids])
            where_conditions.append(f'{weight_view_table}."bldg_id" IN ({bldg_list})')

        # Handle restrictions - these are typically filters on the weight view table
        if restrictions:
            for column, values in restrictions:
                # Determine if this is a numeric column that shouldn't be quoted
                numeric_columns = ['bldg_id', 'building_id', 'upgrade', 'upgrade_id']
                is_numeric = column in numeric_columns

                if isinstance(values, (list, tuple)):
                    if len(values) == 1:
                        if is_numeric:
                            where_conditions.append(f'{weight_view_table}."{column}" = {values[0]}')
                        else:
                            where_conditions.append(f'{weight_view_table}."{column}" = \'{values[0]}\'')
                    else:
                        if is_numeric:
                            value_list = ', '.join([str(v) for v in values])
                        else:
                            value_list = ', '.join([f"'{v}'" for v in values])
                        where_conditions.append(f'{weight_view_table}."{column}" IN ({value_list})')
                else:
                    if is_numeric:
                        where_conditions.append(f'{weight_view_table}."{column}" = {values}')
                    else:
                        where_conditions.append(f'{weight_view_table}."{column}" = \'{values}\'')

        where_clause = ' AND '.join(where_conditions)

        # Build the query using FROM clause with comma-separated tables (like buildstock)
        query = f"""SELECT {select_clause}
        FROM {weight_view_table}, {self.timeseries_table}
        WHERE {where_clause}
        GROUP BY {time_group}
        ORDER BY {time_group}"""

        return query

    def get_timeseries_aggregation_query_with_join(self,
                                                 upgrade_id: Union[int, str],
                                                 enduses: List[str],
                                                 restrictions: List[tuple] = None,
                                                 timestamp_grouping: str = 'hour',
                                                 building_ids: Optional[List[int]] = None) -> str:
        """
        Alternative version using JOIN syntax instead of comma-separated FROM clause.
        Use this if you prefer explicit JOIN syntax over the buildstock comma-style.
        """

        # Build SELECT clause for enduses
        enduse_selects = []
        for enduse in enduses:
            enduse_selects.append(f'sum("{enduse}") AS "{enduse}"')

        enduse_clause = ',\n                '.join(enduse_selects)

        # Build timestamp grouping
        if timestamp_grouping == 'hour':
            time_select = 'EXTRACT(HOUR from "time") as "hour"'
            time_group = '"hour"'
        elif timestamp_grouping == 'day':
            time_select = 'EXTRACT(DAY from "time") as "day"'
            time_group = '"day"'
        elif timestamp_grouping == 'month':
            time_select = 'EXTRACT(MONTH from "time") as "month"'
            time_group = '"month"'
        else:
            time_select = '"time"'
            time_group = '"time"'

        # Build WHERE clause
        where_conditions = [f'"upgrade" = "{upgrade_id}"']

        if building_ids:
            bldg_list = ', '.join([str(bid) for bid in building_ids])
            where_conditions.append(f'"{self.timeseries_table}"."building_id" IN ({bldg_list})')

        if restrictions:
            for column, values in restrictions:
                if isinstance(values, (list, tuple)):
                    value_list = ', '.join([f'"{v}"' for v in values])
                    where_conditions.append(f'"{column}" IN ({value_list})')
                else:
                    where_conditions.append(f'"{column}" = "{values}"')

        where_clause = ' AND '.join(where_conditions)

        query = f"""
            SELECT
                {time_select},
                {enduse_clause}
            FROM
                "{self.timeseries_table}"
            JOIN "{self.baseline_table}"
                ON "{self.timeseries_table}"."building_id" = "{self.baseline_table}"."building_id"
            WHERE {where_clause}
            GROUP BY
                {time_group}
            ORDER BY
                {time_group}
        """

        return query.strip()

    def get_building_characteristics_query(self,
                                         upgrade_ids: Optional[List[Union[int, str]]] = None,
                                         characteristics: Optional[List[str]] = None,
                                         filters: Optional[Dict[str, Union[str, List[str]]]] = None) -> str:
        """
        Build query to extract building characteristics and metadata.

        Args:
            upgrade_ids: List of upgrade IDs to include (optional, defaults to all)
            characteristics: Specific characteristic columns to select (optional)
            filters: Dictionary of column: value(s) filters to apply

        Returns:
            SQL query string
        """

        # Default characteristics if none specified
        if characteristics is None:
            characteristics = [
                'building_id',
                'upgrade',
                'build_existing_model.building_type',
                'build_existing_model.county_id',
                'build_existing_model.create_bar_from_building_type_ratios_bldg_type_a',
                'in.sqft',
                'in.geometry_building_type_recs'
            ]

        # Build SELECT clause
        select_clause = ',\n                '.join([f'"{char}"' for char in characteristics])

        # Build WHERE clause
        where_conditions = []

        if upgrade_ids:
            upgrade_list = ', '.join([f'"{uid}"' for uid in upgrade_ids])
            where_conditions.append(f'"upgrade" IN ({upgrade_list})')

        if filters:
            for column, values in filters.items():
                if isinstance(values, (list, tuple)):
                    value_list = ', '.join([f'"{v}"' for v in values])
                    where_conditions.append(f'"{column}" IN ({value_list})')
                else:
                    where_conditions.append(f'"{column}" = "{values}"')

        where_clause = 'WHERE ' + ' AND '.join(where_conditions) if where_conditions else ''

        query = f"""
            SELECT
                {select_clause}
            FROM
                "{self.baseline_table}"
            {where_clause}
        """

        return query.strip()

    def get_applicability_query(self,
                               upgrade_ids: List[Union[int, str]],
                               state: Optional[Union[str, List[str]]] = None,
                               county: Optional[Union[str, List[str]]] = None,
                               columns: Optional[List[str]] = None,
                               weight_view_table: Optional[str] = None) -> str:
        """
        Build query to get applicable buildings and their characteristics from the weight view.

        Args:
            upgrade_ids: List of upgrade IDs to filter on
            state: State abbreviation(s) to filter on (optional, can be single string or list)
            county: County GISJOIN(s) to filter on (optional, can be single string or list)
            columns: Specific columns to select (optional, defaults to common applicability columns)
            weight_view_table: Name of the weight view table (optional, uses default naming)

        Returns:
            SQL query string
        """

        # If no weight view table provided, construct default name
        if weight_view_table is None:
            weight_view_table = f"{self.athena_table_name}_md_agg_national_by_state_vu"

        # Default columns for applicability queries
        if columns is None:
            # Choose geographic column based on which filter is being used
            geo_column = '"in.nhgis_county_gisjoin"' if county else '"in.state"'
            columns = [
                'dataset',
                geo_column,
                'bldg_id',
                'upgrade',
                'applicability'
            ]

        # Build SELECT clause
        select_clause = ',\n            '.join(columns)

        # Build WHERE clause
        where_conditions = []

        # Filter by upgrade IDs
        if len(upgrade_ids) == 1:
            where_conditions.append(f'upgrade = {upgrade_ids[0]}')
        else:
            upgrade_list = ','.join(map(str, upgrade_ids))
            where_conditions.append(f'upgrade IN ({upgrade_list})')

        # Filter by applicability
        where_conditions.append('applicability = true')

        # Filter by geographic location (state or county) - support single values or lists
        if state:
            if isinstance(state, str):
                where_conditions.append(f'"in.state" = \'{state}\'')
            elif isinstance(state, (list, tuple)):
                if len(state) == 1:
                    where_conditions.append(f'"in.state" = \'{state[0]}\'')
                else:
                    state_list = "', '".join(state)
                    where_conditions.append(f'"in.state" IN (\'{state_list}\')')
        elif county:
            if isinstance(county, str):
                where_conditions.append(f'"in.nhgis_county_gisjoin" = \'{county}\'')
            elif isinstance(county, (list, tuple)):
                if len(county) == 1:
                    where_conditions.append(f'"in.nhgis_county_gisjoin" = \'{county[0]}\'')
                else:
                    county_list = "', '".join(county)
                    where_conditions.append(f'"in.nhgis_county_gisjoin" IN (\'{county_list}\')')

        where_clause = ' AND '.join(where_conditions)

        query = f"""
        SELECT DISTINCT
            {select_clause}
        FROM {weight_view_table}
        WHERE {where_clause}
        ORDER BY bldg_id
        """

        return query.strip()


def get_monthly_energy_query(athena_table_name: str, **kwargs) -> str:
    """
    Convenience function to get monthly energy consumption query.

    Args:
        athena_table_name: Base Athena table name
        **kwargs: Additional arguments passed to get_monthly_energy_consumption_query

    Returns:
        SQL query string
    """
    builder = ComStockQueryBuilder(athena_table_name)
    return builder.get_monthly_energy_consumption_query(**kwargs)


def get_timeseries_query(athena_table_name: str, **kwargs) -> str:
    """
    Convenience function to get timeseries aggregation query.

    Args:
        athena_table_name: Base Athena table name
        **kwargs: Additional arguments passed to get_timeseries_aggregation_query

    Returns:
        SQL query string
    """
    builder = ComStockQueryBuilder(athena_table_name)
    return builder.get_timeseries_aggregation_query(**kwargs)


def get_building_chars_query(athena_table_name: str, **kwargs) -> str:
    """
    Convenience function to get building characteristics query.

    Args:
        athena_table_name: Base Athena table name
        **kwargs: Additional arguments passed to get_building_characteristics_query

    Returns:
        SQL query string
    """
    builder = ComStockQueryBuilder(athena_table_name)
    return builder.get_building_characteristics_query(**kwargs)


# Query template constants for common patterns
MONTHLY_ENERGY_TEMPLATE = """
SELECT
    "upgrade",
    "month",
    "state_id",
    "building_type",
    sum("total_site_gas_kbtu") AS "total_site_gas_kbtu",
    sum("total_site_electricity_kwh") AS "total_site_electricity_kwh"
FROM
(
    SELECT
        EXTRACT(MONTH from "time") as "month",
        SUBSTRING("build_existing_model.county_id", 2, 2) AS "state_id",
        "build_existing_model.create_bar_from_building_type_ratios_bldg_type_a" as "building_type",
        "upgrade",
        "total_site_gas_kbtu",
        "total_site_electricity_kwh"
    FROM
        "{timeseries_table}"
    JOIN "{baseline_table}"
        ON "{timeseries_table}"."building_id" = "{baseline_table}"."building_id"
    WHERE {where_clause}
)
GROUP BY
    "upgrade",
    "month",
    "state_id",
    "building_type"
"""

TIMESERIES_AGG_TEMPLATE = """
SELECT
    {time_grouping},
    {enduse_aggregations}
FROM
    "{timeseries_table}"
JOIN "{baseline_table}"
    ON "{timeseries_table}"."building_id" = "{baseline_table}"."building_id"
WHERE {where_clause}
GROUP BY
    {time_grouping}
ORDER BY
    {time_grouping}
"""