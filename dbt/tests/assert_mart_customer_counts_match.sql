-- fct_customer_churn_risk and fct_customer_ltv cover every customer in dim_customers.
-- fct_customer_rfm intentionally does NOT: a customer whose orders were all canceled/
-- unavailable has no real purchase behavior to score (see fct_customer_rfm.sql), so it's
-- checked as a strict subset of the other two, not an exact match.
--
-- The original version of this test only checked rfm -> churn/ltv (one direction) and PASSED
-- even though fct_customer_rfm had 1,106 fewer customers than the other two marts — it never
-- checked whether churn_risk and ltv agreed with EACH OTHER, which is the actual invariant
-- that should always hold exactly. Verified against the real warehouse: churn_risk and ltv both
-- had 96,096 customers, rfm had 94,990 — the gap was real and exactly the canceled/unavailable-
-- only customers, not a join bug. Caught here, not assumed away.
with rfm_customers as (
    select customer_unique_id from {{ ref('fct_customer_rfm') }}
),

churn_customers as (
    select customer_unique_id from {{ ref('fct_customer_churn_risk') }}
),

ltv_customers as (
    select customer_unique_id from {{ ref('fct_customer_ltv') }}
),

churn_ltv_mismatch as (
    select customer_unique_id from churn_customers
    except
    select customer_unique_id from ltv_customers

    union all

    select customer_unique_id from ltv_customers
    except
    select customer_unique_id from churn_customers
),

rfm_not_in_churn as (
    select customer_unique_id from rfm_customers
    except
    select customer_unique_id from churn_customers
)

select customer_unique_id from churn_ltv_mismatch
union all
select customer_unique_id from rfm_not_in_churn
