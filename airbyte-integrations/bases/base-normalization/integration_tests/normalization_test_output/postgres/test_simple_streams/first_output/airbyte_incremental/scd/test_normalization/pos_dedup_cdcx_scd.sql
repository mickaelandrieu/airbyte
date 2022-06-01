
      

  create  table "postgres".test_normalization."pos_dedup_cdcx_scd"
  as (
    
-- depends on: "postgres"._airbyte_test_normalization."pos_dedup_cdcx_scd_new_data"
with

input_data as (
    select *
    from "postgres"._airbyte_test_normalization."pos_dedup_cdcx_stg"
    -- pos_dedup_cdcx from "postgres".test_normalization._airbyte_raw_pos_dedup_cdcx
),

scd_data as (
    -- SQL model to build a Type 2 Slowly Changing Dimension (SCD) table for each record identified by their primary key
    select
      md5(cast(coalesce(cast("id" as text), '') as text)) as _airbyte_unique_key,
      "id",
      "name",
      _ab_cdc_lsn,
      _ab_cdc_updated_at,
      _ab_cdc_deleted_at,
      _ab_cdc_log_pos,
      _ab_cdc_updated_at as _airbyte_start_at,
      lag(_ab_cdc_updated_at) over (
        partition by "id"
        order by
            _ab_cdc_updated_at is null asc,
            _ab_cdc_updated_at desc,
            _ab_cdc_updated_at desc,
            _ab_cdc_log_pos desc,
            _airbyte_emitted_at desc
      ) as _airbyte_end_at,
      case when row_number() over (
        partition by "id"
        order by
            _ab_cdc_updated_at is null asc,
            _ab_cdc_updated_at desc,
            _ab_cdc_updated_at desc,
            _ab_cdc_log_pos desc,
            _airbyte_emitted_at desc
      ) = 1 and _ab_cdc_deleted_at is null then 1 else 0 end as _airbyte_active_row,
      _airbyte_ab_id,
      _airbyte_emitted_at,
      _airbyte_pos_dedup_cdcx_hashid
    from input_data
),
dedup_data as (
    select
        -- we need to ensure de-duplicated rows for merge/update queries
        -- additionally, we generate a unique key for the scd table
        row_number() over (
            partition by
                _airbyte_unique_key,
                _airbyte_start_at,
                _airbyte_emitted_at, cast(_ab_cdc_deleted_at as text), cast(_ab_cdc_updated_at as text), cast(_ab_cdc_log_pos as text)
            order by _airbyte_active_row desc, _airbyte_ab_id
        ) as _airbyte_row_num,
        md5(cast(coalesce(cast(_airbyte_unique_key as text), '') || '-' || coalesce(cast(_airbyte_start_at as text), '') || '-' || coalesce(cast(_airbyte_emitted_at as text), '') || '-' || coalesce(cast(_ab_cdc_deleted_at as text), '') || '-' || coalesce(cast(_ab_cdc_updated_at as text), '') || '-' || coalesce(cast(_ab_cdc_log_pos as text), '') as text)) as _airbyte_unique_key_scd,
        scd_data.*
    from scd_data
)
select
    _airbyte_unique_key,
    _airbyte_unique_key_scd,
    "id",
    "name",
    _ab_cdc_lsn,
    _ab_cdc_updated_at,
    _ab_cdc_deleted_at,
    _ab_cdc_log_pos,
    _airbyte_start_at,
    _airbyte_end_at,
    _airbyte_active_row,
    _airbyte_ab_id,
    _airbyte_emitted_at,
    now() as _airbyte_normalized_at,
    _airbyte_pos_dedup_cdcx_hashid
from dedup_data where _airbyte_row_num = 1
  );
  