-- Raw Olist review data can have more than one review row per order_id (re-review after a
-- follow-up). Deduped here to the latest review per order — this is the one staging model
-- that does real cleanup rather than a straight rename, because every downstream consumer
-- (fct_customer_churn_risk) needs one review score per order, not a fan-out.
with ranked as (
    select
        review_id,
        order_id,
        review_score,
        cast(review_creation_date as timestamp) as review_creation_date,
        cast(review_answer_timestamp as timestamp) as review_answer_timestamp,
        row_number() over (
            partition by order_id
            order by review_creation_date desc
        ) as review_rank
    from {{ source('bronze', 'order_reviews') }}
)

select
    review_id,
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp
from ranked
where review_rank = 1
