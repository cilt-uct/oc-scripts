#! /bin/bash

branch_name=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)

read -p "Branch [$branch_name]: " branch
branch=${branch:-$branch_name}

read -p "Github Username: " username

git push https://$username@github.com/cilt-uct/oc-scripts.git $branch

if [ $? -eq 0 ]; then
  bash get.sh
fi
