# bcfishobs

BC [Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is a table described as the *most current and comprehensive information source on fish presence for the province*. This repository includes a method and scripts for locating these observation locations as linear referencing events on the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater).

The script:

- downloads `whse_fish.fiss_fish_obsrvtn_pnt_sp`, the latest observation data from DataBC
- downloads a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- downloads a lookup table `species_cd`, linking the fish species code found in the observation table to species name and scientific name
- loads each table to a PostgreSQL database
- aggregates the observations to retain only distinct sites that are coded as `point_type_code = 'Observation'` (`Summary` records should all be duplicates of `Observation` records; they can be discarded)
- references the observation points to their position on the FWA stream network using the logic outlined below

### Matching logic / steps

1. For observation points associated with a lake or wetland (according to `wbody_id`):

    - match observations to the closest FWA stream in a waterbody that matches the observation's `wbody_id`, within 1500m
    - if no FWA stream in a lake/wetland within 1500m matches the observation's `wbody_id`, match to the closest stream in any lake/wetland within 1500m

2. For observation points associated with a stream:

    - match to the closest FWA stream within 100m that has a matching watershed code (via `fwa_streams_20k_50k_xref`)
    - for remaining unmatched records within 100m of an FWA stream, match to the closest stream regardless of a match via watershed code
    - for remaining unmatched records between 100m to 500m of an FWA stream, match to the closest FWA stream that has a matching watershed code

This logic is based on the assumptions:

- for observations noted as within a lake/wetland, we can use a relatively high distance threshold for matching to a stream because
    -  an observation may be on a bank far from a waterbody flow line
    -  as long as an observation is associated with the correct waterbody, it is not important to exactly locate it on the stream network within the waterbody
- for observations on streams, the location of an observation should generally take priority over a match via the xref lookup because many points have been manually snapped to the 20k stream lines - the lookup is best used to prioritize instances of multiple matches within 100m and allow for confidence in making matches between 100 and 500m



## Requirements

