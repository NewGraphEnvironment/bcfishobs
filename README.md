# bcfishobs

BC [Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is a table described as the *most current and comprehensive information source on fish presence for the province*. This repository includes a method and scripts for locating these observation locations as linear referencing events on the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater). 

The script:

- downloads `whse_fish.fiss_fish_obsrvtn_pnt_sp`, the latest observation data from DataBC
- downloads a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- downloads a lookup table `species_cd`, linking the fish species code found in the observation table to species name and scientific name
- loads each table to a PostgreSQL database
- aggregates the observations to retain only distinct sites that are coded as `point_type_code = 'Observation'` (`Summary` records should all be duplicates of `Observation` records; they can be discarded)
- references the observation points to their position on the FWA stream network using the logic outlined below

## Matching logic / steps

1. For observation points associated with a lake or wetland (according to `wbody_id`):

    - match to the FWA lake/wetland that matches the `wbody_id`
    - if no FWA lake/wetland has a matching `wbody_id`, match to the nearest lake/wetland within 1500m

2. For observation points associated with a stream:
    
    - match to the closest FWA stream within 100m that has a matching watershed code (via `fwa_streams_20k_50k_xref`)
    - for remaining unmatched records within 100m of an FWA stream, match to the closest stream regardless of a match via watershed code
    - for remaining unmatched records between 100m to 500m of an FWA stream, match to the closest FWA stream that has a matching watershed code

This logic is based on the assumptions:

- for observations noted as within a lake/wetland, we can use a relatively high distance threshold for matching to a stream because the observation may be on a bank far from the waterbody flow line
- for observations on streams, the location of an observation should generally take priority over a match via the xref lookup because many points have been manually snapped to the 20k stream lines - the lookup is best used to prioritize instances of multiple matches within 100m and allow for confidence in making matches between 100 and 500m



# Requirements

