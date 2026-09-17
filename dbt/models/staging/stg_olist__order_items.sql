-- Grain: one row per item within an order (order_id + order_item_id).
select
    order_id,
    order_item_id,
    product_id,
    seller_id,
    cast(shipping_limit_date as timestamp) as shipping_limit_date,
    cast(price as decimal(10, 2)) as price,
    cast(freight_value as decimal(10, 2)) as freight_value,
    cast(price as decimal(10, 2)) + cast(freight_value as decimal(10, 2)) as item_total
from {{ source('bronze', 'order_items') }}
