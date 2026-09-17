-- Grain: one row per customer_unique_id who has at least one non-canceled/unavailable order —
-- NOT every customer in dim_customers. A customer whose orders were all canceled/unavailable
-- has no real purchase behavior to score, so they're intentionally absent here rather than
-- given a meaningless R/F/M (verified against the real warehouse: 1,106 of 96,096 customers,
-- ~1.2%, fall into this group). fct_customer_churn_risk and fct_customer_ltv still cover them —
-- see tests/assert_mart_customer_counts_match.sql for how this asymmetry is actually tested.
--
-- snapshot_date is computed from the data itself (max order date + 1 day), not from today's
-- date — this is a static historical dataset, "today" would make recency meaningless.
-- Monetary uses total_payment_value (what the customer actually paid, incl. freight/discount
-- timing) rather than item price alone — see README design decisions for why.
with orders as (
    select *
    from {{ ref('int_customer_orders') }}
    where order_status not in ('canceled', 'unavailable')
),

snapshot as (
    select max(order_purchase_timestamp) + interval 1 day as snapshot_date
    from {{ ref('int_customer_orders') }}
),

customer_orders_with_payment as (
    select
        o.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        p.total_payment_value
    from orders as o
    left join {{ ref('int_order_payments_summary') }} as p
        on o.order_id = p.order_id
),

customer_agg as (
    select
        customer_unique_id,
        max(order_purchase_timestamp) as last_order_date,
        count(distinct order_id) as frequency,
        sum(total_payment_value) as monetary
    from customer_orders_with_payment
    group by customer_unique_id
),

with_recency as (
    select
        c.customer_unique_id,
        c.last_order_date,
        c.frequency,
        c.monetary,
        datediff(s.snapshot_date, c.last_order_date) as recency_days
    from customer_agg as c
    cross join snapshot as s
),

scored as (
    select
        *,
        {{ rfm_score('recency_days', higher_is_better=false) }} as r_score,
        {{ rfm_score('frequency', higher_is_better=true) }} as f_score,
        {{ rfm_score('monetary', higher_is_better=true) }} as m_score
    from with_recency
)

select
    customer_unique_id,
    last_order_date,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    case
        when r_score >= 4 and f_score >= 4 and m_score >= 4 then 'Champions'
        when f_score >= 4 and m_score >= 3 then 'Loyal'
        when r_score >= 4 and f_score <= 2 then 'New'
        when r_score <= 2 and f_score >= 3 then 'At Risk'
        when r_score <= 2 and f_score <= 2 then 'Hibernating'
        else 'Needs Attention'
    end as rfm_segment
from scored
