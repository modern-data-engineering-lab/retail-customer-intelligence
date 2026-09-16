-- The one Olist "table" small/static enough (~71 rows) to be a genuine dbt seed rather than a
-- bronze table loaded by the ingestion job.
select
    product_category_name,
    product_category_name_english
from {{ ref('product_category_name_translation') }}
