
    
    

select
    product_id as unique_field,
    count(*) as n_records

from ANALYTICS_DEV.dbt_gm_staging.stg_akeneo__products
where product_id is not null
group by product_id
having count(*) > 1


