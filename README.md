# bcfishobs

BC [Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is a table described as the *most current and comprehensive information source on fish presence for the province*. However, the point locations in the table are not referenced to the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater). This script downloads the observations and associated data and references the observations to the FWA as best as possible.

The script:

- downloads observation data from DataBC
- downloads a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- loads each table to postgres
- cleans the observations to retain only distinct species/location combinations that are coded as `point_type_code = 'Observation'`
- references the observation points to their position on the FWA stream network in two ways:
    + for records with a `wbody_id` that is not associated with a lake (on a stream), match to nearest stream within 300m
    + for records with a `wbody_id` associated with a lake or wetland, match to the lake/wetland that matches the `wbody_id` - or if that fails, with the nearest lake/wetland (within 1500m)

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

Download time will vary, but once all data is loaded the script creates the output table `whse_fish.fiss_fish_obsrvtn_events` (~7 min running time on a 2 core 2.8GHz laptop). 

Note that the output table stores the source id and species codes values (`fish_observation_point_id`, `species_code`) as arrays in columns `obs_ids` and `species_codes`. This enables storing multiple observations at a single location within a single record.

```
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

# Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.  

For example, we could list all species observed on the Cowichan River, downstream of Skutz Falls (about 34km from the river's mouth):

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

Note the use of [`unnest`](https://www.postgresql.org/docs/10/static/functions-array.html#ARRAY-FUNCTIONS-TABLE) to find distinct species.