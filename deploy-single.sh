#! /bin/bash

source config-dist.sh

# internal configuration
CONFIG_DIR="config"
SRC_VERSION=$(xmlstarlet sel -t -v "/_:project/_:version" $SRC/pom.xml)
HOSTFILES=("dev" "production")
CURRENT_USER=$(logname)

# should we execute permanent scripts
LIVE=true

DEPLOY_TYPE="dev"
HOSTS_FILE=$HOSTS_FOLDER"tmp"

# action variables (what we will do)
FULL=false
DEPLOY=false
FORCE_DEPLOY=false
LTI=false
INSTALL=false
RECONFIGURE=false
ROLLBACK=false
STARTUP=false
STOP=false
VERSION=false
ALIAS=false
TEST=false
TRACK4K=false
TRIMPOINT=false
EMPTYVENUE=false
OCR=false
SOX=false
ACTIONS=0

target_server=""
target_section=""
target_hostfile=""

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

    build_file="$FILES/config/build-$name.cfg"
    if [ ! -f "$build_file" ]; then
        echo "deploy_server_name=http://$name.uct.ac.za:8080" > $build_file
    fi

    # replace the server specific settings
    writeConfiguration $build_file $file

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
            sed -i -e "/#.*/! s;NNNN;$name;" "$cfg_file"
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
    echo "Actions for $target_server [$target_section] ($target_hostfile):"

    # if we are deploying then don't do reconfigure or rollback
    if [[ ( $RECONFIGURE || $ROLLBACK ) && $DEPLOY ]]; then
        $RECONFIGURE && ACTIONS=$((ACTIONS-1))
        $ROLLBACK && ACTIONS=$((ACTIONS-1))
        RECONFIGURE=false
        ROLLBACK=false
    fi 

    # if we rollback then we can't deploy or reconfigure
    if $ROLLBACK && $RECONFIGURE; then
        $DEPLOY && ACTIONS=$((ACTIONS-1))
        $RECONFIGURE && ACTIONS=$((ACTIONS-1))
        DEPLOY=false
        RECONFIGURE=false
    fi

    $DEPLOY && printf "Deploy"
    $DEPLOY && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $RECONFIGURE && printf "Reconfigure"
    $RECONFIGURE && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $ROLLBACK && printf "Rollback"
    $ROLLBACK && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $LTI && printf "Deploy LTI Tool"
    $LTI && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $INSTALL && printf "Install ALL Packages"
    $INSTALL && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $VERSION && printf "Check dependencies"
    $VERSION && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $STOP && printf "Stop Services"
    $STOP && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $STARTUP && printf "Start Services"
    $STARTUP && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $ALIAS && printf "Deploy Bash Aliases"
    $ALIAS && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $TEST && printf "Run Dependency Test"
    $TEST && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $TRIMPOINT && printf "Deploy Audio trimpoint detection"
    $TRIMPOINT && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $EMPTYVENUE && printf "Deploy Empty Venue detection"
    $EMPTYVENUE && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $OCR && printf "Deploy Tesseract and Hunspell data"
    $OCR && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))

    $SOX && printf "Deploy Sox"
    $SOX && [ "$ACTIONS" -gt "1" ] && printf " - " && ACTIONS=$((ACTIONS-1))    

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

    # For Jira comment date
    st=$(date +'%Y-%m-%d %H-%M-%S')
    extra_vars="production=$([ $DEPLOY_TYPE = "prod" ] && echo "true" || echo "false") deploy_date_time=\"$st\" by=\"$(getCurrentUser)\" "

    if $INSTALL; then
        cd $YML
        echo "Install ALL Packages: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-install-packages.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
        $LIVE && echo $(addDeploymentMarker $production "Install Packages" $gitlog $branch)
    fi

    # the script folder is valid or we are just doing dev OR forced to deploy or rollback
    if $FORCE_DEPLOY || $ROLLBACK || $valid_script || [ $DEPLOY_TYPE = "dev" ]; then

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

            cd $YML
            echo "Deploy: ($HOSTS_FILE)"                    
            $LIVE && ansible-playbook -i $HOSTS_FILE ansible-deploy.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
            $LIVE && echo $(addDeploymentMarker $production "Deploy" $gitlog $branch)
        fi

        # don't deploy and reconfigure
        if $RECONFIGURE && [ $compiled -eq 1 ]; then

            cd $YML
            echo "Reconfigure: ($HOSTS_FILE)"
            $LIVE && ansible-playbook -i $HOSTS_FILE ansible-reconfig.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
            $LIVE && echo $(addDeploymentMarker $production "Reconfigure" $gitlog $branch)
        fi

        if $ROLLBACK; then

            cd $YML
            echo "Rollback: ($HOSTS_FILE)"
            $LIVE && ansible-playbook -i $HOSTS_FILE ansible-rollback.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
            $LIVE && echo $(addDeploymentMarker $production "Rollback" $gitlog $branch)
        fi                

        echo
    else
        printf "    NOT "
        $DEPLOY && printf "DEPLOYING"
        $ROLLBACK && printf "ROLLING BACK"
        $RECONFIGURE && printf "RECONFIGURING"
        echo ": script ($YML) contains uncommited/added items."
        echo
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
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-lti.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
        $LIVE && echo $(addDeploymentMarker $production "LTI" $gitlog $branch)
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
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-stop_service.yml
    fi

    if $STARTUP && [ $compiled -eq 1 ]; then

        cd $YML
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-start_service.yml
    fi

    if $ALIAS; then

        cd $YML
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-alias.yml
    fi

    if $TEST; then
        cd $YML
        echo "Deploy Testing Script: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-testing.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
    fi    

    if $TRACK4K; then
        track_log=$(git -C $TRACK4K_SRC show --oneline | head -n 1)
        track_branch=$(git -C $TRACK4K_SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

        cd $YML
        echo "Deploy Track4K: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-track4k.yml --extra-vars "$extra_vars gitbranch=\"$track_branch\" gitlog=\"$track_log\" "
        $LIVE && echo $(addDeploymentMarker $production "Track4K" $track_log $track_branch)
    fi

    if $EMPTYVENUE; then
        empty_log=$(git -C $EMPTY_VENUE_SRC show --oneline | head -n 1)
        empty_branch=$(git -C $EMPTY_VENUE_SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

        cd $YML
        echo "Deploy Empty Venue: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-emptyvenuedetector.yml --extra-vars "$extra_vars gitbranch=\"$empty_branch\" gitlog=\"$empty_log\" "
        $LIVE && echo $(addDeploymentMarker $production "EmptyVenueDetect" $empty_log $empty_branch)
    fi

    if $TRIMPOINT; then
        trim_log=$(git -C $AUDIO_TRIM_SRC show --oneline | head -n 1)
        trim_branch=$(git -C $AUDIO_TRIM_SRC rev-parse --symbolic-full-name --abbrev-ref HEAD)

        cd $YML
        echo "Deploy Audio Trim Point Detector: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-trimpointdetector.yml --extra-vars "$extra_vars gitbranch=\"$trim_branch\" gitlog=\"$trim_log\" "
        $LIVE && echo $(addDeploymentMarker $production "AudioTrimPoint" $trim_log $trim_branch)
    fi

    if $OCR; then
        cd $YML
        echo "Deploy OCR: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-deploy-ocr.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
        $LIVE && echo $(addDeploymentMarker $production "OCR" $gitlog $branch)
    fi

    if $SOX; then
        cd $YML
        echo "Deploy Sox: ($HOSTS_FILE)"
        $LIVE && ansible-playbook -i $HOSTS_FILE ansible-deploy-sox.yml --extra-vars "$extra_vars gitbranch=\"$branch\" gitlog=\"$gitlog\" "
        $LIVE && echo $(addDeploymentMarker $production "Sox" $gitlog $branch)
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

    echo "Usage: $PROGNAME [options] (srv|dev)ubuopc(xxx)"
    echo
    echo "  Example: $PROGNAME -d srvubuopc001"
    echo "           Deploy Opencast to srvubuopc001"
    echo
    echo "  NOTE: If configured some options also add JIRA comments and New Relic deployment markers."
    echo
    echo "Options:"
    echo
    echo "  -h, --help"
    echo "      This help text."
    echo
    echo "  -a, --all"
    echo "      Deploy build to specified server and ALL other dependencies (alias,lti,ocr,sox,track4k,audiotrim,emptyvenue)"
    echo
    echo "  --alias"
    echo "      Deploy the Opencast bash aliases file to each server to make interaction with the sytem easier."
    echo
    echo "  -d, --deploy"
    echo "      Deploy the currently build assemblies to their respective servers - only if source code is 'clean' or 'dev'."
    echo
    echo "  -f, --force"
    echo "      Force deploy the currently build assemblies to their respective servers."
    echo
    echo "  -i, --install"
    echo "      Install ALL packages and create Opencast User (ffmpeg hunspell sox tesseract-ocr, perl, python, OpenJDK)."
    echo
    echo "  -t, --lti-deploy"
    echo "      Deploy LTI tool static files to the appropriate servers."
    echo
    echo "  --ocr"
    echo "      Deploy Tesseract and hunspell with all the required language and dictionary files."
    echo
    echo "  --sox"
    echo "      Deploy Sox."
    echo    
    echo "  --test"
    echo "      Deploy Opencast dependency testing script and run it."
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
ARGS=$(getopt -o ":abdifhrtvxz" -l ":one,all,build,deploy,force,install,help,reconfig,rollback,version,xtop,ztart,lti-deploy,alias,test,track4k,audiotrim,emptyvenue,ocr,sox" -n "$PROGNAME" -- "$@")

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
            ALIAS=true
            INSTALL=true
            DEPLOY=true
            LTI=true
            TEST=true
            TRACK4K=true
            TRIMPOINT=true
            EMPTYVENUE=true
            OCR=true
            SOX=true

            ACTIONS=9
            MORE=false
            shift
            ;;
        --alias)
            $MORE && ALIAS=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -d|--deploy)
            $MORE && DEPLOY=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -f|--force)
            $MORE && FORCE_DEPLOY=true
            $MORE && DEPLOY=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -i|--install)
            $MORE && INSTALL=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;                    
        -t|--lti-deploy)
            $MORE && LTI=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --test)
            $MORE && TEST=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --track4k)
            $MORE && TRACK4K=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --audiotrim)
            $MORE && TRIMPOINT=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --emptyvenue)
            $MORE && EMPTYVENUE=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -l|--list)
            $MORE && LIST=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --ocr)
            $MORE && OCR=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --sox)
            $MORE && SOX=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -r|--reconfig)
            $MORE && RECONFIGURE=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        --rollback)
            $MORE && ROLLBACK=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -v|--version)
            $MORE && VERSION=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -x|--xtop)
            $MORE && STOP=true
            $MORE && ACTIONS=$((ACTIONS+1))
            shift
            ;;
        -z|--ztart)
            $MORE && STARTUP=true
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
    if [[ $arg != srv* ]]; then
        target_server="$arg"
    fi
    if [[ $arg != dev* ]]; then
        target_server="$arg"
    fi
