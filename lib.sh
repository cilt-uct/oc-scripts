# Common helper functions for Opencast deployment scripts
#
# This file is sourced by run.sh and deploy-single.sh

# Print a human-readable duration
# Usage: displayTime <seconds>
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

# Replace key=value pairs in a file
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

# Update a config file for a server
packageConfigurationFile() {
    name=$1
    filename=$2
    out=$3

    build_file="$FILES/config/build-$name.cfg"
    if [ ! -f "$build_file" ]; then
        echo "deploy_server_name=http://$name.uct.ac.za:8080" > $build_file
        echo "deploy_server_nodename=$name.uct.ac.za" > $build_file
        echo "" > $build_file
    fi

    # replace the server specific settings
    writeConfiguration $build_file $file

    # replace generic
    writeConfiguration $FILES/config/build-default.cfg $file

    if $out; then
        printf "."
    fi
}

# Prepare config packaging for a server
packageConfiguration() {
    name=$1
    tmp="$TMP_DIR/$name"

    if [ "$CONFIG_DIR" != "$name" ]; then
        cfg_dir="$FILES/config/$name"
        cfg_file="$FILES/config/conf-$name.cfg"
        build_file="$FILES/config/build-$name.cfg"

        if [ ! -f "$cfg_file" ]; then
            cp "$FILES/conf-server.template" "$cfg_file"
            sed -i -e "/#.*/! s;NNNN;$name;" "$cfg_file"
        fi

        if [ ! -f "$build_file" ]; then
            echo "deploy_server_name=http://$name.uct.ac.za:8080" > $build_file
            echo "deploy_server_nodename=$name.uct.ac.za" > $build_file
            echo "" > $build_file
        fi

        if [ ! -d "$cfg_dir" ]; then
            mkdir -p "$cfg_dir/etc"
            mkdir -p "$cfg_dir/bin"
            touch "$cfg_dir/etc/.keep"
            touch "$cfg_dir/bin/.keep"
        fi

        mkdir -p $tmp
        cp -r $FILES/config/default/* $tmp
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

# Ensure git work tree is clean
require_clean_work_tree () {
    local __result=$1
    local __desc=$2
    local __msg=""
    local valid=true
    local err=0

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

  value=$(if [ -n "$section" ]; then
    sed -n "/^\[$section\]/, /^\[/p" $DEPLOY_CFG_FOLDER/users.cfg
  else
    cat $DEPLOY_CFG_FOLDER/users.cfg
  fi |
    egrep "^ *\\b$key\\b *=" |
    head -1 | cut -f2 -d'=' |
    sed 's/^[ "\'']*//g' |
    sed 's/[ ",\'']*$//g')

  if [ -n "$value" ]; then
    echo $value
    return
  else
    echo $key
    return
  fi
}

# Optionally set a deployment marker
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
            "{\n                \"deployment\": {\n                    \"revision\": \"$branch\",\n                    \"changelog\": \"$DEPLOY_TYPE-$type\",\n                    \"description\": \"$gitlog\",\n                    \"user\": \"$(getCurrentUser)\"\n                }\n            }")
        if [ $result = "201" ]; then
            echo "done"
        else
            echo "error [$result]"
        fi
        echo
    fi
}
