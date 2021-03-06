ALTER TABLE oc_assets_asset ADD CONSTRAINT FK_oc_assets_asset_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES oc_assets_snapshot (id) ON DELETE CASCADE;

-- DROP TABLE oc_scheduled_transaction; (Already dropped)

ALTER TABLE
  oc_scheduled_extended_event DROP review_status,
  DROP review_date,
  DROP optout,
  DROP last_modified_origin;

DELETE FROM oc_scheduled_extended_event WHERE end_date < NOW();
DELETE FROM oc_assets_properties WHERE namespace = 'org.opencastproject.scheduler.trx';

-- ALTER TABLE oc_job DROP COLUMN blocking_job; (Already dropped)
DROP TABLE oc_blocking_job;

-- Due to MH-13397 Remove unfinished feature "Participation Management"
ALTER TABLE oc_series DROP COLUMN opt_out;

-- Due to MH-13431 Remove unfinished feature "Bulk Messaging"
DROP TABLE oc_email_configuration;
DROP TABLE oc_message_signature;
DROP TABLE oc_message_template;

-- Due to MH-13446 Remove unfinished feature "ACL transitions"
DROP TABLE oc_acl_episode_transition;
DROP TABLE oc_acl_series_transition;

-- Clean up orphaned asset manager properties
delete p from oc_assets_properties p where not exists (
  select * from oc_assets_snapshot s
    where p.mediapackage_id = s.mediapackage_id
);

-- MH-12047 Add series index for efficiency
CREATE INDEX IX_oc_search_series ON oc_search (series_id);

-- MH-13380 Add snapshot_id index for efficiency
-- CREATE INDEX IX_oc_assets_asset_snapshot_id ON oc_assets_asset (snapshot_id); (Already exists)

-- MH-13490 Add event index for efficiency
-- CREATE INDEX IX_oc_event_comment_event ON oc_event_comment (event, organization); (Already exists)

-- MH-13489 Add index on series_id for efficiency
-- CREATE INDEX IX_oc_assets_snapshot_series ON oc_assets_snapshot (series_id, version); (Already exists)

-- Due to MH-13514 Add descriptive node names to hosts
ALTER TABLE oc_host_registration ADD COLUMN node_name VARCHAR(255) AFTER host;

ALTER TABLE oc_aws_asset_mapping CHANGE COLUMN media_package_element mediapackage_element varchar(128);
ALTER TABLE oc_aws_asset_mapping CHANGE COLUMN media_package mediapackage varchar(128);

-- Migrate IBM Watson transcription data to new shared table

INSERT INTO oc_transcription_service_provider (id, provider) VALUES (1, "IBM Watson");

ALTER TABLE oc_transcription_service_job CHANGE COLUMN media_package_id mediapackage_id varchar(128);

INSERT INTO oc_transcription_service_job (id, mediapackage_id, track_id, job_id, date_created, date_completed, status, track_duration, provider_id)
 (SELECT id, media_package_id, track_id, job_id, date_created, date_completed, status, track_duration, 1 FROM oc_ibm_watson_transcript_job);

DROP TABLE oc_ibm_watson_transcript_job;

-- Clear out job data and hosts
SET FOREIGN_KEY_CHECKS=0;
select 'Truncating job and host data' as 'ON';
TRUNCATE oc_job;
TRUNCATE oc_job_argument;
TRUNCATE oc_job_oc_service_registration;
TRUNCATE oc_host_registration;
TRUNCATE oc_service_registration;
SET FOREIGN_KEY_CHECKS=1;
-- END Clear out job data and hosts

-- Remove published search records for unpublished events as they don't need to get re-indexed
delete from oc_search where deletion_date is not null;

-- Drop bundle data to avoid production server bundle info showing up on dev servers
truncate table oc_bundleinfo;

-- Fix some paths in oc_search
UPDATE oc_search
   SET mediapackage_xml =
   REPLACE( mediapackage_xml,
            '/static/engage-player/',
            '/static/mh_default_org/engage-player/')
   WHERE INSTR( mediapackage_xml,
                '/static/engage-player/') > 0;
