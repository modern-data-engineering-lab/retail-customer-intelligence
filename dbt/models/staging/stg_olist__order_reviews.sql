-- Raw Olist review data can have more than one review row per order_id (re-review after a
-- follow-up). Deduped here to the latest review per order — this is the one staging model
-- that does real cleanup rather than a straight rename, because every downstream consumer
-- (fct_customer_churn_risk) needs one review score per order, not a fan-out.
--
-- A small number of raw rows (~16 of 99,224, ~0.02%) are genuinely malformed: multi-paragraph
-- review comments with internal escaped quotes and blank lines that even Spark's multiLine CSV
-- reader can't fully disambiguate, shifting review_score into free text or leaving order_id
-- null for that row. Verified directly against the real bronze table (see terraform/README —
-- same "check reality, don't assume the parser got it right" discipline as the other repos in
-- this portfolio) rather than assumed away. Quarantined here via try_cast + a not-null filter
-- rather than chasing a perfect CSV-parser config for a handful of pathological free-text rows.
with ranked as (
    select
        review_id,
        order_id,
        try_cast(review_score as int) as review_score,
        cast(review_creation_date as timestamp) as review_creation_date,
        cast(review_answer_timestamp as timestamp) as review_answer_timestamp,
        row_number() over (
            partition by order_id
            order by review_creation_date desc
        ) as review_rank
    from {{ source('bronze', 'order_reviews') }}
    where order_id is not null
)

select
    review_id,
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp
from ranked
where review_rank = 1
  and review_score between 1 and 5
