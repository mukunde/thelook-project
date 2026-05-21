
    
    

select
    order_id as unique_field,
    count(*) as n_records

from ANALYTICS_DEV.dbt_gm_staging.stg_shopify__orders
where order_id is not null
group by order_id
having count(*) > 1


