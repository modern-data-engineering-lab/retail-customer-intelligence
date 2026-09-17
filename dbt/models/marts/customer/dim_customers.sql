-- Grain: one row per customer_unique_id — the real customer identity, not per customer_id.
with order_agg as (
    select
        customer_unique_id,
        min(order_purchase_timestamp) as first_order_date,
        max(order_purchase_timestamp) as last_order_date,
        count(distinct order_id) as lifetime_order_count
    from {{ ref('int_customer_orders') }}
    group by customer_unique_id
),

payment_agg as (
    select
        co.customer_unique_id,
        sum(p.total_payment_value) as lifetime_spend
    from {{ ref('int_customer_orders') }} as co
    left join {{ ref('int_order_payments_summary') }} as p
        on co.order_id = p.order_id
    group by co.customer_unique_id
)

select
    a.customer_unique_id,
    a.first_order_date,
    a.last_order_date,
    a.lifetime_order_count,
    loc.customer_city,
    loc.customer_state,
    loc.customer_zip_code_prefix,
    coalesce(p.lifetime_spend, 0) as lifetime_spend
from order_agg as a
left join payment_agg as p
    on a.customer_unique_id = p.customer_unique_id
left join {{ ref('int_customer_location_current') }} as loc
    on a.customer_unique_id = loc.customer_unique_id
