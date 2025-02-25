import os
import re
import json
import boto3
import logging
import shapely
import botocore
import numpy as np
import pandas as pd
import geopandas as gpd
from datetime import datetime
from shapely import difference
from shapely.ops import unary_union
from shapely.geometry import MultiPolygon
from shapely.geometry.collection import GeometryCollection
from comstockpostproc.s3_utilities_mixin import S3UtilitiesMixin
from comstockpostproc.gap.eia861 import EIA861
from comstockpostproc.gap.eia930 import EIA930

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S')
logger = logging.getLogger(__name__)

class BAGeography(S3UtilitiesMixin):
    def __init__(self, truth_data_version='v01', reload_from_saved=True, save_processed=True):
        """
        A class to generate a dataset mapping EIA Balancing Authorities to US census tracts to the fraction of Commercial/Residential/Industrial building floor area in that tract to that BA.
        This currently uses the following input data sources:
            - Electric Retail Service Territories data from https://atlas.eia.gov/datasets/geoplatform::electric-retail-service-territories-2/explore
            - US State TIGER/Line Shapefile
            - US Structures data from FEMA: https://disasters.geoplatform.gov/USA_Structures/ https://www.nature.com/articles/s41597-024-03219-x

            Note - other sources of interest that are not (yet) used in this:
                - Balancing Authorities shapefile: https://atlas.eia.gov/datasets/eia::balancing-authorities/about (this appears to have been published after my initial version. Does contain overlaps)
            
        Args:
            truth_data_version (string): The version of truth data. 'v01'
            reload_from_saved (Bool): reload from processed data if available
            save_processed (Bool): Flag to save out processed files of: de-overlapped service territories, de-overlapped Balancing Authority in parquet format
        Attributes:
            utility_territories_data (GeoDataFrame): GeoDataFrame of non-overlapping Electric Utility Service Territory geometries by states. Processing time approx 2m 45s
            balancing_authority_territories_data (GeoDataFrame): GeoDataFrame of non-overlapping Balancing Authority geometries by state. Processing time approx 44s
            balancing_authority_bldg_areas_data (DataFrame): DataFrame of estimated total floor areas by Balancing Authority and Census Tract
        """

        self.truth_data_version = truth_data_version
        self.reload_from_saved = reload_from_saved
        self.save_processed = save_processed
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.truth_data_dir = os.path.join(current_dir, '..', '..', 'truth_data', self.truth_data_version)
        self.processed_dir = os.path.join(self.truth_data_dir, 'gap_processed')
        self.output_dir = os.path.join(current_dir, 'output')

        self.processed_filename = 'ba_tract_areas.parquet'

        # initialize s3 client
        self.s3_client = boto3.client('s3', config=botocore.client.Config(max_pool_connections=50))
        self.s3_resource = boto3.resource('s3')

        # make directories
        for p in [self.truth_data_dir, self.processed_dir, self.output_dir]:
            if not os.path.exists(p):
                os.makedirs(p)
        
        # # reload from csv
        # if self.reload_from_csv:
        #     logger.info('Reloading data from CSV')
        #     processed_path = os.path.join(self.processed_dir, self.processed_filename)
        #     if os.path.exists(processed_path):
        #         self.data = pd.read_csv(processed_path, index_col=0)
        #     else:
        #         logger.warning(f'No processed data found for {self.processed_filename}. Processing from truth data.')
                # self.data = self.create_ba_geomap()
        # else:
            # self.data = self.create_ba_geomap()

    def download_truth_shapefiles(self, shapefile_name):
        local_path = os.path.join(self.truth_data_dir, shapefile_name)
        if not os.path.isfile(os.path.join(local_path, shapefile_name + '.shp')):
            os.makedirs(local_path)
            try:
                logger.info('Downloading %s from s3...' % shapefile_name)
                s3_files_path = f'truth_data/{self.truth_data_version}/shapefiles/{shapefile_name}/'
                bucket = self.s3_resource.Bucket('eulp')
                for obj in bucket.objects.filter(Prefix=s3_files_path):
                    bucket.download_file(obj.key, os.path.join(local_path, os.path.basename(obj.key)))
            except:
                logger.error(f'Error downloading files at {shapefile_name}')
                exit(code=1)

    def load_shapefile_df(self, shapefile_name):
        local_path = os.path.join(self.truth_data_dir, shapefile_name, shapefile_name + '.shp')
        if not os.path.exists(local_path):
            self.download_truth_shapefiles(shapefile_name)

        df = gpd.read_file(local_path)
        return df
    
    def download_structures_parquet(self, dir_name, file_name):
        local_dir = os.path.join(self.truth_data_dir, 'structures')
        local_path = os.path.join(local_dir, file_name)
        if not os.path.exists(local_dir):
            os.makedirs(local_dir)
        try:
            logger.info('Downloading %s from s3...' % file_name)
            s3_file_path = f'truth_data/{self.truth_data_version}/structures/{dir_name}/{file_name}'
            bucket_name = 'eulp'
            self.s3_client.download_file(bucket_name, s3_file_path, local_path)
        except:
            logger.error(f'Error downloading structures file {file_name}')
            exit(code=1)

    def load_structures_parquet(self, dir_name, file_name):
        local_path = os.path.join(self.truth_data_dir, 'structures', file_name)
        if not os.path.exists(local_path):
            self.download_structures_parquet(dir_name, file_name)
        
        df = gpd.read_parquet(local_path)
        return df

    def utility_territories_data(self):
        """
        Returns a geodataframe of non-overlapping Electric Utility Service Territories by state, coded to Utility ID and Balancing Authorty abbreviation.
        """
        processed_filename = 'utility_territories_processed.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved:
            if os.path.exists(processed_path):
                logger.info('Reloading Utility Territories from saved parquet')
                gdf = gpd.read_parquet(processed_path)
                return gdf
            else: 
                logger.warning(f'No processed data found for {processed_filename}. Processing from truth data')

        logger.info('Processing Electric Retail Service Territories from truth data')

        # load retail service territories
        service_territories = self.load_shapefile_df('Electric_Retail_Service_Territories')
        service_territories = service_territories[['NAME', 'ID', 'STATE', 'CNTRL_AREA', 'HOLDING_CO', 'PLAN_AREA', 'SOURCE', 'geometry']]
        
        logger.info(f'Electric Retail Service Territories loaded with {len(service_territories.index)} rows')

        # Load states shapefile and align coordinate system
        states_shapes = self.load_shapefile_df('tl_2020_us_state').to_crs(service_territories.crs)
        logger.info(f'US states loaded with {len(states_shapes.index)} rows')

        # filter shapes to CONUS
        state_labels = self.read_delimited_truth_data_file_from_S3(f'truth_data/{self.truth_data_version}/national_state2020.txt', '|')
        state_labels['STATEFP'] = state_labels['STATEFP'].astype(str).str.zfill(2)
        state_labels.set_index('STATEFP', drop=True, inplace=True)
        not_conus = ['02','15','60','66','69','72','74','78'] 
        conus_labels = state_labels.drop(not_conus)

        # filter to CONUS
        conus_shapes = states_shapes[states_shapes['GEOID'].isin(conus_labels.index)]
        logger.info(f'Dropped {len(not_conus)} states from states shapefile - not part of CONUS.')

        # overlay states onto service territories
        logger.info('Overlaying CONUS states onto electric service territories')
        eia_by_state = gpd.overlay(
            service_territories,
            conus_shapes,
            how='intersection',
            keep_geom_type=False
        )
        
        logger.info(f'Service Territories divided by states yields {len(eia_by_state.index)} total rows')
        # print(eia_by_state.columns)

        # remove rows with 'NA' ID
        eia_id_mask = eia_by_state['ID'].apply(lambda x: str(x).isdigit())
        logger.info(f'Removing {(~eia_id_mask).sum()} rows where Utility ID not a number')
        # eia_by_state = eia_by_state[eia_by_state['ID'].apply(lambda x: str(x).isdigit())]
        eia_by_state = eia_by_state.loc[eia_id_mask]
        eia_by_state = eia_by_state.astype({'ID': int})

        # load EIA 861 sales
        sales = EIA861(type='Annual', segment=['Commercial', 'Residential', 'Industrial'], measure='Customers').data
        logger.info(f'Loaded annual EIA861 Sales to Ultimate Consumers Com/Res/Ind Customers with {len(sales.index)} rows')

        part_mask = sales['Part'] != 'C'
        logger.info(f'Removing {(~part_mask).sum()} Part C rows')
        sales = sales.loc[part_mask]

        owner_mask = sales['Ownership'] != 'Behind the Meter'
        logger.info(f'Removing {(~owner_mask).sum()} Behind the Meter ownership rows')
        sales = sales.loc[owner_mask]

        num_mask = sales['Utility Number'] != 99999
        logger.info(f'Removing {(~num_mask).sum()} state BA-level adjustement rows')

        sales['Total Customers'] = sales[['INDUSTRIAL_Customers_ct', 'COMMERCIAL_Customers_ct', 'RESIDENTIAL_Customers_ct']].sum(axis=1)
        sales_customers = sales[['Utility Number', 'State', 'BA Code', 'Total Customers']].copy()
        sales = sales.loc[num_mask]

        logger.info(f'{len(sales.index)} Sales to Ultimate Consumers rows remain')

        # load EIA 861 short form
        short = EIA861(type='Short').data
        logger.info(f'Loaded EIA 861 Short Form data with {len(short.index)} rows')
      
        na_mask = short['Total Customers'].notna()
        logger.info(f'Dropping {(~na_mask).sum()} rows from short form data where Total Customers are NA')
        short = short.loc[na_mask]

        short_customers = short[['Utility Number', 'State', 'BA Code', 'Total Customers']].copy()

        # combine sales and short data
        total_customers = pd.concat([sales_customers, short_customers], axis=0)
        logger.info(f'Sales and Short Utility Total Customers by State and BA Combined for {len(total_customers.index)} rows')

        ba_mask = total_customers['BA Code'].notna()
        logger.info(f'Dropping {(~ba_mask).sum()} rows from combined EIA data where BA Code is NA')
        total_customers = total_customers.loc[ba_mask]

        # merge BA Code and total customers into utilty shapes
        logger.info('Merging customers into utility shapes')
        eia_by_state = eia_by_state.merge(total_customers, left_on=['ID', 'STUSPS'], right_on=['Utility Number', 'State'], how='left')

        # drop rows missing BA Code
        ba_mask = eia_by_state['BA Code'].notna()
        logger.info(
            f"""{(~ba_mask).sum()} rows have NA for BA Code - combination of Utility ID and State not found in EIA data.
            These are typically sliver shapes around state borders where the service territory data didn't align well with borders.
            {ba_mask.sum()} rows remain."""
        )
        eia_by_state = eia_by_state.loc[ba_mask]
        assert(len(eia_by_state.index) == ba_mask.sum())
        
        # calculate areas and total customers per area
        logger.info('calculating service territory area and customer density')
        current_crs = eia_by_state.crs
        # use USGS Contiguous US Albers Equal Area CRS
        eia_by_state = eia_by_state.to_crs('EPSG:5070')
        eia_by_state['area'] = eia_by_state.geometry.area
        eia_by_state['cust_per_area'] = eia_by_state['Total Customers'] / eia_by_state['area']
        # return to original geographical CRS
        eia_by_state = eia_by_state.to_crs(current_crs)

        # filter slivers
        def filter_slivers(gdf):
            """
            Removes sliver geometries from a GeoDataFrame by 'deflating' (negative buffer) the geometry by a 
            small amount, and only keeping the (un-deflated) geometry that remains.

            """
            old_elems = 0
            new_elems = 0
            new_geom = []
            gdf_co = gdf.copy()
            for geom in gdf_co.geometry:
                # print(geom)
                if isinstance(geom, MultiPolygon):
                    geom = list(geom.geoms)
                elif isinstance(geom, GeometryCollection):
                    geom = list(geom.geoms)
                else:
                    geom = [geom]
                old_elems += len(geom)
                filtered_geom = [poly for poly in geom if not poly.buffer(-0.001).is_empty]
                new_elems += len(filtered_geom)
                if filtered_geom:
                    new_geom.append(MultiPolygon(filtered_geom) if len(filtered_geom) > 1 else filtered_geom[0])
                else:
                    new_geom.append(None)

            # print(new_geom)
            logger.info(f'number of old geometry elements: {old_elems}')
            logger.info(f'number of cleaned geometry elements: {new_elems}')

            gdf_co['geometry'] = new_geom

            none_filter = gdf_co['geometry'].notna()
            logger.info(f"{(~none_filter).sum()} cleaned rows now have empty geometry and will be removed. {none_filter.sum()} rows remain")

            gdf_co = gdf_co.loc[none_filter]

            return gdf_co
        
        logger.info('filtering out sliver geometry')
        eia_by_state = filter_slivers(eia_by_state)

        # remove duplicate geometry
        def remove_duplicate_geometries(gdf, sort_column='Total Customers'):
            """
            Removes duplicate geometries from a GeoDataFrame, keeping only the row with the highest value in thee specified column.
            """
            idx_max = gdf.groupby(gdf.geometry.apply(lambda geom: geom.wkb))[sort_column].idxmax().dropna()

            gdf_cleaned = gdf.loc[idx_max]
            gdf_removed = gdf.drop(index=idx_max)

            logger.info(f'{len(gdf_removed.index)} rows found with duplicate geometries and will be dropped. {len(gdf_cleaned.index)} rows remain.')

            return gdf_cleaned

        logger.info('Filtering out duplicate geometry')
        eia_by_state = remove_duplicate_geometries(eia_by_state)

        # remove overlaps
        def remove_overlaps(gdf):
            """
            Removes overlapping service territory geometries by subtracting smaller area territories from larger ones.
            """

            modified_geometries = []

            for state in gdf['State'].unique():
                logger.debug(f'Removing overlapping geometries for {state}')
                state_gdf = gdf.loc[gdf['State'] == state].copy()
                state_gdf.sort_values(by='area', ascending=False, inplace=True)
                state_gdf.reset_index(inplace=True, drop=True)
                
                # find intersecting geometries.
                intersections = gpd.sjoin(state_gdf, state_gdf, how='left', predicate='intersects')

                for i, row in state_gdf.iterrows():
                    this_area = row['area']
                    others_ids = intersections.loc[
                        (intersections.index == i) # all intersecting shapes
                        & (intersections['ID_left'] != intersections['ID_right']) # not including self
                        & (intersections['area_right'] <= this_area) # with less area
                    ]['ID_right'].to_list()

                    if others_ids:
                        # subtract union of lesser area geometries from this geom
                        others_geom = state_gdf[state_gdf['ID'].isin(others_ids)].geometry
                        new_geometry = difference(row.geometry, unary_union(others_geom))
                    else:
                        new_geometry = row.geometry
                    
                    modified_geometries.append({**row, 'geometry': new_geometry})

            return gpd.GeoDataFrame(modified_geometries, columns=gdf.columns, crs=gdf.crs)
        
        logger.info('De-overlapping service territory geometries')
        eia_by_state = remove_overlaps(eia_by_state)

        if self.save_processed:
            # eia_by_state.to_file(processed_path)
            eia_by_state.to_parquet(processed_path)
        
        return eia_by_state
    
    def balancing_authority_territories_data(self):
        """
        Returns a geodataframe of non-overlapping Balancing Authority shapes by State, with columns of
        """
        processed_filename = 'balancing_authorites_processed.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved:
            if os.path.exists(processed_path):
                logger.info('Reloading Balancing Authority data from saved parquet')
                gdf = gpd.read_parquet(processed_path)
                return gdf
            else: 
                logger.warning(f'No processed data found for {processed_filename}. Processing from truth data')

        logger.info('Processing Balancing Authorities from truth data')

        eia_by_state = self.utility_territories_data()

        logger.info('Combining service territories by Balancing Authority')
        cols_to_keep = ['State', 'BA Code', 'area', 'Total Customers', 'geometry']
        bas_by_state = eia_by_state[cols_to_keep].dissolve(by=['State', 'BA Code'], as_index=False, aggfunc='sum')

        def collapse_collections(gdf):
            """
            This will collapse GeometryCollections to MultiPolygons or simple Polygons, removing any stray Lines and Points.
            This resolves verys low sjoins with structures points.
            """

            exploded = gdf.geometry.explode()
            polys = exploded[exploded.geom_type.isin(['Polygon', 'MultiPolygon'])]
            combined = polys.groupby(polys.index).apply(lambda x: MultiPolygon([geom for geom in x]) if len(x) > 1 else x.iloc[0])
            gdf.set_geometry(combined, inplace=True)
        
        collapse_collections(bas_by_state)

        if self.save_processed:
            bas_by_state.to_parquet(processed_path)

        return bas_by_state

    def balancing_authority_bldg_areas_data(self):
        """
        Creates estimate of total area of Commercial, Residential and Industrial building area contained in each census tract
        served by each Balancing Authority
        """
        processed_filename = 'ba_tract_areas.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved:
            if os.path.exists(processed_path):
                logger.info('Reloading Balancing Authority Building Areas from saved parquet')
                df = pd.read_parquet(processed_path)
                return df
            else:
                logger.info(f'No processed data found for {processed_filename}. Processing from truth data.')

        logger.info('Processing Balancing Authority Building Areas from truth data')

        bas_by_state = self.balancing_authority_territories_data()

        # Using US Structures dataset, get approximate fractions of total Commercial/Residential/Industrial building area
        # for each Balancing Authority by Tract

        # load structures filename mapping
        struc_state_zip_map_path = f'truth_data/{self.truth_data_version}/structures/structures_state_zip_map.json'
        struc_state_zip_map = self.read_delimited_truth_data_file_from_S3(struc_state_zip_map_path, ',')

        ba_tract_areas = pd.DataFrame()
        for state_name, zip in struc_state_zip_map.items():
            logger.info(f'Processing structure counts for {state_name}')

            match = re.search(r'\d{8}([A-Z]{2})\.zip', zip)
            if match:
                state_abbrev = match.group(1)
            else:
                logger.error('No match in structures_state_zip_map.json')

            dir_name = zip.replace('.zip','')
            file_name = f'{state_abbrev}_structures_rep_pts.parquet'
            structures = self.load_structures_parquet(dir_name, file_name)
            structures.set_crs(bas_by_state.crs, inplace=True)
            
            state = bas_by_state.loc[bas_by_state['State'] == state_abbrev].copy()

            logger.info(f'Finding structures within Balancing Authorities for {state_abbrev}')

            state_struct_bas = gpd.sjoin(structures, state, how='inner', predicate='within')

            # estimate default height for buildings as 10 ft
            state_struct_bas['height_est'] = state_struct_bas['HEIGHT'].fillna(value=3.048)
            # estimate total floor area by assuming height / 3.048m (10ft) is # of stories
            state_struct_bas['flr_area_est'] = state_struct_bas['SQFEET'] * (state_struct_bas['height_est'] / 3.048)

            # pivot dataframe to total area by occupancy class
            pivot = state_struct_bas.pivot_table('flr_area_est', index=['BA Code', 'CENSUSCODE'], columns='OCC_CLS', aggfunc='sum', fill_value=0.0)
            # sum all commercial occupancies
            pivot['All Commercial'] = pivot[['Assembly', 'Commercial', 'Education', 'Government']].sum(axis=1)
            pivot = pivot[['All Commercial', 'Residential', 'Industrial']]

            # merge into master df
            if ba_tract_areas.empty:
                ba_tract_areas = pivot
            else:
                ba_tract_areas = pd.concat([ba_tract_areas, pivot])
        
        ba_tract_areas.index = ba_tract_areas.index.set_levels(ba_tract_areas.index.levels[0].astype(str), level=0)
        
        ba_tract_areas.to_parquet(processed_path)

        return ba_tract_areas

    def balancing_authority_bldg_area_fracs_data(self):

        processed_filename = 'ba_tract_fracs.parquet'
        processed_path = os.path.join(self.processed_dir, processed_filename)
        if self.reload_from_saved:
            if os.path.exists(processed_path):
                logger.info('Reloading Balancing Authority Building Area Fractions from saved parquet')
                df = pd.read_parquet(processed_path)
                return df
            else:
                logger.info(f'No processed data found for {processed_filename}. Processing from truth data.')

        ba_tract_areas = self.balancing_authority_bldg_areas_data()

        tract_totals = ba_tract_areas.groupby(['CENSUSCODE']).sum()

        ba_tract_fracs = ba_tract_areas.divide(tract_totals, axis=1, level=-1)

        ba_tract_fracs.to_parquet(processed_path)

        return ba_tract_fracs




 





    