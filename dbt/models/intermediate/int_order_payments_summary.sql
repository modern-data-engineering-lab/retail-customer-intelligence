-- Grain: one row per order_id. Collapses the (possibly multi-row) payments-per-order grain so
-- downstream models join once per order instead of fanning out across payment methods.
select
    order_id,
    sum(payment_value) as total_payment_value,
    count(distinct payment_type) as distinct_payment_types,
    max(payment_installments) as max_installments
from {{ ref('stg_olist__order_payments') }}
group by order_id
