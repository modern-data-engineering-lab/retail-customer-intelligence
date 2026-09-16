-- Grain: one row per order item. Incremental via a real Delta merge — dbt-databricks's native
-- mechanism, not a hand-rolled upsert. The Olist Kaggle dump is a one-time static extract, so a
-- fresh bronze load won't organically produce a second incremental batch; this model exists to
-- demonstrate the real merge behavior (verified manually — see README Troubleshooting), which
-- is what would incrementally pick up new order items on every bronze refresh in a live system.
{{
    config(
        materialized="incremental",
        incremental_strategy="merge",
        unique_key="order_item_key",
    )
}}

select
    {{ dbt_utils.generate_surrogate_key(["oi.order_id", "oi.order_item_id"]) }} as order_item_key,
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    oi.item_total,
    p.product_category_name,
    t.product_category_name_english,
    s.seller_state,
    o.order_purchase_timestamp
from {{ ref('stg_olist__order_items') }} as oi
inner join {{ ref('stg_olist__orders') }} as o
    on oi.order_id = o.order_id
left join {{ ref('stg_olist__products') }} as p
    on oi.product_id = p.product_id
left join {{ ref('stg_olist__product_category_translation') }} as t
    on p.product_category_name = t.product_category_name
left join {{ ref('stg_olist__sellers') }} as s
    on oi.seller_id = s.seller_id

{% if is_incremental() %}
where o.order_purchase_timestamp > (select max(order_purchase_timestamp) from {{ this }})
{% endif %}
