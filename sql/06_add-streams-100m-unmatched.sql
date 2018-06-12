-- For records that we haven't yet inserted, insert those that are 100m
-- or less from a stream based just on minimum distance to stream
WITH unmatched AS
(   SELECT e1.*
    FROM whse_fish.fiss_fish_obsrvtn_events_prelim1 e1
    LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events_prelim2 e2
    ON e1.fiss_fish_obsrvtn_distinct_id = e2.fiss_fish_obsrvtn_distinct_id
    INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
    ON e1.fiss_fish_obsrvtn_distinct_id = o.fiss_fish_obsrvtn_distinct_id
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e1.distance_to_stream <= 100
    AND e2.fiss_fish_obsrvtn_distinct_id IS NULL
    ORDER BY e1.fiss_fish_obsrvtn_distinct_id , e1.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (fiss_fish_obsrvtn_distinct_id)
    fiss_fish_obsrvtn_distinct_id,
    distance_to_stream
  FROM unmatched
  ORDER BY fiss_fish_obsrvtn_distinct_id, distance_to_stream
)

INSERT INTO whse_fish.fiss_fish_obsrvtn_events_prelim2
SELECT DISTINCT ON (e.fiss_fish_obsrvtn_distinct_id)
  e.fiss_fish_obsrvtn_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'matched - stream, within 100m, closest stream'
FROM whse_fish.fiss_fish_obsrvtn_events_prelim1 e
INNER JOIN closest_unmatched
ON e.fiss_fish_obsrvtn_distinct_id = closest_unmatched.fiss_fish_obsrvtn_distinct_id
AND e.distance_to_stream = closest_unmatched.distance_to_stream
