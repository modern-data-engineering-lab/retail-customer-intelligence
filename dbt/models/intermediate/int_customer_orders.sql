-- Grain: one row per order_id, joined through to the real customer identity
-- (customer_unique_id, not customer_id — see stg_olist__customers). This is the join every
-- mart in models/marts/customer/ builds on.
select
    o.order_id,
    c.customer_unique_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.is_delivered_late,
    c.customer_city,
    c.customer_state,
    c.customer_zip_code_prefix
from {{ ref('stg_olist__orders') }} as o
inner join {{ ref('stg_olist__customers') }} as c
    on o.customer_id = c.customer_id
