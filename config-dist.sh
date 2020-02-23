#! /bin/bash
if [ "$BASH" = "" ] ;then echo "Please run with bash"; exit 1; fi

# If you want to change this file (and you should) copy it to config.sh and make your changes
# there so git ignores your local copy.

echo

# Check to see if we are overriden - but only do it once
if [ -f "config.sh" ]
then
    echo "Taking configuration from local config.sh"
    source config.sh include
    return
    exit
else
    echo "Using defaults."
    echo "  If you want to override configuration settings, "
    echo "  copy config-dist.sh to config.sh and edit config.sh"
    echo
fi

# Settings
# --------

# Change GIT_REPO so that you checkout your forked repository
GIT_REPO=https://github.com/opencast/opencast.git

# GIT repo source folder - will pull and compile here
SRC="/usr/local/src/opencast"
TRACK4K_SRC="/usr/local/src/track4k/trackhd"
AUDIO_TRIM_SRC="/opt/trimpointdetector/"
OCR_SCR="/usr/local/src/tesseract"
EMPTY_VENUE_SRC="/opt/VAD-python"

# The folder where all the ansible scripts reside and the files folder structure
# probably the same folder as ${PWD}
YML="/usr/local/src/scripts"

# The folder where the deploy-dev.cfg / deploy-prod.cfg / deploy-staging.cfg files
# are kept for save keeping - they contain production passwords
DEPLOY_CFG_FOLDER="."

FILES=$YML"/files"
HOSTS_FOLDER=$YML"/hosts/"
LOG_DIR=$YML"/log"
TMP_DIR=$FILES"/tmp"
PATCHES_DIR=$YML"/patches"

BUILD_STATUS_FILE=$LOG_DIR"/build.status.log"
STATUS_FILE=$LOG_DIR"/current.log"

DIRNAME=$(dirname "$0")
PROGNAME=$(basename "$0")
CURRENT_DIR=${PWD}

mkdir -p $LOG_DIR
mkdir -p $TMP_DIR
mkdir -p $PATCHES_DIR

