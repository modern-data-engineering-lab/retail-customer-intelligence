-- Grain: one row per customer_unique_id.
--
-- estimated_ltv is a transparent, auditable extrapolation — avg_order_value projected across
-- the customer's expected remaining lifespan (avg_customer_lifespan_days / their own
-- avg_days_between_orders = expected future order count) — explicitly NOT a survival-model
-- estimate. One-time buyers have no avg_days_between_orders to project from, so their estimate
-- floors at historical_ltv (what they've actually spent) rather than extrapolating from a
-- single data point.
with customer_base as (
    select
        customer_unique_id,
        first_order_date,
        last_order_date,
        lifetime_order_count,
        lifetime_spend
    from {{ ref('dim_customers') }}
),

churn as (
    select customer_unique_id, avg_days_between_orders
    from {{ ref('fct_customer_churn_risk') }}
),

cohort_lifespan as (
    select avg(datediff(last_order_date, first_order_date)) as avg_customer_lifespan_days
    from customer_base
    where lifetime_order_count > 1
),

combined as (
    select
        cb.customer_unique_id,
        cb.lifetime_spend                                              as historical_ltv,
        cb.lifetime_spend / nullif(cb.lifetime_order_count, 0)         as avg_order_value,
        c.avg_days_between_orders,
        cl.avg_customer_lifespan_days
    from customer_base as cb
    left join churn as c
        on cb.customer_unique_id = c.customer_unique_id
    cross join cohort_lifespan as cl
)

select
    customer_unique_id,
    historical_ltv,
    coalesce(
        avg_order_value * (avg_customer_lifespan_days / nullif(avg_days_between_orders, 0)),
        historical_ltv
    ) as estimated_ltv
from combined