- PostgreSQL/PostGIS
- Python
- GDAL and GDAL Python bindings
- [fwakit](https://github.com/smnorris/fwakit) and a FWA database

# Installation

With `fwakit` installed, all required Python libraries should be available, no further installation should be necessary.  

Download/clone the scripts to your system and navigate to the folder: 

```
$ git clone bcfishobs
$ cd bcfishobs
```

# Run the script

Usage presumes that you have installed `fwakit`, the FWA database is loaded, and the `$FWA_DB` environment variable is correct. See the instructions for this [here](https://github.com/smnorris/fwakit#configuration).

Run the script in two steps, one to download the data, the next to do the linear referencing:  

```
$ python bcfishobs.py download
$ python bcfishobs.py process
```

Time to complete the `download` command will vary.  
The `process` command completes in ~7 min running time on a 2 core 2.8GHz laptop. 

Five tables are created by the script:

|         TABLE                        | DESCRIPTION                 |
|--------------------------------------|-----------------------------|
|`whse_fish.fiss_fish_obsrvtn_pnt_sp`            | Source fish observation points | 
|`whse_fish.wdic_waterbodies`                    | Source lookup for relating 1:50,000 waterbody identifiers | 
|`whse_fish.species_cd`| Species code -> name lookup |
|`whse_fish.fiss_fish_obsrvtn_distinct`| Output distinct observation points |
|`whse_fish.fiss_fish_obsrvtn_events`  | Output distinct observation points stored as linear locations on `whse_basemapping.fwa_stream_networks_sp` |

Note that the two output tables store the source id and species codes values (`fish_observation_point_id`, `species_code`) as arrays in columns `obs_ids` and `species_codes`. This enables storing multiple observations at a single location within a single record.

```
postgis=# \d whse_fish.fiss_fish_obsrvtn_distinct
                      Table "whse_fish.fiss_fish_obsrvtn_distinct"
            Column             |         Type          | Collation | Nullable | Default
-------------------------------+-----------------------+-----------+----------+---------
 fiss_fish_obsrvtn_distinct_id | bigint                |           | not null |
 obs_ids                       | integer[]             |           |          |
 utm_zone                      | smallint              |           |          |
 utm_easting                   | integer               |           |          |
 utm_northing                  | integer               |           |          |
 wbody_id                      | double precision      |           |          |
 waterbody_type                | character varying(20) |           |          |
 new_watershed_code            | character varying(56) |           |          |
 species_codes                 | character varying[]   |           |          |
 geom                          | geometry              |           |          |
 watershed_group_code          | text                  |           |          |
Indexes:
    "fiss_fish_obsrvtn_distinct_pkey" PRIMARY KEY, btree (fiss_fish_obsrvtn_distinct_id)
    "fiss_fish_obsrvtn_distinct_gidx" gist (geom)
    "fiss_fish_obsrvtn_distinct_wbidix" btree (wbody_id)


postgis=# \d whse_fish.fiss_fish_obsrvtn_events
                      Table "whse_fish.fiss_fish_obsrvtn_events"
            Column             |        Type         | Collation | Nullable | Default
-------------------------------+---------------------+-----------+----------+---------
 fiss_fish_obsrvtn_distinct_id | bigint              |           | not null |
 wscode_ltree                  | ltree               |           |          |
 localcode_ltree               | ltree               |           |          |
 blue_line_key                 | integer             |           |          |
 downstream_route_measure      | double precision    |           |          |
 distance_to_stream            | double precision    |           |          |
 obs_ids                       | integer[]           |           |          |
 species_codes                 | character varying[] |           |          |
Indexes:
    "fiss_fish_obsrvtn_events_pkey" PRIMARY KEY, btree (fiss_fish_obsrvtn_distinct_id)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx" gist (localcode_ltree)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx1" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx" gist (wscode_ltree)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx1" btree (wscode_ltree)

```

Also note that not all distinct observations can be matched to a stream. Currently, about 1,200 distinct points are not close enough to a stream (or waterbody) to be matched:

```
postgis=# SELECT count(*) FROM whse_fish.fiss_fish_obsrvtn_distinct;
 count
-------
 77440
(1 row)

postgis=# SELECT count(*) FROM whse_fish.fiss_fish_obsrvtn_events;
 count
-------
 76201
(1 row)
```

# Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.  

## Example 1

List all species observed on the Cowichan River (`blue_line_key = 354155148`), downstream of Skutz Falls (`downstream_route_meaure = 34180`). Note the use of [`unnest`](https://www.postgresql.org/docs/10/static/functions-array.html#ARRAY-FUNCTIONS-TABLE) to find distinct species:

```
SELECT
    array_agg(distinct_spp) AS species_codes
FROM (
    SELECT DISTINCT unnest(species_codes) AS distinct_spp
    FROM whse_fish.fiss_fish_obsrvtn_events
    WHERE
        blue_line_key = 354155148
        AND downstream_route_measure < 34180
    ORDER BY unnest(species_codes)
) AS dist_spp;

                               species_codes
----------------------------------------------------------------------------
 {ACT,AS,BNH,BT,C,CAL,CAS,CH,CM,CO,CT,DV,EB,GB,KO,L,MARFAL,RB,SA,ST,TR,TSB}
(1 row)

```


## Example 2

What is the slope of all streams where Coho have been observed?

```
SELECT * FROM
    (SELECT
      e.fiss_fish_obsrvtn_distinct_id, 
      e.blue_line_key,
      s.edge_type, 
      ec.edge_description,
      e.downstream_route_measure, 
      Round(fwa_streamslope(e.blue_line_key, e.downstream_route_measure)::numeric, 4) AS slope, 
      e.waterbody_key,
      wb.waterbody_type,
      Unnest(e.species_codes) AS species_code
    FROM whse_fish.fiss_fish_obsrvtn_events e
    INNER JOIN whse_basemapping.fwa_stream_networks_sp s 
    ON e.linear_feature_id = s.linear_feature_id
    INNER JOIN whse_basemapping.fwa_edge_type_codes ec
    ON s.edge_type = ec.edge_type
    LEFT OUTER JOIN whse_basemapping.waterbodies wb 
    ON e.waterbody_key = wb.waterbody_key
    ) as obs
WHERE species_code = 'CO'
```


## Example 3

Trace downstream of all Coho observations in the `COWN` watershed group:

