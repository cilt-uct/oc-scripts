# UCT Opencast Build Script

Scripts used to build and deploy Opencast from source to multiple servers, each with their own configuration.

## Getting Started

* Make sure you have Java-8 JDK (not JRE) installed.

    `java -version
    javac -version`

* Make sure you have Maven (mvn) 3.3 or later installed, the java version should be the same as shown above (Building source).

    `mvn -version`

* Make sure you have Ansible 2.1 or later installed (Deploying to the respective servers).

    `ansible --version`


* Make sure you have XMLStarlet installed (To obtain the source build version).

    `apt-get install xmlstarlet`

* Check out oc-scripts into some folder.

    `git clone https://github.com/cilt-uct/oc-scripts.git /usr/local/src/scripts`

* Configure your `config.sh` file:

    `cp config-dist.sh config.sh`

### Deploy configurations

Remember to create and modify the appropriate deployment configuration file.

```
cp deploy-example.cfg deploy-dev.cfg
cp deploy-example.cfg deploy-prod.cfg
cp deploy-example.cfg deploy-staging.cfg
cp users-example.cfg users.cfg

cp hosts/example hosts/dev
cp hosts/example hosts/production
cp hosts/example hosts/staging
```

### Configuring Servers

1. Add the server name to the appropriate hosts file 'hosts/'

  * **dev**: Development servers
  * **production**: Production servers
  * **staging**: Staging servers

2. Create a folder in `files/config` with the name of the server e.g `srvubuopc001` and the following structure

```
files/config/[servername]
├── bin
└── etc
```

3. Configure server build file:

    `cp build-example.cfg build-[servername].cfg`

Note: additional configuration parameters is defined in `build-all.cfg`.

4. Configure server configuration file (used when the distribution is deployed on the server):

    `cp conf-example.cfg conf-[servername].cfg`

Note: `server_url` in `conf-[servername].cfg` should be identical to `deploy_server_name` in `build-[servername].cfg`.

## Running

  Usage: run.sh [options] (Deploy type: dev, production | prod, staging)

  Example: run.sh -bd prod
           Build source, package and deploy to production servers.

  NOTE: If configured some options also add JIRA comments and New Relic deployment markers.

  Options:

  -h, --help
      This help text.

  -a, --all
      Update the source, build it, clean the servers and deploy new build.

  --alias
      Deploy the Opencast bash aliases file to each server to make interaction with the sytem easier.

  -b, --build
      Will build the assemblies for $SRC (e.g mvn clean install) with the current source.

  -c, --clean
      Will clean the deployment of opencast on all the associated servers.
      a) Clean Database
      b) Clean Indexes, Distribution and Workspace

  -d, --deploy
      Deploy the currently build assemblies to their respective servers.

  -t, --lti-deploy
      Deploy LTI tool static files to the appropriate servers.

  -l, --list
      List the servers that can be updated with this script.

  --ocr
      Deploy the Tesseract and hunspell data and dictionary files.

  --track4k
      Deploy Track4k binary files to the appropriate nodes.

  --audiotrim
      Deploy or update the audio trim detector script from github.

  -r, --reconfig
      Reconfigure the respective servers. Deploy configuration build to each,
      which includes custom.properties, encoding profiles and workflows.

  -u, --update-git
      Will update $SRC to include the latest changes on the selected branch.
      e.g git fetch && git pull

  -s, --status
      Display the current git status of the source folder ($SRC) and assemblies.

  -v, --version
      Run a script on each server and return the version of all the program dependencies.

  -x, --xtop
      Stop all opencast services on the respective servers.

  -z, --ztart
      Start all opencast services on the respective servers.

  --
      Do not interpret any more arguments as options.

Note: The deploy and reconfiguration on production and staging will not be run if the source or script folder are not up-to-date with respects to their repositories (all changes committed).

### Keeping it all up-to-date

It might be good practice to setup the repository to use access keys (SSH keys / read-only) to keep it up-to-date (see Github repository Settings > Access keys for more information).

* To update repository.

    `./get.sh`

