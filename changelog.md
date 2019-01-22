2016-06-28: Corne Oosthuizen
      Updated code.

2016-07-19: Corne Oosthuizen
     Change Compile time from 7 to 15.

2016-11-01: Corne Oosthuizen
     Changed from sh to bash.

2016-11-30: Corne Oosthuizen
     On build generate keytool for deployment on Admin and Presentation nodes.

2017-01-04: Corne Oosthuizen
     Added version checking script.

2017-01-16: Corne Oosthuizen
     Changed the configuration files and running script to generate 'files/build-all.cfg' and 'group_vars/all'.

2017-01-19: Corne Oosthuizen
     Moved the build of the packages from build to deploy, makes sense to deploy using
     the correct configuration without rebuilding git based source.

2017-02-16: Corne Oosthuizen
     Implemented reconfigure operation to redeploy configuration, encoding profiles and workflows to
     the selected server list. Also reduced the build list by using a sorted unique array of generated
     from the hosts file of the profile used. Version checking uses the paths configured for each
     server.

2017-03-16: Duncan Smith
     Added the action to deploy the static version of the LTI tools from the SRC folder to the approriate
     configured static folder on the admin/presentation server.
     Additional line in conf-[servername].cfg for LTI static folder.
     Files (Add): lti.sh, lti.yml
     REF: OPENCAST-1521

2017-08-19: Stephen Marquard
     Added timetable webservice code

2017-09-15: Corne Oosthuizen
     Added code to create comments to a jira issue when deployed - only for production.

2017-10-25: Corne Oosthuizen
     Modified the current Ansible playbooks (alias, deploy, reconfig, lti, reconfig) to run as roles.
     Rename all ansible scripts to ansible-*.
     Incorporate "deploy-alias.sh" and "deploy-track4k.sh" into "run.sh"

2018-03-01: Corne Oosthuizen
     Added trimpointdetector update ansible script and into run.sh

2018-03-27: Corne Oosthuizen
     Added jira comment logging for trim point detection and ocr deployments

2018-08-07: Corne Oosthuizen
     Added the configuration to create New Relic Deployment markers when deploying, reconfigure, LTI
     CURRENT_USER now uses users.cfg in the config folder to show the display name of the person doing the deployment
     Ansible - [DEPRECATION WARNING]: Instead of using `result|succeeded` use `result is succeeded`

2018-08-13: Corne Oosthuizen
      Added watson transcription service config and workflow.

2018-09-03: Corne Oosthuizen
      Improved set deployment markers with the appropriate src branch and code. Only set markers on production deployments.

2018-09-20: Corne Oosthuizen
      Maven 3.x has the capability to perform parallel builds. The command is as follows:
            mvn -T 4 clean install # Builds with 4 threads
            mvn -T 1C clean install # 1 thread per cpu core
            mvn -T 1.5C clean install # 1.5 thread per cpu core

      This build-mode analyzes your project's dependency graph and schedules modules that can be built in parallel according to the dependency graph of your project.

      BUILD: mvn -T 1C clean install -Dmaven.test.skip=true
      Reduce compile time from ± 15min to ± 3min

      Changed the creation of configuration files to run as background jobs.
