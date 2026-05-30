{% test expression_is_true(model, expression) %}

select *
from {{ model }}
where ({{ expression }}) is not true

{% endtest %}
