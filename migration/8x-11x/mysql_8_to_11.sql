-- Drop unused tables
drop table if exists oc_job_oc_service_registration;
drop table if exists oc_job_context;

-- Increase mime_type field size
--ALTER TABLE oc_assets_asset MODIFY COLUMN mime_type VARCHAR (255);
--this change has already been applied.