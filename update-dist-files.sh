#! /bin/bash
if [ "$BASH" = "" ] ;then echo "Please run with bash"; exit 1; fi

source config-dist.sh

# internal configuration
CONFIG_DIR="config"
SRC_VERSION=$(xmlstarlet sel -t -v "/_:project/_:version" $SRC/pom.xml)
DEPLOY_TYPE="dev"
HOSTS_FILE=$HOSTS_FOLDER"dev"
CURRENT_USER=$(logname)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# search a list of ini_files for the desired id, returning the first match
# w/o regard for sections so it also works for setup.py files.
# Strips enclosing white space and quotes and trailing commas
# params:
# $1 -- the section (if any)
# $2 -- the key
# $3 -- the config file
get_ini_value() {

  section=$1
  key=$2
  file=$3
  shift; shift

  value=$(
    if [ -n "$section" ]; then
      sed -n "/^\[$section\]/, /^\[/p" $file
    else
      cat $file
    fi |

    egrep "^ *\b$key\b *=" |

    head -1 | cut -f2 -d'=' |
    sed 's/^[ "'']*//g' |
    sed 's/[ ",'']*$//g' )

  if [ -n "$value" ]; then
    echo $value
    return
  fi
}

get_downloader() {
    if command -v wget &> /dev/null; then
        echo "wget"
    elif command -v curl &> /dev/null; then
        echo "curl"
    else
        echo -e "${RED}Error: Neither wget nor curl is installed${NC}" >&2
        exit 1
    fi
}

# Function to download file with progress
download_file() {
    local url="$1"
    local output="$2"
    local downloader=$(get_downloader)

    echo -e "${YELLOW}Downloading from: $url${NC}"

    if [[ "$downloader" == "wget" ]]; then
        wget --show-progress -O "$output" "$url"
    else
        curl -L --progress-bar -o "$output" "$url"
    fi

    if [[ $? -eq 0 ]] && [[ -f "$output" ]]; then
        echo -e "${GREEN}Download completed successfully${NC}"
        return 0
    else
        echo -e "${RED}Download failed${NC}" >&2
        return 1
    fi
}

# Function to download with progress
safe_download() {
    local url="$1"
    local output="$2" # final filename
    local output_full="${output}.original" #original downloaded file before flattening and renaming
    local temp_output="${output}.tmp"
    local expected_sha256="$3"

    echo -e "Downloading ${url}"

    # Check if output already exists and matches SHA256
    if [[ -f "$output_full" ]]; then
        echo -e "File already exists, checking integrity..."
        if echo "$expected_sha256  $output_full" | sha256sum -c --status 2>/dev/null; then
            echo -e "${GREEN}Existing file matches SHA256, skipping download${NC}"
            return 0
        else
            echo -e "${YELLOW}Existing file corrupted or mismatched, re-downloading...${NC}"
            rm -f "$output_full"
        fi
    fi

    # Check available disk space (estimate ~50MB for FFmpeg)
    local required_kb=100000  # ~100MB buffer
    local available_kb=$(df "$(dirname "$output")" | awk 'NR==2 {print $4}')
    if [[ "${available_kb:-0}" -lt "$required_kb" ]]; then
        echo -e "${RED}Error: Insufficient disk space. Required: ${required_kb}KB${NC}" >&2
        return 1
    fi

    # Download to temp file
    if command -v wget &> /dev/null; then
        wget --quiet --show-progress -O "$temp_output" "$url" 2>&1
    elif command -v curl &> /dev/null; then
        curl -L --silent --progress-bar -o "$temp_output" "$url" 2>&1
    else
        echo -e "${RED}Error: Neither wget nor curl is installed${NC}" >&2
        return 1
    fi

    # Verify download succeeded
    if [[ ! -f "$temp_output" ]] || [[ ! -s "$temp_output" ]]; then
        echo -e "${RED}Error: Download failed or file is empty${NC}" >&2
        rm -f "$temp_output"
        return 1
    fi

    # Verify SHA256 checksum
    echo -e "${YELLOW}Verifying SHA256 checksum...${NC}"
    if echo "$expected_sha256  $temp_output" | sha256sum -c --status; then
        echo -e "${GREEN}SHA256 verification passed${NC}"
        # Atomic rename
        mv "$temp_output" "$output_full"

        echo -e "${YELLOW}Repackaging downloaded archive...${NC}"
        # Get the top directory name
        TOP_DIR=$(tar -tf "$output_full" | head -1 | sed 's|/.*||')

        # Create temp directory
        mkdir -p /tmp/ffmpeg_extract

        # Extract while stripping the top directory
        tar -xf "$output_full" -C /tmp/ffmpeg_extract --strip-components=1

        # Repackage from the temp directory
        tar -C /tmp/ffmpeg_extract -cJf "${output}" .

        # Clean up
        rm -rf /tmp/ffmpeg_extract

        return 0
    else
        echo -e "${RED}SHA256 verification failed!${NC}" >&2
        echo "Expected: $expected_sha256" >&2
        local actual_sha=$(sha256sum "$temp_output" | cut -d' ' -f1)
        echo "Actual:   $actual_sha" >&2
        rm -f "$temp_output"
        return 1
    fi
}

