# Common helper functions for Opencast deployment scripts
#
# This file is sourced by run.sh and deploy-single.sh

# Enable timing output (set to 1 to see timings)
TIMING_DEBUG="${TIMING_DEBUG:-0}"
export TIMING_DEBUG

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

# Create server-specific build config file if missing
createBuildFile() {
    local name="$1"
    local build_file="$FILES/config/build-$name.cfg"

    if [[ ! -f "$build_file" ]]; then
        cat > "$build_file" <<EOF
deploy_server_name=http://$name.uct.ac.za:8080
deploy_server_nodename=$name.uct.ac.za

EOF
    fi
}

# Process a single configuration file (now no build-file creation)
packageConfigurationFile() {
    local name="$1"
    local filename="$2"
    local out="$3"

    local build_file="$FILES/config/build-$name.cfg"
    local default_file="$FILES/config/build-default.cfg"
    local sed_expr=()

    # Helper function to read a config file and build sed expressions
    build_sed_expressions() {
        local input_file="$1"
        while IFS= read -r line; do
            # Skip comment lines and empty lines (same as original)
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            # Split on first '='
            local find replace
            IFS="=" read -r find replace <<< "$line"
            # Escape any '/' in find/replace if needed, but keep original behavior
            # Using ';' as sed delimiter (matches original s;find;replace;)
            sed_expr+=(-e "/#.*/! s;$find;$replace;")
        done < "$input_file"
    }

    # First read build-specific, then default (default overrides)
    build_sed_expressions "$build_file"
    build_sed_expressions "$default_file"

    # Apply all substitutions in one go
    if [[ ${#sed_expr[@]} -gt 0 ]]; then
        sed -i "${sed_expr[@]}" "$filename"
    fi

    if [[ "$out" == "true" ]]; then
        printf "."
    fi
}

# Package all configurations for one server
packageConfiguration() {
    local name="$1"
    local tmp="$TMP_DIR/$name"
    local cfg_dir="$FILES/config/$name"
    local cfg_file="$FILES/config/conf-$name.cfg"
    local build_file="$FILES/config/build-$name.cfg"

    # Record overall start
    local total_start=$(date +%s)
    local step_start=$total_start

    if [[ "$CONFIG_DIR" != "$name" ]]; then

        # Create conf-$name.cfg from template if missing
        if [[ ! -f "$cfg_file" ]]; then
            cp "$FILES/conf-server.template" "$cfg_file"
            sed -i -e "/#.*/! s;NNNN;$name;" "$cfg_file"
        fi

        # Create build file once
        createBuildFile "$name"

        # Ensure cfg_dir exists
        if [[ ! -d "$cfg_dir" ]]; then
            mkdir -p "$cfg_dir/etc" "$cfg_dir/bin"
            touch "$cfg_dir/etc/.keep" "$cfg_dir/bin/.keep"
        fi

        # Prepare temp workspace
        mkdir -p "$tmp"
        cp -r "$FILES/config/default/"* "$tmp/"
        local step_end=$(date +%s)
        if [[ "$TIMING_DEBUG" -eq 1 ]]; then
            echo "package $name: copy default took $((step_end - step_start))s" >&2
        fi
        step_start=$step_end

        cp -r "$FILES/config/$name/"* "$tmp/"
        step_end=$(date +%s)
        if [[ "$TIMING_DEBUG" -eq 1 ]]; then
            echo "package $name: copy server-specific took $((step_end - step_start))s" >&2
        fi
        step_start=$step_end

        # Process all files in parallel, limiting concurrency to 4
        find "$tmp" -type f ! -name ".keep" ! -name "*.jks" ! -name "*.swp" -print0 |
            xargs -0 -P 4 -I {} bash -c 'packageConfigurationFile "'"$name"'" "{}" false'
        step_end=$(date +%s)
        if [[ "$TIMING_DEBUG" -eq 1 ]]; then
            echo "package $name: file processing (find+xargs) took $((step_end - step_start))s" >&2
        fi
        step_start=$step_end

        # Archive (use pigz if available for faster compression)
        cd "$tmp" || return
        if command -v pigz >/dev/null 2>&1; then
            tar -cf - . | pigz > "$FILES/config/conf-$name.tar.gz"
        else
            tar -zcf "$FILES/config/conf-$name.tar.gz" .
        fi
        cd - >/dev/null || return
        step_end=$(date +%s)
        if [[ "$TIMING_DEBUG" -eq 1 ]]; then
            echo "package $name: archiving took $((step_end - step_start))s" >&2
        fi
        step_start=$step_end

        # rm -rf "$tmp"
        local total_end=$(date +%s)
        if [[ "$TIMING_DEBUG" -eq 1 ]]; then
            echo "package $name: TOTAL time $((total_end - total_start))s" >&2
        fi
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
