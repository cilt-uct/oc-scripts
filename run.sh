#! /bin/bash

## Manages the building, cleaning and deployment of Opencast from this machine
## Uses:
##    - Ansible
##    - Git
##    - Maven
##    - xmlstarlet
##    - sshpass

# Original (2016-06-27): Corne Oosthuizen
# See: changelog.md

source config-dist.sh

# internal configuration
CONFIG_DIR="config"
SRC_VERSION=$(xmlstarlet sel -t -v "/_:project/_:version" $SRC/pom.xml)
DEPLOY_TYPE="dev"
HOSTS_FILE=$HOSTS_FOLDER"dev"
CURRENT_USER=$(logname)

# action variables (what we will do)
BUILD=false
CLEAN=false
DEPLOY=false
LTI=false
LIST=false
UPDATE=false
RECONFIGURE=false
ROLLBACK=false
STATUS=false
STARTUP=false
STOP=false
VERSION=false
ALIAS=false
TRACK4K=false
TRIMPOINT=false
EMPTYVENUE=false
OCR=false
ACTIONS=0

# list of servers to use
declare -a ACTIVE_LIST

# should we execute permanent scripts
LIVE=true

setStatus() {

    branch_name=$(git -C $SRC symbolic-ref -q HEAD)
    branch_name=${branch_name##refs/heads/}
    branch_name=${branch_name:-HEAD}
    echo "src: $SRC" > $STATUS_FILE
    echo >> $STATUS_FILE
    git -C $SRC status | grep $branch_name >> $STATUS_FILE
    echo "" >> $STATUS_FILE
    git -C $SRC show --oneline | head -n 1 >> $STATUS_FILE
    echo "" >> $STATUS_FILE
}

showServers() {

    cd $YML

    if [ -f $STATUS_FILE ]; then

        echo "    Servers ($HOSTS_FILE):"
        while read -r line
        do
            echo "        $line"
        done < $HOSTS_FILE
    else

        echo "    ERROR: No servers defined!"
    fi
    echo

    cd $YML
}

displayTime() {
  T=$1
  D=$((T/60/60/24))
  H=$((T/60/60%24))
  M=$((T/60%60))
  S=$((T%60))
  [ $D -ge 1 ] && printf '%d d ' $D
  [ $H -ge 1 ] && printf '%d h ' $H
  [ $M -ge 1 ] && printf '%d m ' $M
  printf '%d sec\n' $S
}

writeConfiguration() {
  INPUT=$1
  OUTPUT=$2

  while read line
  do
      [[ $line = \#* ]] && continue

      if [ ! -z "$line" ]; then

        IFS="=" read find replace <<< "$line"

        sed -i -e "/#.*/! s;$find;$replace;" $OUTPUT
      fi

  done < $INPUT
}

packageConfigurationFile() {
    name=$1
    filename=$2
    out=$3

    # replace the server specific settings
    writeConfiguration $FILES/config/build-$name.cfg $file

    # replace generic
    writeConfiguration $FILES/config/build-default.cfg $file

    if $out; then
        printf "."
    fi
}

packageConfiguration() {
    name=$1
    tmp="$TMP_DIR/$name"

    if [ "$CONFIG_DIR" != "$name" ]; then

        # make sure that the files exist for the server so that packaging them is easier next time
        cfg_dir="$FILES/config/$name"
        cfg_file="$FILES/config/conf-$name.cfg"
        build_file="$FILES/config/build-$name.cfg"

        if [ ! -f "$cfg_file" ]; then
            cp "$FILES/conf-server.template" "$cfg_file"
            sed -i -e "/#.*/! s;NNNN;$name/;" "$cfg_file"
        fi

        if [ ! -f "$build_file" ]; then
            echo "deploy_server_name=http://$name.uct.ac.za:8080" > $build_file
        fi

        if [ ! -d "$cfg_dir" ]; then
            mkdir -p "$cfg_dir/etc"
            mkdir -p "$cfg_dir/bin"
            touch "$cfg_dir/etc/.keep"
            touch "$cfg_dir/bin/.keep"
        fi

        mkdir -p $tmp

        # copy default configuration files to tmp
        cp -r $FILES/config/default/* $tmp

        # overwrite with server specific configuration files
        cp -r $FILES/config/$name/* $tmp

        for file in $(find $tmp -type f -type f -not -name ".keep" -not -name "*.jks" -not -name "*.swp")
        do
            packageConfigurationFile $name $file false &
        done
        wait

        cd $tmp
        tar -zcpf $FILES/config/conf-$name.tar.gz .
        rm -rf $tmp
        printf "."
    fi
}

require_clean_work_tree () {
    local __result=$1
    local __desc=$2
    local __msg=""
    local valid=true
    local err=0

    #git fetch
    git rev-parse --verify HEAD >/dev/null || exit 1
    git update-index -q --ignore-submodules --refresh

    if ! git diff-files --quiet --ignore-submodules
    then
        msg="$__desc has unstaged changes."
        err=1
    fi

    if ! git diff-index --cached --quiet --ignore-submodules HEAD --
    then
        msg="$__desc contains uncommitted changes."
        err=1
    fi

    if [ $err = 0 ]; then
        err=`git ls-files --exclude-standard --others| wc -l`

        if [ $err = 1 ]; then
            msg="$__desc contains untracked files ($err)."
        fi
    fi

    if [ $err = 1 ]; then

        # valid=false
        echo "    $msg"
    fi

    eval $__result="'$valid'"
}

# Get the display name of the user
# params:
# $1 -- the section (if any)
# $2 -- the key
getCurrentUser() {

  section="users"
  key=$CURRENT_USER

  value=$(
    if [ -n "$section" ]; then
      sed -n "/^\[$section\]/, /^\[/p" $DEPLOY_CFG_FOLDER/users.cfg
    else
      cat $DEPLOY_CFG_FOLDER/users.cfg
    fi |

    egrep "^ *\b$key\b *=" |

    head -1 | cut -f2 -d'=' |
    sed 's/^[ "'']*//g' |
    sed 's/[ ",'']*$//g' )

  if [ -n "$value" ]; then
    echo $value
    return
  else
    echo $key
    return
  fi
}

addDeploymentMarker() {
    local production=$1
    local type=$2
    local gitlog=$3
    local branch=$4

    if $NEWRELIC_USE && $production; then

        printf "Set deploy marker: "
        result=$(curl --write-out '%{http_code}' --silent --output /dev/null -X POST "https://api.newrelic.com/v2/applications/$NEWRELIC_APP/deployments.json" \
                -H "X-Api-Key:$NEWRELIC_API" -i \
                -H 'Content-Type: application/json' \
                -d \
            "{
                \"deployment\": {
                    \"revision\": \"$branch\",
                    \"changelog\": \"$DEPLOY_TYPE-$type\",
                    \"description\": \"$gitlog\",
                    \"user\": \"$(getCurrentUser)\"
                }
            }")
        if [ $result = "201" ]; then
            echo "done"
        else
            echo "error [$result]"
        fi
        echo
    fi
}

main() {

    echo #$ACTIONS
    printf "Actions [$DEPLOY_TYPE]($SRC_VERSION): "

    $UPDATE && printf "Update"
    $UPDATE && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $BUILD && printf "Build"
    $BUILD && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $CLEAN && printf "Clean"
    $CLEAN && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    if $RECONFIGURE; then

        if $( ! $DEPLOY) && $(! $ROLLBACK); then
            printf "Reconfigure"
            [ "$ACTIONS" -gt "1" ] && printf " - "
        else
            RECONFIGURE=false
        fi

        ACTIONS=$((ACTIONS-1))
    fi

     if $ROLLBACK; then

        if $( ! $DEPLOY) && $(! $RECONFIGURE); then
            printf "Rollback"
            [ "$ACTIONS" -gt "1" ] && printf " - "
        else
            ROLLBACK=false
        fi

        ACTIONS=$((ACTIONS-1))
    fi

    $DEPLOY && printf "Deploy"
    $DEPLOY && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $LTI && printf "Deploy LTI Tool"
    $LTI && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $VERSION && printf "Check dependencies"
    $VERSION && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $STOP && printf "Stop Services"
    $STOP && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $STARTUP && printf "Start Services"
    $STARTUP && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $ALIAS && printf "Deploy Bash Aliases"
    $ALIAS && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $TRACK4K && printf "Deploy Track4K"
    $TRACK4K && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $TRIMPOINT && printf "Deploy Audio trimpoint detection"
    $TRIMPOINT && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $EMPTYVENUE && printf "Deploy Empty Venue detection"
    $EMPTYVENUE && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $OCR && printf "Deploy Tesseract and Hunspell data"
    $OCR && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    if $LIST && $( ! $STATUS); then
        printf "Display List Servers"
        [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))
    fi

    $STATUS && printf "Show Current Status"
    echo
    echo

    start_time=`date +%s`
    compiled=1

    if [[ $DEPLOY_TYPE = "prod" ]]; then
        production=true
    else
        production=false
    fi

    # OC source gitlog and branch
    gitlog=$(git -C $SRC show --oneline | head -n 1)
    branch=$(git -C $SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

    cd $SRC
    require_clean_work_tree valid_src "Source ($SRC)"
    $(! $valid_src) && echo

    cd $YML
    require_clean_work_tree valid_script "Script ($YML)"
    $(! $valid_script) && echo

    # should be first
    if $UPDATE; then

        echo "Updating opencast build ..."
        git -C $SRC fetch && git -C $SRC pull
        echo
    fi

    # should be second before displaying status
    if $BUILD; then

        st=$(date +'%Y-%m-%d.%H-%M-%S')
        log_file=$YML"/log/oc-build."$st".log"
        now=$(date +'%Y-%m-%d %H:%M:%S')
        target=$(date --date='3 minutes' +'%Y-%m-%d %H:%M:%S')

        # the source is valid or we are just doing dev in which case
        # build source
        if $valid_src || [ $DEPLOY_TYPE = "dev" ]; then

            echo "Building source: "
            echo "    mvn -T 1C clean install -Dmaven.test.skip=true (takes around 3min)"
            echo "        $now : Started"
            echo "        $target : Target"

            if $LIVE; then
                cd $SRC

                #/usr/local/src/opencast-uct/modules/matterhorn-admin-ui-ng# rm -rf node_modules/*
                mvn -T 1C clean install -Dmaven.test.skip=true --log-file $log_file
                EXEC_STATUS=$?

                cd $YML

                now=$(date +'%Y-%m-%d %H:%M:%S')
                echo "        $now : Completed"
                echo

                if [ $EXEC_STATUS -eq 0 ]; then
                    compiled=1
                    echo "    SUCCESS"
                    echo "Last Build ($now) - SUCCESS" > $BUILD_STATUS_FILE

                else
                    compiled=0
                    echo "    ERROR"
                    echo "Last Build ($now) - ERROR" > $BUILD_STATUS_FILE
                fi

                echo "    (Log: $log_file)"
                echo
            else
                echo "    SUCCESS (NOT LIVE)"
            fi
        else

            if $( ! $valid_src); then
                echo "    NOT BUILD: source ($SRC) contains uncommited/added items."
                echo
            fi
        fi

        cd $YML
    fi

    if $CLEAN && [ $compiled -eq 1 ]; then

        echo "Clean: ($HOSTS_FILE)"

        if [ $DEPLOY_TYPE = "dev" ]; then
          cd $YML

          extra="full_clean=true"

          if $( ! $DEPLOY); then

              # we will start after deploy
              extra="$extra start_service=false"
          fi

          $LIVE && ansible-playbook -i $HOSTS_FILE ansible-clean.yml --extra-vars "$extra"
          echo

          cd $YML
        else

          echo "    Cleaning can only be performed on 'dev'."
          echo
        fi
    fi

   # the script folder is valid or we are just doing dev
   if $valid_script || [ $DEPLOY_TYPE = "dev" ]; then

        if $DEPLOY || $RECONFIGURE || $ROLLBACK; then

            cd $YML

            # copy workflow scripts to default
            mkdir -p $FILES/config/default/wfexec/
            cp -pr $FILES/worker/wfexec/* $FILES/config/default/wfexec/

            echo "    Packaging configurations:"
            printf "       "
            for name in "${ACTIVE_SERVER_LIST[@]}"; do
                if [ "$CONFIG_DIR" != "$name" ]; then
                   packageConfiguration $name &
                fi
            done
            wait
            echo
            echo "    Done."
            echo
        fi

        if $DEPLOY && [ $compiled -eq 1 ]; then

            echo "Deploy: ($HOSTS_FILE)"
	        st=$(date +'%Y-%m-%d %H-%M-%S')

            cd $YML
            $LIVE && ansible-playbook -i $HOSTS_FILE ansible-deploy.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

            echo $(addDeploymentMarker $production "Deploy" $gitlog $branch)
        fi

        # don't deploy and reconfigure
        if $RECONFIGURE && [ $compiled -eq 1 ]; then

            echo "Reconfigure: ($HOSTS_FILE)"
	        st=$(date +'%Y-%m-%d %H-%M-%S')

            cd $YML
            $LIVE && ansible-playbook -i $HOSTS_FILE ansible-reconfig.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

            echo $(addDeploymentMarker $production "Reconfigure" $gitlog $branch)
        fi

        if $ROLLBACK; then

            echo "Rollback: ($HOSTS_FILE)"
            st=$(date +'%Y-%m-%d %H-%M-%S')

            cd $YML
            $LIVE && ansible-playbook -i $HOSTS_FILE ansible-rollback.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

            echo $(addDeploymentMarker $production "Rollback" $gitlog $branch)
        fi

        echo
    else

        if $( ! $valid_script) && $( ! $VERSION); then
            printf "    NOT "
            $DEPLOY && printf "DEPLOYING"
            $RECONFIGURE && $( ! $DEPLOY) && printf "RECONFIGURING"
            echo ": script ($YML) contains uncommited/added items."
            echo
        fi
    fi

    if $LTI; then

        #hope that TMP_DIR != '/'
        rm -rf $TMP_DIR/*

        echo "Creating tarball for LTI"
        current_date=`date +%Y%m%d-%H%M%P`

        cd $TMP_DIR
        cp $SRC/modules/lti/src/main/resources/tools/* . -R

        #Versioning of static assets (e.g. css, js)
        find . -type f -print0 | xargs -0 sed -i -e "s/%version%/$current_date/g"

        tar -zcf ../lti.tar.gz .

        rm -rf $TMP_DIR/*

        cd $YML
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-lti.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false")"

        echo $(addDeploymentMarker $production "LTI" $gitlog $branch)
    fi

    # STATUS will show list of servers
    if $LIST && $( ! $STATUS) && [ $compiled -eq 1 ]; then

        cd $YML
        showServers
    fi

    if $VERSION; then

        cd $YML

        # clean out tmp directory
        rm -rf $TMP_DIR/*

        echo "   Creating dependency check configurations:"
        printf "       "
        for name in "${ACTIVE_SERVER_LIST[@]}"; do

            if [ "$CONFIG_DIR" != "$name" ]; then

                file=$TMP_DIR/conf-$name.cfg
                cp $FILES/check.template $file

                packageConfigurationFile $name $file true &
            fi
        done
        wait
        echo
        echo "    Done."
        echo

        cd $YML
        ansible-playbook -i $HOSTS_FILE ansible-check.yml

        # clean out tmp directory
        rm -rf $TMP_DIR/*
    fi

    if $STOP; then

      cd $YML
      ansible-playbook -i $HOSTS_FILE ansible-stop_service.yml
    fi

    if $STARTUP && [ $compiled -eq 1 ]; then

      cd $YML
      ansible-playbook -i $HOSTS_FILE ansible-start_service.yml
    fi

    if $ALIAS; then

      cd $YML
      ansible-playbook -i $HOSTS_FILE ansible-alias.yml
    fi

    if $TRACK4K; then

        cd $YML
        ansible-playbook -i $HOSTS_FILE ansible-track4k.yml

        track_log=$(git -C $TRACK4K_SRC show --oneline | head -n 1)
        track_branch=$(git -C $TRACK4K_SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

        echo $(addDeploymentMarker $production "Track4K" $track_log $track_branch)
    fi

    if $EMPTYVENUE; then

        cd $YML
        st=$(date +'%Y-%m-%d %H-%M-%S')
        ansible-playbook -i $HOSTS_FILE ansible-emptyvenuedetector.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

        empty_log=$(git -C $EMPTY_VENUE_SRC show --oneline | head -n 1)
        empty_branch=$(git -C $EMPTY_VENUE_SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

        echo $(addDeploymentMarker $production "EmptyVenueDetect" $empty_log $empty_branch)
    fi

    if $TRIMPOINT; then

        cd $YML
        st=$(date +'%Y-%m-%d %H-%M-%S')
        ansible-playbook -i $HOSTS_FILE ansible-trimpointdetector.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

        trim_log=$(git -C $AUDIO_TRIM_SRC show --oneline | head -n 1)
        trim_branch=$(git -C $AUDIO_TRIM_SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

        echo $(addDeploymentMarker $production "AudioTrimPoint" $trim_log $trim_branch)
    fi

    if $OCR; then

        cd $YML
        st=$(date +'%Y-%m-%d %H-%M-%S')
        ansible-playbook -i $HOSTS_FILE ansible-deploy-ocr.yml --extra-vars "production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

        ocr_log=$(git -C $OCR_SCR show --oneline | head -n 1)
        ocr_branch=$(git -C $OCR_SCR rev-parse --symbolic-full-name --abbrev-ref HEAD)

        echo $(addDeploymentMarker $production "OCR" $ocr_log $ocr_branch)
    fi

    if $STATUS; then

        cd $YML

        setStatus
        echo "Current Status:"

        if [ -f $STATUS_FILE ]; then

            while read -r line
            do
                printf "\t$line\n"
            done < $STATUS_FILE
        fi

        if [ -f $BUILD_STATUS_FILE ]; then

            while read -r line
            do
                printf "\t$line\n"
            done < $BUILD_STATUS_FILE
            echo
        fi

        if [ $compiled -eq 1 ]; then
          showServers
        fi

        # also display state / running of service
    fi

    end_time=`date +%s`
    duration=$(( $(date "+%s") - $(echo $start_time) ))

    printf "Execution time was "
    displayTime $duration

    echo

    cd $CURRENT_DIR
}

usage() {

    if [ $# -ne 0 ]; then
        echo
        echo "One or more options cannot be processed: '$@' (See below)."
        echo
    fi

    echo "Usage: $PROGNAME [options] (Deploy type: dev, production | prod, staging)"
    echo
    echo "  Example: $PROGNAME -bd prod"
    echo "           Build source, package and deploy to production servers."
    echo
    echo "  NOTE: If configured some options also add JIRA comments and New Relic deployment markers."
    echo
    echo "Options:"
    echo
    echo "  -h, --help"
    echo "      This help text."
    echo
    echo "  -a, --all"
    echo "      Update the source, build it, clean the servers and deploy new build."
    echo
    echo "  --alias"
    echo "      Deploy the Opencast bash aliases file to each server to make interaction with the sytem easier."
    echo
    echo "  -b, --build"
    echo "      Will build the assemblies for $SRC (e.g mvn -T 1C clean install) with the current source."
    echo
    echo "  -c, --clean"
    echo "      Will clean the deployment of opencast on all the associated servers."
    echo "      a) Clean Database (Only works for development)"
    echo "      b) Clean Indexes, Distribution and Workspace"
    echo
    echo "  -d, --deploy"
    echo "      Deploy the currently build assemblies to their respective servers."
    echo
    echo "  -t, --lti-deploy"
    echo "      Deploy LTI tool static files to the appropriate servers."
    echo
    echo "  -l, --list"
    echo "      List the servers that can be updated with this script."
    echo
    echo "  --ocr"
    echo "      Deploy the Tesseract and hunspell data and dictionary files."
    echo
    echo "  --track4k"
    echo "      Deploy Track4k binary files to the appropriate nodes."
    echo
    echo "  --audiotrim"
    echo "      Deploy or update the audio trim detector script from github."
    echo
    echo "  --emptyvenue"
    echo "      Deploy or update the empty venue detector script from github."
    echo
    echo "  -r, --reconfig"
    echo "      Reconfigure the respective servers. Deploy configuration build to each,"
    echo "      which includes custom.properties, encoding profiles and workflows."
    echo
    echo "  --rollback"
    echo "      Rollback the respective servers. The previous version (backup folder)"
    echo "      will now be used as the live version and now the live bversion is in the backup folder"
    echo
    echo "  -s, --status"
    echo "      Display the current git status of the source folder ($SRC) and assemblies."
    echo
    echo "  -u, --update-git"
    echo "      Will update $SRC to include the latest changes on the selected branch."
    echo "      e.g git fetch && git pull"
    echo
    echo "  -v, --version"
    echo "      Run a script on each server and return the version of all the program dependencies."
    echo
    echo "  -x, --xtop"
    echo "      Stop all opencast services on the respective servers."
    echo
    echo "  -z, --ztart"
    echo "      Start all opencast services on the respective servers."
    echo
    echo "  --"
    echo "      Do not interpret any more arguments as options."
    echo
}

## Start parsing arguments ##
## TODO: Add optional parameters to
##       - build: 0 (default) Do All, 1 build src, 2 build cfg
#        - clean: 0 (default) Do All, 1 clean only db, 2 clean shared+archive+distribution
ARGS=$(getopt -o ":abcdhlrstuvxz" -l ":all,build,clean,deploy,help,list,reconfig,rollback,update-git,status,version,xtop,ztart,lti-deploy,alias,track4k,audiotrim,emptyvenue,ocr" -n "$PROGNAME" -- "$@")

if [ $? -ne 0 ] || [ $# -eq 0 ]; then
    # if error in parsing args display usage
    usage $@
    exit 1
fi

MORE=true
eval set -- "$ARGS"
while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -a|--all)
            BUILD=true
            CLEAN=true
            DEPLOY=true
            UPDATE=true
            STATUS=true
            ACTIONS=5
            MORE=false
            shift
            ;;
        --alias)
            ALIAS=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -b|--build)
            BUILD=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -c|--clean)
            CLEAN=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -d|--deploy)
            DEPLOY=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -t|--lti-deploy)
            LTI=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --track4k)
            TRACK4K=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --audiotrim)
            TRIMPOINT=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --emptyvenue)
            EMPTYVENUE=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;    
        -l|--list)
            LIST=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --ocr)
            OCR=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -u|--update-git)
            UPDATE=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -r|--reconfig)
            RECONFIGURE=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --rollback)
            ROLLBACK=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -s|--status)
            STATUS=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -v|--version)
            VERSION=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -x|--xtop)
            STOP=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -z|--ztart)
            STARTUP=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Invalid option '$1'. Use --help to see the valid options" >&2
            exit 1
        ;;
        # an option argument, continue
        *) ;;
    esac
done

string="$@"
for arg in "${string,}"
do
  case "$arg" in
    "dev" )
      DEPLOY_TYPE="dev"
      HOSTS_FILE=$HOSTS_FOLDER"dev"
      shift
      break
      ;;
    "prod"|"production" )
      DEPLOY_TYPE="prod"
      HOSTS_FILE=$HOSTS_FOLDER"production"
      shift
      break
      ;;
    "staging" )
      DEPLOY_TYPE="staging"
      HOSTS_FILE=$HOSTS_FOLDER"staging"
      shift
      break
      ;;
    * )
      args+=($arg)
  esac
done

if [ -z "$DEPLOY_TYPE" ]; then
  DEPLOY_TYPE="dev"
  HOSTS_FILE=$HOSTS_FOLDER"dev"
fi

if [ $ACTIONS -eq 0 ]; then
    # if there are no actions / only deploy type then show usage
    usage $@
    exit 1
fi

# Write out the required files for this build type (deploy-[type].cfg) to the files for:
# - build and package for each server
# - deploy with ansible script

cd $YML

cp $FILES/build-all.template files/config/build-default.cfg
cp $FILES/dbservers.template group_vars/dbservers
cp $FILES/all.template group_vars/all
cp $FILES/shell_variable.template $FILES/shell_variable.sh

writeConfiguration "$DEPLOY_CFG_FOLDER/deploy-$DEPLOY_TYPE.cfg" files/config/build-default.cfg
writeConfiguration "$DEPLOY_CFG_FOLDER/deploy-$DEPLOY_TYPE.cfg" group_vars/dbservers
writeConfiguration "$DEPLOY_CFG_FOLDER/deploy-$DEPLOY_TYPE.cfg" group_vars/all
writeConfiguration "$DEPLOY_CFG_FOLDER/deploy-$DEPLOY_TYPE.cfg" $FILES/shell_variable.sh

sed -i -e "/#.*/! s;tmpl_src_version;$SRC_VERSION;" group_vars/all
sed -i -e "/#.*/! s;tmpl_folder_src;$SRC/;" group_vars/all
sed -i -e "/#.*/! s;tmpl_folder_script;$YML/;" group_vars/all

# source the shell variables that we are going to use
source $FILES/shell_variable.sh

  # Read the hosts file for the profile and populate a list of servers that will be
  # used to build configuration files for and deploy/reconfigure
  while read line
  do
      [[ $line = \#* ]] && continue

      if [ ! -z "$line" ]; then

        if [[ $line != \[* ]]; then
           name=$( echo $line | cut -d'.' -f 1)
           ACTIVE_LIST+=($name)
        fi
      fi

  done < "$HOSTS_FILE"

  ACTIVE_SERVER_LIST=($(echo "${ACTIVE_LIST[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

cd $CURRENT_DIR

# run main code
main
