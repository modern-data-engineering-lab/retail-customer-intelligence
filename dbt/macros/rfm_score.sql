{#
    Buckets a column into an ntile(5) score. higher_is_better controls which end of the raw
    values gets score 5: true for frequency/monetary (bigger is better), false for recency
    (fewer days since the last order is better) — reversing the ntile order rather than
    subtracting from 6, so the same macro covers both directions.
#}
{% macro rfm_score(column_name, higher_is_better=true) %}
    ntile(5) over (
        order by {{ column_name }} {{ "asc" if higher_is_better else "desc" }}
    )
{% endmacro %}
