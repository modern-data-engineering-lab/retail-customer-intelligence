-- Grain: one row per customer_unique_id — their most recently known location, by the
-- purchase timestamp of their most recent order. Feeds snapshots/customer_location_snapshot.sql.
with ranked as (
    select
        customer_unique_id,
        customer_city,
        customer_state,
        customer_zip_code_prefix,
        row_number() over (
            partition by customer_unique_id
            order by order_purchase_timestamp desc
        ) as recency_rank
    from {{ ref('int_customer_orders') }}
)

select
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix
from ranked
where recency_rank = 1
