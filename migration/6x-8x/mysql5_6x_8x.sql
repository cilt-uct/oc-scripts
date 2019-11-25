ALTER TABLE oc_assets_asset ADD CONSTRAINT FK_oc_assets_asset_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES oc_assets_snapshot (id) ON DELETE CASCADE;
DROP TABLE oc_scheduled_transaction;
DROP TABLE oc_scheduled_extended_event;
CREATE TABLE oc_scheduled_extended_event (
  mediapackage_id VARCHAR(128) NOT NULL,
  organization VARCHAR(128) NOT NULL,
  capture_agent_id VARCHAR(128) NOT NULL,
  start_date DATETIME NOT NULL,
  end_date DATETIME NOT NULL,
  source VARCHAR(255),
  recording_state VARCHAR(255),
  recording_last_heard BIGINT,
  presenters TEXT(65535),
  last_modified_date DATETIME,
  checksum VARCHAR(64),
  capture_agent_properties MEDIUMTEXT,
  workflow_properties MEDIUMTEXT,
  PRIMARY KEY (mediapackage_id, organization),
  CONSTRAINT FK_oc_scheduled_extended_event_organization FOREIGN KEY (organization) REFERENCES oc_organization (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
CREATE INDEX IX_oc_scheduled_extended_event_organization ON oc_scheduled_extended_event (organization);
CREATE INDEX IX_oc_scheduled_extended_event_capture_agent_id ON oc_scheduled_extended_event (capture_agent_id);
CREATE INDEX IX_oc_scheduled_extended_event_dates ON oc_scheduled_extended_event (start_date, end_date);
DELETE FROM oc_assets_properties WHERE namespace = 'org.opencastproject.scheduler.trx';

ALTER TABLE oc_job DROP COLUMN blocking_job;
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
CREATE INDEX IX_oc_assets_asset_snapshot_id ON oc_assets_asset (snapshot_id);

-- MH-13490 Add event index for efficiency
CREATE INDEX IX_oc_event_comment_event ON oc_event_comment (event, organization);

-- MH-13489 Add index on series_id for efficiency
CREATE INDEX IX_oc_assets_snapshot_series ON oc_assets_snapshot (series_id, version);

-- Due to MH-13514 Add descriptive node names to hosts
ALTER TABLE oc_host_registration ADD COLUMN node_name VARCHAR(255) AFTER host;

ALTER TABLE oc_aws_asset_mapping CHANGE COLUMN media_package_element mediapackage_element varchar(128);
ALTER TABLE oc_aws_asset_mapping CHANGE COLUMN media_package mediapackage varchar(128);


-- Create provider table for transcription service
CREATE TABLE oc_transcription_service_provider (
  id BIGINT(20) NOT NULL,
  provider VARCHAR(255) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Create table for transcription service job with link to transcription provider table
CREATE TABLE oc_transcription_service_job (
  id BIGINT(20) NOT NULL,
  mediapackage_id VARCHAR(128) NOT NULL,
  track_id VARCHAR(128) NOT NULL,
  job_id  VARCHAR(128) NOT NULL,
  date_created DATETIME NOT NULL,
  date_expected DATETIME DEFAULT NULL,
  date_completed DATETIME DEFAULT NULL,
  status VARCHAR(128) DEFAULT NULL,
  track_duration BIGINT NOT NULL,
  provider_id BIGINT(20) NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT FK_oc_transcription_service_job_provider_id FOREIGN KEY (provider_id) REFERENCES oc_transcription_service_provider (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Migrate IBM Watson transcription data to new shared table

INSERT INTO oc_transcription_service_provider (id, provider) VALUES (1, "IBM Watson");

INSERT INTO oc_transcription_service_job (id, mediapackage_id, track_id, job_id, date_created, date_completed, status, track_duration, provider_id)
 (SELECT id, media_package_id, track_id, job_id, date_created, date_completed, status, track_duration, 1 FROM oc_ibm_watson_transcript_job);

DROP TABLE oc_ibm_watson_transcript_job;

---Clear out job data and hosts
SET FOREIGN_KEY_CHECKS=0;
select 'Truncating job and host data' as 'ON';
TRUNCATE oc_job;
TRUNCATE oc_job_argument;
TRUNCATE oc_job_mh_service_registration;
TRUNCATE oc_host_registration;
TRUNCATE oc_service_registration;
SET FOREIGN_KEY_CHECKS=1;
---END Clear out job data and hosts
