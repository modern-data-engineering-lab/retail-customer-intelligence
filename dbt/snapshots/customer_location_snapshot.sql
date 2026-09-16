{% snapshot customer_location_snapshot %}

{{
    config(
        target_schema=target.schema,
        unique_key="customer_unique_id",
        strategy="check",
        check_cols=["customer_city", "customer_state"],
    )
}}

-- SCD2 on a customer's known location. The Olist dump is a static one-time historical extract,
-- so this won't organically produce a valid_to transition on repeated runs against the same
-- data — verified for real by manually mutating a few bronze customer rows and re-running
-- `dbt snapshot` once; see README Troubleshooting for what that run actually showed.
select
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix
from {{ ref('int_customer_location_current') }}

{% endsnapshot %}