main() {
    local CONFIG="$1"

    printf "Actions [$DEPLOY_TYPE]($SRC_VERSION): "
    echo "Updating distribution files for $DEPLOY_TYPE deployment with source version $SRC_VERSION"

     # Read values
    local FFMPEG_VERSION=$( get_ini_value "" "tmpl_deploy_dist_ffmpeg_version" "$CONFIG")
    local FFMPEG_SHA=$( get_ini_value "" "tmpl_deploy_dist_ffmpeg_sha" "$CONFIG")

    # Check each required value
    [[ -z "$FFMPEG_VERSION" ]] && missing_values+=("tmpl_deploy_dist_ffmpeg_version")
    [[ -z "$FFMPEG_SHA" ]] && missing_values+=("tmpl_deploy_dist_ffmpeg_sha")

    # Report missing values
    if [[ ${#missing_values[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing required config values:${NC}" >&2
        printf '  - %s\n' "${missing_values[@]}" >&2
        return 1
    fi

    FFMPEG_FILE="ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION}.tar.xz"
    DOWNLOAD_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${FFMPEG_FILE}"

    if safe_download "$DOWNLOAD_URL" "$DISTFILES/$FFMPEG_FILE" "$FFMPEG_SHA"; then
        cp "$DISTFILES/$FFMPEG_FILE" "$DISTFILES/ffmpeg-${DEPLOY_TYPE}.tar.xz"
        echo -e "${GREEN}Download complete and verified!${NC}"
    else
        echo -e "${RED}Download failed!${NC}" >&2
        exit 1
    fi
}

usage() {

    if [ $# -ne 0 ]; then
        echo
        echo "One or more options cannot be processed: '$@' (See below)."
        echo
    fi

    echo "Usage: $PROGNAME [options] (Deploy type: dev, production | prod, staging)"
    echo
    echo "  Example: $PROGNAME prod"
    echo "           Fetch dist files for production deployment."
    echo
    echo "Options:"
    echo
    echo "  -h, --help"
    echo "      This help text."
    echo
    echo "  --"
    echo "      Do not interpret any more arguments as options."
    echo
}

## Start parsing arguments ##
## TODO: Add optional parameters to
##       - build: 0 (default) Do All, 1 build src, 2 build cfg
#        - clean: 0 (default) Do All, 1 clean only db, 2 clean shared+archive+distribution
ARGS=$(getopt -o ":h" -l ":help" -n "$PROGNAME" -- "$@")

MORE=true
eval set -- "$ARGS"
while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
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

# Write out the required files for this build type (deploy-[type].cfg) to the files for:
# - build and package for each server
# - deploy with ansible script

cd $YML

cp $FILES/build-all.template files/config/build-default.cfg
cp $FILES/dbservers.template group_vars/dbservers
cp $FILES/all.template group_vars/all
cp $FILES/shell_variable.template $FILES/shell_variable.sh

writeConfiguration "$DEPLOY_CFG_FOLDER/deploy-$DEPLOY_TYPE.cfg" $FILES/config/build-default.cfg
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
ACTIVE_SERVER_LIST=($(grep -vE '^[[:space:]]*(#|$|\[.*\]|.*=)' "$HOSTS_FILE" | cut -d. -f1 | sort -u))

cd $CURRENT_DIR

# run main code
main "$DEPLOY_CFG_FOLDER/deploy-$DEPLOY_TYPE.cfg"

# Post clean-up of temporary files
rm -rf $TMP_DIR/*
find "$FILES/config" -type f -name "*.tar.gz" -delete
rm $FILES/config/build-default.cfg
rm $FILES/shell_variable.sh
