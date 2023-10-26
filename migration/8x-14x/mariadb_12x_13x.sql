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
