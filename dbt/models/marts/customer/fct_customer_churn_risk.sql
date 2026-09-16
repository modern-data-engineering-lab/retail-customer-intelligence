-- Grain: one row per customer_unique_id. churn_risk_tier is an explicit, documented business
-- rule — not an ML model. This repo's scope is dbt/Databricks depth, not MLOps (energy-
-- analytics-platform already covers a real deployed classifier elsewhere in the portfolio).
with orders as (
    select *
    from {{ ref('int_customer_orders') }}
),

order_gaps as (
    select
        customer_unique_id,
        order_purchase_timestamp,
        datediff(
            order_purchase_timestamp,
            lag(order_purchase_timestamp) over (
                partition by customer_unique_id
                order by order_purchase_timestamp
            )
        ) as days_since_previous_order
    from orders
),

customer_gap_agg as (
    select
        customer_unique_id,
        avg(days_since_previous_order) as avg_days_between_orders
    from order_gaps
    where days_since_previous_order is not null
    group by customer_unique_id
),

reviews as (
    select
        co.customer_unique_id,
        avg(r.review_score) as avg_review_score
    from orders as co
    left join {{ ref('stg_olist__order_reviews') }} as r
        on co.order_id = r.order_id
    group by co.customer_unique_id
),

delivery as (
    select
        customer_unique_id,
        avg(case when is_delivered_late then 1.0 else 0.0 end) as pct_orders_delivered_late
    from orders
    group by customer_unique_id
),

snapshot as (
    select max(order_purchase_timestamp) + interval 1 day as snapshot_date
    from {{ ref('int_customer_orders') }}
),

order_agg as (
    select
        customer_unique_id,
        max(order_purchase_timestamp) as last_order_date,
        count(distinct order_id)      as order_frequency
    from orders
    group by customer_unique_id
),

last_status as (
    select customer_unique_id, order_status as last_order_status
    from (
        select
            customer_unique_id,
            order_status,
            row_number() over (
                partition by customer_unique_id
                order by order_purchase_timestamp desc
            ) as rn
        from orders
    ) as ranked
    where rn = 1
),

combined as (
    select
        a.customer_unique_id,
        datediff(s.snapshot_date, a.last_order_date) as recency_days,
        a.order_frequency,
        g.avg_days_between_orders,
        a.order_frequency = 1 as is_one_time_buyer,
        rv.avg_review_score,
        d.pct_orders_delivered_late,
        ls.last_order_status
    from order_agg as a
    cross join snapshot as s
    left join customer_gap_agg as g on a.customer_unique_id = g.customer_unique_id
    left join reviews as rv on a.customer_unique_id = rv.customer_unique_id
    left join delivery as d on a.customer_unique_id = d.customer_unique_id
    left join last_status as ls on a.customer_unique_id = ls.customer_unique_id
)

select
    customer_unique_id,
    recency_days,
    order_frequency,
    avg_days_between_orders,
    is_one_time_buyer,
    avg_review_score,
    pct_orders_delivered_late,
    last_order_status,
    -- Explicit thresholds, not learned: a customer who hasn't ordered in 180+ days and only
    -- ever ordered once is the clearest churn signal available without a modeled propensity
    -- score; recency alone at 90-180 days for a one-time buyer is a softer, "Medium" signal.
    case
        when recency_days > 180 and order_frequency = 1 then 'High'
        when recency_days > 180 then 'Medium'
        when recency_days > 90 and order_frequency = 1 then 'Medium'
        else 'Low'
    end as churn_risk_tier
from combined
