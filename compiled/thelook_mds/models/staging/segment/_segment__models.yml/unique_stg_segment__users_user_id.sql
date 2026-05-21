
    
    

select
    user_id as unique_field,
    count(*) as n_records

from ANALYTICS_DEV.dbt_gm_staging.stg_segment__users
where user_id is not null
group by user_id
having count(*) > 1


