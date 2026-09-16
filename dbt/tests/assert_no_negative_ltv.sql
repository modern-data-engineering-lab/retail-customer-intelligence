select *
from {{ ref('fct_customer_ltv') }}
where estimated_ltv < 0
   or historical_ltv < 0
