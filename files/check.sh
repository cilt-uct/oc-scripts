#! /bin/bash

if [ "$BASH" = "" ] ;then echo "Please run with bash."; exit 1; fi

DEPLOY_DIR=/opt
PROGNAME=$(basename "$0")
CONFIG="$DEPLOY_DIR/check.cfg"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'
BOLD='\033[0;1m'
NC='\033[0m' # No Color

echo  "---------------"
printf "Server: ${BLUE}${BOLD}${HOSTNAME}${NC}\n\n"

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

echo "Java: "
java_path=$( get_ini_value "" "java_home" $CONFIG)
java=$( $java_path/bin/java -version 2>&1 | head -n 1)
if [ $? -eq 0 ]; then

  check=$( get_ini_value "" "java_version" $CONFIG)

  if grep -q $check <<<$java; then
    printf "${GREEN}${java}${NC}\n"
  else
    printf "${RED}${java}${NC}\n"
    echo $check
  fi

else
  printf "${RED}FAIL${NC}\n"
fi

mvn=$(mvn -version 2>/dev/null)
if [ $? -eq 0 ]; then
  echo
  echo "Maven: "
  echo $mvn
fi

ansible=$(ansible --version 2>/dev/null)
if [ $? -eq 0 ]; then
  echo
  echo "Ansible: "
  echo "$(ansible --version | head -n 1)"
fi


echo

echo "FFMpeg: "
ffmpeg_path=$( get_ini_value "" "ffmpeg_path" $CONFIG)
ffmpeg=$( $ffmpeg_path -version | grep -i "ffmpeg version")
if [ $? -eq 0 ]; then

  check=$( get_ini_value "" "ffmpeg_version" $CONFIG)

  if grep -q $check <<<$ffmpeg; then
    printf "${GREEN}${ffmpeg}${NC}\n"
  else
    printf "${RED}${ffmpeg}${NC}\n"
    echo $check
  fi

else
  printf "${RED}FAIL${NC}\n"
fi

echo

echo "Tesseract: "
tesseract_path=$( get_ini_value "" "tesseract_path" $CONFIG)
tesseract=$( $tesseract_path --version 2>&1)
if [ $? -eq 0 ]; then

  check=$( get_ini_value "" "tesseract_version" $CONFIG)

  if grep -q $check <<<$tesseract; then
    printf "${GREEN}${tesseract}${NC}\n"
  else
    printf "${RED}${tesseract}${NC}\n"
    echo $check
  fi

else
  printf "${RED}FAIL${NC}\n"
fi

echo

echo "Sox: "
sox_path=$( get_ini_value "" "sox_path" $CONFIG)
sox=$( $sox_path --version)
if [ $? -eq 0 ]; then

  check=$( get_ini_value "" "sox_version" $CONFIG)

  if grep -q $check <<<$sox; then
    printf "${GREEN}${sox}${NC}\n"
  else
    printf "${RED}${sox}${NC}\n"
    echo $check
  fi

else
  printf "${RED}FAIL${NC}\n"
fi

echo

echo "Hunspell: "
hunspell_path=$( get_ini_value "" "hunspell_path" $CONFIG)
hunspell=$( $hunspell_path --version | grep Version)
if [ -z "$hunspell" ]; then
  printf "${RED}FAIL${NC}\n"
else

  check=$( get_ini_value "" "hunspell_version" $CONFIG)

  if grep -q $check <<<$hunspell; then
    printf "${GREEN}${hunspell}${NC}\n"
  else
    printf "${RED}${hunspell}${NC}\n"
    echo $check
  fi
fi

echo
echo "cropvid: "
cropvid_path=$( get_ini_value "" "track4k_cropvid_path" $CONFIG)
cropvid=$($cropvid_path 2>&1 | grep build)
if [ -z "$cropvid" ]; then
  printf "${RED}FAIL${NC}\n"
else
  printf "${GREEN}${cropvid}${NC}\n"
fi

echo
echo "Track4K: "
track4k_path=$( get_ini_value "" "track4k_binary_path" $CONFIG)
track4k=$($track4k_path 2>&1 | grep build)
if [ -z "$track4k" ]; then
  printf "${RED}FAIL${NC}\n"
else
  printf "${GREEN}${track4k}${NC}\n"
fi

echo
echo "Python: "
python_path=$( get_ini_value "" "python_path" $CONFIG)
py=$($python_path --version 2>&1)
if [ $? -eq 0 ]; then

  check=$( get_ini_value "" "python_version" $CONFIG)

  if grep -q $check <<<$py; then
    printf "${GREEN}${py}${NC}\n"
  else
    printf "${RED}${py}${NC}\n"
    echo $check
  fi

  echo
  echo "pyAudioAnalysis:"
  py1=$($python_path -c 'import pkgutil; print("pyAudioAnalysis exists" if pkgutil.find_loader("pyAudioAnalysis") else "NO pyAudioAnalysis")' 2>&1 | grep exists)
  if [ -z "$py1" ]; then
    printf "${RED}FAIL${NC}\n"
  else
    printf "${GREEN}pyAudioAnalysis exists${NC}\n"
  fi

  echo
  echo "Trim Point Detector:"
  pytrimpoints_path=$( get_ini_value "" "pytrimpoints_path" $CONFIG)
  pytrimpoints=$($python_path $pytrimpoints_path --version 2>&1 | grep build)
  if [ -z "$pytrimpoints" ]; then
    printf "${RED}FAIL${NC}\n"
  else
    printf "${GREEN}${pytrimpoints}${NC}\n"
  fi

else
  printf "${RED}FAIL${NC}\n"
fi

echo
echo "Perl: "
perl "$DEPLOY_DIR/check.pl"

rm $CONFIG;
rm "$DEPLOY_DIR/$PROGNAME";
rm "$DEPLOY_DIR/check.pl";
