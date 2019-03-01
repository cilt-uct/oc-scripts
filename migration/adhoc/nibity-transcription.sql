 CREATE TABLE `oc_transcription_service_job` (
  `id` bigint(20) NOT NULL,
  `date_completed` datetime DEFAULT NULL,
  `date_created` datetime NOT NULL,
  `media_package_id` varchar(128) NOT NULL,
  `provider_id` bigint(20) NOT NULL,
  `status` varchar(128) DEFAULT NULL,
  `track_duration` bigint(20) NOT NULL,
  `track_id` varchar(128) NOT NULL,
  `job_id` varchar(128) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `oc_transcription_service_provider` (
  `id` bigint(20) NOT NULL,
  `provider` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