* To push any commits back to master.

    `/push.sh`


## After Deploy

Reconstruct the Admin UI search index. There are two ways to reconstruct the index:

By opening [http://mediadev.uct.ac.za/admin-ng/index/recreateIndex](http://mediadev.uct.ac.za/admin-ng/index/recreateIndex) or [http://media.uct.ac.za/admin-ng/index/recreateIndex](http://media.uct.ac.za/admin-ng/index/recreateIndex) in your browser. The resulting page is empty but should return an HTTP status 200 (OK).

By using the REST documentation, open "Admin UI - Index Endpoint" and use the testing form on  /recreateIndex. The resulting page is empty but should return an HTTP status 200 (OK). You can find the REST documentation in the help-section of the Admin UI behind the ?-symbol.

TODO: Add and review [https://docs.opencast.org/latest/admin/upgrade/](https://docs.opencast.org/latest/admin/upgrade/).


## Workflows

| ID | Title | Description | UCT | Tag |
|----|-------|-------------|-----|-----|
| partial-cleanup | Cleanup after processing | |:x:| - |
| partial-watermark | Render watermark into presenter and presentation tracks | |:x:| - |
| uct-clean | UCT - Retract and Cleanup | Retract a recording and clean out media files. |:heavy_check_mark:| archive |
| uct-discard | UCT - Discard Media | Discard all the media from this event. |:heavy_check_mark:| archive |
| uct-include-autotrim-detection | Audio trim point detection | Run the audio analysis for (possible) autotrimming of the recording |:heavy_check_mark:| archive |
| uct-include-before-edit-auto-trim | UCT - Process for Editing (Auto Trim) | Publish directly from ingest process using autodetected trimpoints. |:heavy_check_mark:| - |
| uct-include-before-edit-review | UCT - Process for Editing (Review) | Using the work flavors this workflow creates */preview versions for review. |:heavy_check_mark:| - |
| uct-include-partial-download-abde | Download for ABDE | |:heavy_check_mark:| - |
| uct-include-partial-preview-abde | Preview for ABDE | |:heavy_check_mark:| - |
| uct-include-transcription-watson | Submit trimmed audio for Watson Transcription | Runs after real publishing of media uses |:heavy_check_mark:| - |
| uct-ingest-only | UCT - Ingest Only | Ingest source material |:heavy_check_mark:| schedule |
| uct-partial-ingest | UCT - Ingest asset | |:heavy_check_mark:| - |
| uct-partial-preview | Prepare preview artifacts (*/work > */preview) | |:heavy_check_mark:| - |
| uct-partial-publish-coverimage | UCT - Publish Coverimage | |:heavy_check_mark:| x |
| uct-partial-publish-downloads | UCT - Publish Downloads | |:heavy_check_mark:| - |
| uct-partial-publish | Publish the recording | |:heavy_check_mark:| - |
| uct-partial-work | Prepare work versions | |:heavy_check_mark:| - |
|  uct-partial-work-channel | Prepare work versions - with selection of audio channel | |:heavy_check_mark:| - |
| uct-process-before-edit | UCT - Process for Editing | |:heavy_check_mark:| upload, schedule |
| uct-process-obs | UCT - Process OBS Recording | |:heavy_check_mark:| schedule |
| uct-process-personal | UCT - Process for Personal Series | |:heavy_check_mark:| schedule |
| uct-process-track4k  | UCT - Process Source with Track4K | |:heavy_check_mark:| archive |
| uct-process-upload | UCT - Process Upload | |:heavy_check_mark:| upload |
| uct-publish-after-edit | UCT - Publish | |:heavy_check_mark:| editor |
| uct-publish-feed | UCT - Publish feed | |:heavy_check_mark:| - |
| uct-request-consent | Request consent | |:heavy_check_mark:| - |
| uct-test | Testing workflow | Various |:heavy_check_mark:| various |
| uct-transcript-watson | Submit trimmed audio for Watson Transcription | |:heavy_check_mark:| archive |
| uct-update-previews | Update previews | |:heavy_check_mark:| archive |
