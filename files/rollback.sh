#!/bin/sh

USER="opencast"
DEPLOY_DIR=/opt
CONFIG='deploy.cfg'
CONFIG_FILES='deploy.tar.gz'
SERVER_NAME=$HOSTNAME
START_SERVICE=false # true

DIRNAME=$(dirname "$0")
PROGNAME=$(basename "$0")

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
  tmp_folder="$working-tmp"
  tmp_folder_real="$working_real-tmp"
  bak=$( get_ini_value general dir_backup)
  bak_real=$( get_ini_value server dir_backup_real)
  server_cfg="$( get_ini_value server server_url)"
  server_type="$( get_ini_value server assembly)"
  server_type_name="$( get_ini_value server assembly_display)"

  cd $opt
  echo
  echo "Starting to ROLLBACK Opencast Assembly"
  echo "    - for: $server_cfg"
  echo "    - type: $server_type_name"
  echo "    - to: $bak $working"

  # stop service (probably stopped already but this is to make sure)
  service opencast stop

  check_directory $bak $bak_real
  check_directory $tmp_folder $tmp_folder_real
  check_directory $working $working_real

  # Move backup folder to working folder
   mv $working/* $tmp_folder
   mv $bak/* $working
   mv $tmp_folder/* $bak


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

    $START_SERVICE && service opencast start

    echo

    echo "    Cleaning ..."
    rm -rf $tmp_folder
    rm -rf $tmp_folder_real
    rm deploy.cfg
    rm deploy.tar.gz
    rm ${PROGNAME};

  else

    # Configuration correct
    echo "    ERROR: server.urls do not match ($working/etc/custom.properties)."
  fi

  echo
  echo "Done."
  echo
}

check_directory() {

  dir=$1
  real=$2
  shift; shift

  if [ ! -d "$dir" ]; then

    # Directory does not exist - so create it
    if [ "$real" = "$dir" ]; then

        # Real directory
        mkdir $real
        chown -R $USER $real
    else

        # It should be a symlink
        if [ ! -d "$real" ]; then

          # so the real directory does not exist
          mkdir $real
          chown -R $USER $real
        fi

        ln -s $real $dir
        chown -R $USER $dir
    fi
  fi
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
  echo "Configuration file for rollback is missing :p"
  exit 1
fi

main