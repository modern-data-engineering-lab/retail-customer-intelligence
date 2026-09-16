-- Grain: one row per payment method/installment sequence per order — an order can legitimately
-- have multiple rows (e.g. a split voucher + credit card payment).
select
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    cast(payment_value as decimal(10, 2)) as payment_value
from {{ source('bronze', 'order_payments') }}