- Python (tested with v3.6)
- PostgreSQL/PostGIS (tested with v10.4/2.4.4)
- GDAL and GDAL Python bindings
- [fwakit](https://github.com/smnorris/fwakit) and a FWA database
- [bcdata](https://github.com/smnorris/bcdata)

## Installation

With `fwakit` and `bcdata` installed, all required Python libraries should be available, no further installation should be necessary.

Download/clone the scripts to your system and navigate to the folder:

```
$ git clone https://github.com/smnorris/bcfishobs.git
$ cd bcfishobs
```

## Run the script

Usage presumes that you have installed `fwakit`, the FWA database is loaded, and the `$FWA_DB` environment variable is correct. See the instructions for this [here](https://github.com/smnorris/fwakit#configuration).

Run the script in two steps, one to download the data, the next to do the linear referencing:

```
$ python bcfishobs.py download
$ python bcfishobs.py process
```

Time to complete the `download` command will vary.
The `process` command completes in ~7 min running time on a 2 core 2.8GHz laptop.

## Output data

Three new tables are created by the script (in addition to the downloaded data):

#### `whse_fish.fiss_fish_obsrvtn_distinct`

Distinct locations of fish observations. Some points are duplicated as equivalent locations may have different values for `new_watershed_code`.

```
            Column             |         Type
-------------------------------+-----------------------
 fish_obsrvtn_distinct_id      | bigint
 obs_ids                       | integer[]
 utm_zone                      | smallint
 utm_easting                   | integer
 utm_northing                  | integer
 wbody_id                      | double precision
 waterbody_type                | character varying(20)
 new_watershed_code            | character varying(56)
 species_codes                 | text[]
 geom                          | geometry
 watershed_group_code          | text

Indexes:
    "fish_obsrvtn_distinct_pkey" PRIMARY KEY, btree (fish_obsrvtn_distinct_id)
    "fiss_fish_obsrvtn_distinct_gidx" gist (geom)
    "fiss_fish_obsrvtn_distinct_wbidix" btree (wbody_id)
```


#### `whse_fish.fiss_fish_obsrvtn_events`
Distinct observation points stored as linear events on `whse_basemapping.fwa_stream_networks_sp`

```
          Column          |         Type
--------------------------+----------------------
 fish_obsrvtn_distinct_id | integer
 linear_feature_id        | integer
 wscode_ltree             | ltree
 localcode_ltree          | ltree
 blue_line_key            | integer
 waterbody_key            | integer
 downstream_route_measure | double precision
 watershed_group_code     | character varying(4)
 obs_ids                  | integer[]
 species_codes            | text[]
 maximal_species          | text[]
 distance_to_stream       | double precision
 match_type               | text
Indexes:
    "fiss_fish_obsrvtn_events_blue_line_key_idx" btree (blue_line_key)
    "fiss_fish_obsrvtn_events_linear_feature_id_idx" btree (linear_feature_id)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx" gist (localcode_ltree)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx1" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_waterbody_key_idx" btree (waterbody_key)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx" gist (wscode_ltree)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx1" btree (wscode_ltree)
```


#### `whse_fish.fiss_fish_obsrvtn_unmatched`
Distinct observation points that were not referenced to the stream network (for QA)

```
            Column             |        Type
-------------------------------+---------------------
 fish_obsrvtn_distinct_id      | bigint
 obs_ids                       | integer[]
 species_codes                 | text[]
 distance_to_stream            | double precision
 geom                          | geometry
Indexes:
    "fish_obsrvtn_unmatched_pkey" PRIMARY KEY, btree (fish_obsrvtn_distinct_id)
```

## QA results

On completion, the script outputs to stdout the results of the query `sql/qa_match_report.sql`, reporting on the number and type of matches made.

Current result (May 07, 2019):

```
match_type                                                       | n_distinct_events| n_observations
--------------------------------------------------------------------------------------------------
A. matched - stream; within 100m; lookup                         | 52485          | 160344
B. matched - stream; within 100m; closest stream                 | 6410           | 18314
C. matched - stream; 100-500m; lookup                            | 4341           | 29190
D. matched - waterbody; construction line within 1500m; lookup   | 11537          | 111444
E. matched - waterbody; construction line within 1500m; closest  | 1283           | 15467
TOTAL MATCHED                                                    | 76056          | 334759
F. unmatched - less than 1500m to stream                         | 1613           | 5051
G. unmatched - more than 1500m to stream                         | 102            | 713
TOTAL UNMATCHED                                                  | 1715           | 5764
GRAND TOTAL                                                      | 77771          | 340523
```

This result can be compared with the output of `sql/qa_total_records`, the number of total observations should be the same in each query.

## Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.

### Example 1

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


### Example 2

What is the slope (percent) of the stream at the locations of all distinct Coho observations in `COWN` watershed group (on single line streams)?

```
SELECT
  e.fish_obsrvtn_distinct_id,
  Round((fwa_streamslope(e.blue_line_key, e.downstream_route_measure) * 100)::numeric, 2) AS slope
FROM whse_fish.fiss_fish_obsrvtn_events e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
INNER JOIN whse_basemapping.fwa_edge_type_codes ec
ON s.edge_type = ec.edge_type
WHERE e.species_codes @> ARRAY['CO']
AND e.watershed_group_code = 'COWN'
AND ec.edge_type = 1000;

fish_obsrvtn_distinct_id | slope
--------------------------+-------
                    30728 |  0.00
                    30128 | 41.75
                    31129 |  2.31
                    29762 |  0.00
                    31350 | 20.49
                    32586 |  3.64
                    32667 |  0.00
                    29804 |  0.00
                    29007 |  0.40
...
```


### Example 3

Trace downstream from fish observations to the ocean, generating implied habitat distribution for anadramous species:

See [`bcfishobs_traces`](https://github.com/smnorris/bcfishobs_traces)

