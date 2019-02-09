# Alias definitions.

opclog=/opt/opencast/data/log/opencast.log

alias tailopc='tail -f $opclog'

useopc() {
  "$@" $opclog
}

showmedia () {
  printf "Mediapackage_id: "
  read media

  tree /data/opencast/archive/shared/workspace/mediapackage/$media
  tree /data/opencast/archive/shared/files/mediapackage/$media
  tree /data/opencast/archive/mh_default_org/$media
  tree /data/opencast/distribution/downloads/mh_default_org/engage-player/$media
  tree /data/opencast/distribution/downloads/mh_default_org/internal/$media
  tree /data/opencast/distribution/streams/mh_default_org/engage-player/$media
}

rmworkmedia() {
  printf "Mediapackage_id: "
  read media

  rm -rf /data/opencast/archive/shared/workspace/mediapackage/$media
  rm -rf /data/opencast/archive/shared/files/mediapackage/$media
}

movemedia () {
  from=$(pwd)
  setnew=false
  setnew=false
  new_default=$(date +"%y%m%d-%H%M-%s")

  ARGS=$(getopt -o ":n" -l ":new" -n "movemedia" -- "$@")
  eval set -- "$ARGS"
  while true; do
    case "$1" in
        -n|--new)
            setnew=true
            shift
            ;;
        --)
            shift
            break
            ;;
        # an option argument, continue
        *) ;;
    esac
  done

  printf "Mediapackage_id: "
  read media

  if $setnew; then
    printf "New id (default: $new_default): "
    read ni
    newid="$(echo -e "${ni}" | tr -d '[:space:]')"
  fi

  src1="/data/opencast/archive/mh_default_org/$media"
  version=$(find $src1 -name track-* | head -n 1 | cut -d '/' -f 7)
  src="/data/opencast/archive/mh_default_org/$media/$version"
  echo "Move $media [$src]"

  if [ -d "$src" ]; then

      dest="/data/opencast/archive/shared/qa/$(date +"%s")"
      mkdir -p $dest

      cp $src/* $dest

      if $setnew; then

          if [[ !  -z  $newid  ]]; then
            /data/opencast/fix_manifest.pl $dest $newid
          else
            /data/opencast/fix_manifest.pl $dest $new_default
          fi
      else
          /data/opencast/fix_manifest.pl $dest
      fi

      cd $dest
      zip - * | ssh opencast@mediadev.uct.ac.za 'cat > /data/opencast/qa/live/$(echo $media).zip; cp /data/opencast/qa/live/$(echo $media).zip /opt/opencast/data/inbox/in.zip'

      rm -rf $dest
      echo "Done."
  else

    echo "Source folder does not exist !"
  fi

  cd $from
}

opcprobe () {
  printf "Path: "
  read path

  type="video"
  ARGS=$(getopt -o ":va" -l ":video,audio" -n "opcprobe" -- "$@")
  eval set -- "$ARGS"
  while true; do
    case "$1" in
        -v|--video)
            type="video"
            shift
            ;;
        -a|--audio)
            type="audio"
            shift
            ;;
        --)
            shift
            break
            ;;
        # an option argument, continue
        *) ;;
    esac
  done

  ffprobe -show_packets $path | grep "codec_type=$type" | wc -l
}

opchelp () {

    echo "Commands:"
    echo
    echo "  \$opclog ($opclog)"
    echo "      Variable to access Openast log."
    echo
    echo "  tailopc"
    echo "      Alias for 'tail -f $opclog'."
    echo
    echo "  useopc"
    echo "      Uses the log file to do some operation."
    echo "      Usage: usopc grep 'ERR'"
    echo
    echo "  opchelp"
    echo "      Displays this message."
    echo
    echo "  opcprobe"
    echo "      Do a ffprobe -show_packets with a line count"
    echo "      Options: "
    echo "         -v, --video"
    echo "         Check for codec_type=video"
    echo "         -a, --audio"
    echo "         Check for codec_type=audio"
    echo
    echo "  showmedia"
    echo "      Displays the tree of the folders for the media package."
    echo
    echo "  movemedia"
    echo "      move media to mediadev inbox folder for import (should only be used on media\mediadev)."
    echo "      Options: "
    echo "         -n, --new"
    echo "         Define a new id for the media package."
    echo
    echo "  rmworkmedia"
    echo "      Remove the work folders for a media."
    echo
}

cd () {
  builtin cd $@
  gitcolorprompt
}

gitcolorprompt () {
  if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == "true" ]] ; then
    local gitorigin="`git config --get remote.origin.url`"
    if [[ $gitorigin == "http"* ]] ; then
      gitorigin="`git config --get remote.origin.url | awk -F '/' '{ print $4 \"→ \" $5}'`"
    else
      gitorigin="`git config --get remote.origin.url | awk -F ':' '{ print $2 }' | awk -F '/' '{ print $1 \"→ \" $2 }'`"
    fi

    local gitbranch='`git branch 2> /dev/null | grep -e ^* | sed -E  s/^\\\\\*\ \(.+\)$/\(\\\\\1\)\/`'
    local gitpath="`git rev-parse --show-prefix`"
    local colour1="\[\033[01;31m\]"
    local colour2="\[\033[01;34m\]"
    local colour3="\[\033[38;5;28m\]"
    local gitarrow=$'\u2192'
    local gitstar="☘"
    local usertype="$"
    if [[ $(whoami) == "root" ]] ; then
      usertype="#"
    fi
    local textcolour="\[\033[00m\]"
    export PS1="$colour1$gitorigin $colour2$gitbranch $colour3$gitstar $gitpath$textcolour$usertype "
    export gitbase="`git rev-parse --show-toplevel`"
  else
    export PS1='${debian_chroot:+($debian_chroot)}\[\033[38;5;28m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
  fi
}

gitcolorprompt
