# Alias definitions.
export LANGUAGE=en_ZA.UTF-8
export LANG=en_ZA.UTF-8
export LC_ALL=en_ZA.UTF-8

opclog=/opt/opencast/data/log/opencast.log

alias tailopc='tail -f $opclog'

useopc() {
  "$@" $opclog
}

dirUsed() {
    dir=$1
    if [ -z "$(ls -A $dir 2> /dev/null)" ]; then
        echo "0"
    else
        echo "1"
    fi
}

dirSizeAndTime() {
    dir=$1
    size=$(du -sh --time $dir 2>/dev/null | awk '{print $1} {print $2} {print $3}');
    if [ -z "$size" ]; then
        printf "0"
    else
        printf "%7s" $(echo $size | cut -d' ' -f 1)
        printf "   $(echo $size | cut -d' ' -f 2) $(echo $size | cut -d' ' -f 3)"
    fi
}

getFileTypes() {
  dir=$1
  types=$(find $dir -type f | perl -ne 'print $1 if m/\.([^.\/]+)$/' | sort -u | tr '\n' ' ' | sed -e 's/[[:space:]]*$//')
  printf "($types)"
}

checkForArchiveVariance () {
    dir=$1

    if [ -d "$dir" ]; then
        dir_first=$(find $dir -name track-* 2>/dev/null | head -n 1 | cut -d '/' -f 7)
        dir_next=$((dir_first + 1))

        #echo "$dir_first $dir_next"

        if [ -d "$dir/$dir_first" ] && [ -d "$dir/$dir_next" ]; then

            first_array=()
            while IFS= read -d $'\0' -r file ; do
                first_array=("${first_array[@]}" "$(basename $file)")
            done < <(find $dir/$dir_first -type f -name "track-*" -print0 2>/dev/null)
            #echo "${first_array[@]}"

            next_array=()
            while IFS= read -d $'\0' -r file ; do
                next_array=("${next_array[@]}" "$(basename $file)")
            done < <(find $dir/$dir_next -type f -name "track-*" -print0 2>/dev/null)
            #echo "${next_array[@]}"

            found=0
            for item in "${first_array[@]}"
            do
                #echo $item
                if [[ ! " ${next_array[@]} " =~ " ${item} " ]]; then
                    # whatever you want to do when arr doesn't contain value
                    ((found++))
                fi
            done
            printf "$found"
        else
            printf "0"
        fi
    else
        printf "0"
    fi
    printf "\n"
}

showmedia () {

  if [ "$1" != "" ]; then
    media=$1
    printf "Mediapackage_id: $media\n"
  else
    printf "Mediapackage_id: "
    read media
  fi

  # Workspace
  dir_shared_workspace="/data/opencast/archive/shared/workspace/mediapackage/$media"
  dir_shared_files="/data/opencast/archive/shared/files/mediapackage/$media"

  # Archive
  dir_archive="/data/opencast/archive/mh_default_org/$media"
  # Engage
  dir_engage="/data/opencast/distribution/downloads/mh_default_org/engage-player/$media"
  # Internal
  dir_internal="/data/opencast/distribution/downloads/mh_default_org/internal/$media"
  # Stream
  dir_stream="/data/opencast/distribution/streams/mh_default_org/engage-player/$media"

  shared_workspace=$(dirUsed "$dir_shared_workspace")
  shared_files=$(dirUsed "$dir_shared_files")
  archive=$(dirUsed "$dir_archive")
  engage=$(dirUsed "$dir_engage")
  internal=$(dirUsed "$dir_internal")
  stream=$(dirUsed "$dir_stream")

  if [ "$shared_workspace" -eq "1" ]; then
    tree $dir_shared_workspace
  fi

  if [ "$shared_files" -eq "1" ]; then
    tree $dir_shared_files
  fi

  if [ "$archive" -eq "1" ]; then
    tree $dir_archive
  fi

  if [ "$engage" -eq "1" ]; then
    tree $dir_engage
  fi

  if [ "$internal" -eq "1" ]; then
    tree $dir_internal
  fi

  if [ "$stream" -eq "1" ]; then
    tree $dir_stream
  fi

  # summary
  if [ "$archive" -eq "1" ]; then
    printf '%11s' "Archive:"
    dirSizeAndTime $dir_archive
    printf " "
    getFileTypes $dir_archive
    printf "   Var: "
    checkForArchiveVariance $dir_archive
  fi

  if [ "$engage" -eq "1" ]; then
    printf '%11s' "Engage:"
    dirSizeAndTime $dir_engage
    printf " "
    getFileTypes $dir_engage
    printf "\n"
  fi

  if [ "$internal" -eq "1" ]; then
    printf '%11s' "Internal:"
    dirSizeAndTime $dir_internal
    printf " "
    getFileTypes $dir_internal
    printf "\n"
  fi

  if [ "$stream" -eq "1" ]; then
    printf '%11s' "Stream: "
    dirSizeAndTime $dir_stream
    printf " "
    getFileTypes $dir_stream
    printf "\n"
  fi
}

rmworkmedia() {
  if [ "$1" != "" ]; then
    media=$1
    printf "Mediapackage_id: $media"
  else
    printf "Mediapackage_id: "
    read media
  fi

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
  version=$(find $src1 -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" -o -name "*.flac" | head -n 1 | cut -d '/' -f 7)

  if [ -z "$version" ]; then
    echo "Source folder does not exist !"
  else
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
