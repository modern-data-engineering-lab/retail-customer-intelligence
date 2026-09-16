-- Raw geolocation has many duplicate lat/lng rows per zip prefix (multiple street-level pings
-- collapsed to a 5-digit prefix). Deduped to one representative row per prefix using the
-- average of all raw points, since no single raw row is more "correct" than another.
select
    geolocation_zip_code_prefix,
    avg(geolocation_lat) as geolocation_lat,
    avg(geolocation_lng) as geolocation_lng,
    -- city/state are inconsistent across duplicate rows for the same prefix (free-text,
    -- differing capitalization/spelling); take any one non-null value rather than avg-ing text.
    first(geolocation_city, true)  as geolocation_city,
    first(geolocation_state, true) as geolocation_state
from {{ source('bronze', 'geolocation') }}
group by geolocation_zip_code_prefix
