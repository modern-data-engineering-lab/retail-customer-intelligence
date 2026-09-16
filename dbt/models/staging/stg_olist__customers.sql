-- customer_id is per-order, not per-person — customer_unique_id is the real identity. Every
-- downstream model joins on customer_unique_id, never customer_id. See README design decisions.
select
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
from {{ source('bronze', 'customers') }}