done

if [ $ACTIONS -eq 0 ]; then
    # if there are no actions / only deploy type then show usage
    usage $@
    exit 1
fi

if [[ ! "$target_server" == *".uct.ac.za"* ]]; then
    target_server="$target_server.uct.ac.za"
fi

test_target_server=$(echo "$target_server" | cut -f1 -d".")
for host_file in "${HOSTFILES[@]}"; do

    # Read the hosts file for the profile and populate a list of servers that will be
    # used to build configuration files for and deploy/reconfigure
    test_section=""

    while read line
    do
        if [[ $line == \[* ]]; then
            test_section=$line
        fi

        [[ $line = \#* ]] && continue

        if [ ! -z "$line" ]; then

            if [[ $line != \[* ]]; then
                name=$( echo $line | cut -d'.' -f 1)
                if [[ $name == "$test_target_server" ]]; then
                    target_section=$(echo "$test_section" | sed 's/\[//g' | sed 's/\]//g')
                    target_hostfile="$host_file"
                fi
            fi
        fi

    done < "$HOSTS_FOLDER""$host_file"
done

DEPLOY_TYPE=$target_hostfile
if [[ $DEPLOY_TYPE == "production" ]]; then
    DEPLOY_TYPE="prod"
fi

ACTIVE_SERVER_LIST=("$test_target_server")
echo "[$target_section]" > $HOSTS_FILE
echo "$target_server" >> $HOSTS_FILE

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

# for testing
NEWRELIC_USE=false

cd $CURRENT_DIR

# run main code
main
