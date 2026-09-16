-- The three customer marts should describe exactly the same customer population — a drift
-- here means one mart's join logic silently dropped or duplicated customers relative to the
-- others. (Score-range validity is already covered by accepted_values tests in
-- _customer__models.yml, so this test covers cross-mart consistency instead, not range checks.)
with rfm_customers as (
    select customer_unique_id from {{ ref('fct_customer_rfm') }}
),

churn_customers as (
    select customer_unique_id from {{ ref('fct_customer_churn_risk') }}
),

ltv_customers as (
    select customer_unique_id from {{ ref('fct_customer_ltv') }}
)

select customer_unique_id from rfm_customers
except
select customer_unique_id from churn_customers

union all

select customer_unique_id from rfm_customers
except
select customer_unique_id from ltv_customers
