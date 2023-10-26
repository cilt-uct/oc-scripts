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

-- From 12 > 13
select 'From 12 > 13' as 'ON';

CREATE INDEX IX_oc_aws_asset_mapping_object_key ON oc_aws_asset_mapping (object_key);
CREATE INDEX IX_oc_job_argument_id ON oc_job_argument (id);

ALTER TABLE oc_workflow
  MODIFY COLUMN `description` LONGTEXT DEFAULT NULL;

ALTER TABLE oc_workflow_operation
  MODIFY COLUMN `description` LONGTEXT DEFAULT NULL,
  MODIFY COLUMN `if_condition` LONGTEXT DEFAULT NULL;

ALTER TABLE oc_workflow_configuration
  DROP FOREIGN KEY FK_oc_workflow_configuration_workflow_id,
  ADD FOREIGN KEY IX_oc_workflow_configuration_workflow_id (`workflow_id`) REFERENCES `oc_workflow` (`id`);

ALTER TABLE oc_workflow_operation
  DROP FOREIGN KEY FK_oc_workflow_operation_workflow_id,
  ADD FOREIGN KEY IX_oc_workflow_operation_workflow_id (`workflow_id`) REFERENCES `oc_workflow` (`id`);

ALTER TABLE oc_workflow_operation_configuration
  DROP FOREIGN KEY cworkflowoperationconfigurationworkflowoperationid,
  ADD FOREIGN KEY IX_oc_workflow_operation_configuration_workflow_operation_id (`workflow_operation_id`) REFERENCES `oc_workflow_operation` (`id`);

UPDATE oc_workflow_configuration
SET configuration_value = ''
WHERE configuration_value IS NULL;

UPDATE oc_workflow_operation_configuration
SET configuration_value = ''
WHERE configuration_value IS NULL;

-- From 13 > 14
select 'From 13 > 14' as 'ON';
-- Drop unused index
DROP INDEX IF EXISTS IX_oc_job_statistics ON oc_job;

-- Clean up bundle information from nodes which no longer exist.
-- This is done automatically for every node if they are shut down *if* they are shut down properly.
-- We can safely do this since the Opencast cluster should be completely shut down during the database migration.
truncate oc_bundleinfo;

select 'Done' as 'ON';