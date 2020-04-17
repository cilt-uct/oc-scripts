#!/bin/sh

USER="opencast"
DEPLOY_DIR=/opt
CONFIG='deploy.cfg'
CONFIG_FILES='deploy.tar.gz'
SERVER_NAME=$HOSTNAME
START_SERVICE=false # true

DIRNAME=$(dirname "$0")
PROGNAME=$(basename "$0")

CLEANUP=true

# [general]
# dir_working = /opt
# dir_install = /opt/opencast
# dir_backup = /opt/opencast-bak
# dir_data = /data/opencast

# [server]
# assembly = adminpresentation
# assembly_display = Admin and Presentation
# server_url = http://[local machine name].uct.ac.za
# dir_install_real = /opt/opencast
# dir_backup_real = /opt/opencast-bak

main() {

  opt=$( get_ini_value general dir_working)
  data=$( get_ini_value general dir_data)
  working=$( get_ini_value general dir_install)
  working_real=$( get_ini_value server dir_install_real)
  bak=$( get_ini_value general dir_backup)
  bak_real=$( get_ini_value server dir_backup_real)
  server_cfg="$( get_ini_value server server_url)"
  server_type="$( get_ini_value server assembly)"
  server_type_name="$( get_ini_value server assembly_display)"

  cd $opt
  echo
  echo "Starting to deploy Opencast Assembly"
  echo "    - for: $server_cfg"
  echo "    - type: $server_type_name"
  echo "    - to: $working"
  echo

  if [ -f "$DEPLOY_DIR/$CONFIG_FILES" ]; then

    printf "    Extracting Config / Encoding Profiles ..."
    tar -pzxf $DEPLOY_DIR/$CONFIG_FILES -C $working/

    # Move some workflows back - used by default for some of the processes.
    cp $working/etc/workflows-default/attach-watson-transcripts.xml $working/etc/workflows/attach-watson-transcripts.xml
    cp $working/etc/workflows-default/cleanup-publish-placeholder.xml $working/etc/workflows/cleanup-publish-placeholder.xml
    cp $working/etc/workflows-default/delete.xml $working/etc/workflows/delete.xml
    cp $working/etc/workflows-default/import.xml $working/etc/workflows/import.xml
    cp $working/etc/workflows-default/google-speech-attach-transcripts.xml $working/etc/workflows/google-speech-attach-transcripts.xml
    cp $working/etc/workflows-default/google-speech-start-transcription.xml $working/etc/workflows/google-speech-start-transcription.xml
    #cp $working/etc/workflows-default/nibity-start-transcription.xml $working/etc/workflows/nibity-start-transcription.xml
    cp $working/etc/workflows-default/partial-error.xml $working/etc/workflows/partial-error.xml
    cp $working/etc/workflows-default/partial-retract.xml $working/etc/workflows/partial-retract.xml
    cp $working/etc/workflows-default/partial-title-slide.xml $working/etc/workflows/partial-title-slide.xml
    cp $working/etc/workflows-default/publish-uploaded-assets.xml $working/etc/workflows/publish-uploaded-assets.xml
    cp $working/etc/workflows-default/offload.xml $working/etc/workflows/offload.xml
    cp $working/etc/workflows-default/republish-metadata.xml $working/etc/workflows/republish-metadata.xml
    cp $working/etc/workflows-default/restore.xml $working/etc/workflows/restore.xml
    cp $working/etc/workflows-default/retract.xml $working/etc/workflows/retract.xml
    cp $working/etc/workflows-default/retry-watson-transcripts.xml $working/etc/workflows/retry-watson-transcripts.xml
    cp $working/etc/workflows-default/partial-preview.xml $working/etc/workflows/partial-preview.xml

    echo " Done."
  else

    echo
    echo "    WARN: Configuration file ($DEPLOY_DIR/$CONFIG_FILES) not extracted ($working/)."
  fi

  # create and restore directories and ownership
  if [ ! -d "$data/local/" ]; then
    mkdir -p "$data/local/"
    chown -R opencast:opencast "$data/local/"
    if [ -d "$data/local/mysql" ]; then
      chown -R mysql:mysql "$data/local/mysql"
    fi
  fi

  chown -R opencast:opencast $working_real/
  chmod g+w -R $working_real/

  server_etc=$(awk '/org.opencastproject.server.url=http/ && /uct.ac/' $working/etc/custom.properties | cut -d "=" -f2)

  echo
  echo "    Config:"
  echo "        $server_etc"
  echo "        $server_cfg"
  echo

  if [ "$server_etc" = "$server_cfg" ]; then

    # Configuration correct
    echo "    SUCCESS: Configuration is correct."
    echo
    $CLEANUP && echo "    Cleaning ..."
    $CLEANUP && rm $CONFIG
    $CLEANUP && rm $CONFIG_FILES
    $CLEANUP && rm ${PROGNAME};

  else

    # Configuration correct
    echo "    ERROR: server.urls do not match ($working/etc/custom.properties)."
  fi

  echo
  echo "Done."
  echo
}

# search a list of ini_files for the desired id, returning the first match
# w/o regard for sections so it also works for setup.py files.
# Strips enclosing white space and quotes and trailing commas
# params:
# $1 -- the section (if any)
# $2 -- the key
get_ini_value() {

  section=$1
  key=$2
  shift; shift

  value=$(
    if [ -n "$section" ]; then
      sed -n "/^\[$section\]/, /^\[/p" $DEPLOY_DIR/$CONFIG
    else
      cat $DEPLOY_DIR/$CONFIG
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

cd $DEPLOY_DIR

[ -f "$DEPLOY_DIR/$CONFIG" ] && ERR_CFG=false || ERR_CFG=true

if $ERR_CFG; then

  echo
  $ERR_CFG && echo "Configuration files are missing :p"
  exit 1
fi

main
