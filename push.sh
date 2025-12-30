#! /bin/bash

branch_name=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)

read -p "Branch [$branch_name]: " branch
branch=${branch:-$branch_name}

read -p "Github Username (not email): " username
read -p "Force push? (y/N): " force_push
force_flag=""
if [[ "$force_push" =~ ^[Yy]$ ]]; then
  force_flag="--force"
fi

git push $force_flag https://$username@github.com/cilt-uct/oc-scripts.git $branch

if [ $? -eq 0 ]; then
  bash get.sh
fi
