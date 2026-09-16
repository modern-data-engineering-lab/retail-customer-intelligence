-- Fails (returns rows) for any order where payments and order-item totals don't reconcile
-- within a cent. Expect a real, non-zero mismatch rate on first run against real Olist data
-- (freight/discount timing) — see README for the actual rate found and whether it was fixed
-- or documented as an accepted tolerance.
with item_totals as (
    select
        order_id,
        sum(item_total) as items_total
    from {{ ref('stg_olist__order_items') }}
    group by order_id
)

select
    i.order_id,
    i.items_total,
    p.total_payment_value,
    abs(i.items_total - p.total_payment_value) as diff
from item_totals as i
inner join {{ ref('int_order_payments_summary') }} as p
    on i.order_id = p.order_id
where abs(i.items_total - p.total_payment_value) > 0.01
