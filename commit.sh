#! /bin/bash

source config-dist.sh

CURRENT_USER=$(logname)

# Get the display name of the user
# params:
# $1 -- the section (if any)
# $2 -- the key
getCurrentUser() {

  section="git"
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
    echo 'NA'
    return
  fi
}

branch_name=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
user="$(getCurrentUser)"

read -p "[$branch_name] Commit: " msg

read -p "Push [Y/n]: " yn
yn=${yn:-'Y'}

if [[ "$user" == "NA" ]]; then
    git commit --author="$user" -m "$msg"
else
    git commit -m "$msg"
fi

case $yn in
    [Yy]* ) bash push.sh;;
esac

