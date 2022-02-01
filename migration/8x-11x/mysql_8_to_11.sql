-- From 8 > 9
select 'From 8 > 9' as 'ON';
-- Drop unused tables
drop table if exists oc_job_oc_service_registration;
drop table if exists oc_job_context;

-- From 10_to_11/mysql5.sql
-- Increase mime_type field size
-- ALTER TABLE oc_assets_asset MODIFY COLUMN mime_type VARCHAR (255);
-- this change has already been applied.

-- Add modified and deletion date fields to series.
--
-- The deletion date is straight forward, as all existing records can correctly use 'null' as value.
-- Modification date is more tricky. We don't want to make the field nullable, so we have to find a
-- somewhat useful value. But we also don't want to set all values to the unix epoch as code
-- could reasonably assume that almost all modification dates of real world series are unique. So
-- we instead derive the modification dates from the series' events. Unix epoch only for series
-- without events.
--
-- We use 1970-01-02 instead of 1970-01-01 to work around possible timezone problems. The exact value 
-- doesn't matter anyway.

select 'OC_SERIES : Dates (del + mod)' as 'ON';
ALTER TABLE oc_series ADD deletion_date TIMESTAMP NULL;
ALTER TABLE oc_series ADD modified_date TIMESTAMP NULL;
UPDATE oc_series
    SET modified_date = (
        SELECT MAX(oc_search.modification_date)
            FROM oc_search
            WHERE oc_search.series_id = oc_series.id
    );

select 'OC_SERIES : Modified Timestamp' as 'ON';
UPDATE oc_series
    SET modified_date = TIMESTAMP '1970-01-02 00:00:01'
    WHERE modified_date IS NULL;
ALTER TABLE oc_series MODIFY modified_date TIMESTAMP NOT NULL DEFAULT '1970-01-02 00:00:01';

select 'Done' as 'ON';
