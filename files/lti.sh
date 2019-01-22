#!/bin/sh

USER="root"
DEPLOY_DIR='/opt'
CONFIG='lti.cfg'
CONFIG_FILES='lti.tar.gz'
SERVER_NAME=$HOSTNAME
#START_SERVICE=false # true

#DIRNAME=$(dirname "$0")
#PROGNAME=$(basename "$0")

# [general]
# dir_working = /opt
# dir_install = /opt/opencast
# dir_backup = /opt/opencast-bak
# dir_data = /data/opencast

# [server]
# assembly = adminpresentation
# assembly_display = Admin and Presentation
# server_url = http://mediadev.uct.ac.za
# dir_install_real = /data/opt/opencast
# dir_backup_real = /data/opt/opencast-bak

main() {

  opt=$( get_ini_value general dir_working )
  lti=$( get_ini_value general dir_lti )
  
  cd $opt

  echo "Starting to deploy Opencast LTI Static files:"

  check_directory $lti $lti

  [ "$(find -type f -name lti*.tar.gz -ls | wc -l)" -eq "1" ] && found_tar=true || found_tar=false

  if $found_tar; then
 
    printf "    Extracting $DEPLOY_DIR/$CONFIG_FILES as $USER"

    tar -zxf $DEPLOY_DIR/$CONFIG_FILES -C $lti/

    chown -R $USER:$USER $lti

    echo "    Cleaning..."
    rm lti.tar.gz
    rm lti.cfg
    rm lti.sh

    echo " Done."
  else

    printf "    Could not find deploy folder"

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

check_directory() {

  dir=$1
  real=$2
  shift; shift

  if [ ! -d "$dir" ]; then

    # Directory does not exist - so create it
    if [ "$real" = "$dir" ]; then

        # Real directory
        mkdir -p $real
        chown -R $USER $real
    else

        # It should be a symlink
        if [ ! -d "$real" ]; then

          # so the real directory does not exist
          mkdir $real
          chown -R $USER $real
        fi

        ln -s $real $bak
        chown -R $USER $bak
    fi
  fi
}

cd $DEPLOY_DIR

[ "$(find $DEPLOY_DIR -type f -name lti*.tar.gz -ls | wc -l)" -eq "1" ] && ERR_TAR=false || ERR_TAR=true
[ -f "$DEPLOY_DIR/$CONFIG" ] && ERR_CFG=false || ERR_CFG=true

if $ERR_TAR || $ERR_CFG; then

  echo
  $ERR_TAR && printf "LTI tar file does not exist"
  $ERR_TAR && $ERR_CFG && printf " AND c" || ( $ERR_TAR && echo "." || printf "C" )
  $ERR_CFG && echo "onfiguration file for deployment is missing :p"
  exit 1
fi

main
