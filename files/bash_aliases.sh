# Alias definitions.
export LANGUAGE=en_ZA.UTF-8
export LANG=en_ZA.UTF-8
export LC_ALL=en_ZA.UTF-8

opclog=/opt/opencast/data/log/opencast.log

alias tailopc='tail -f $opclog'
alias pa='source .venv/bin/activate'
alias pd='deactivate'

useopc() {
  "$@" $opclog
}

# Convert bytes to human-readable
human_readable() {
    size=$1
    if (( size >= 1024*1024*1024 )); then
        printf "%.2f GB" "$(bc -l <<< "$size/1024/1024/1024")"
    elif (( size >= 1024*1024 )); then
        printf "%.2f MB" "$(bc -l <<< "$size/1024/1024")"
    elif (( size >= 1024 )); then
        printf "%.2f KB" "$(bc -l <<< "$size/1024")"
    else
        printf "%d B" "$size"
    fi
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
    size=$(du -B1 -s --time $dir 2>/dev/null | awk '{print $1} {print $2} {print $3}');
    if [ -z "$size" ]; then
        printf "0"
    else
        hl_size=$(human_readable "$(echo $size | cut -d' ' -f 1)")
        printf "%12s" "$hl_size"
        printf "   $(echo $size | cut -d' ' -f 2) $(echo $size | cut -d' ' -f 3)"
    fi
}

getDirHardLinks() {
    dir=$1

    # Unique inodes size (sum of file sizes, counting each inode only once)
    unique_size=$(find "$dir" -type f -printf "%i %s\n" | sort -u | awk '{sum+=$2} END{print sum}')

    # Count unique files
    folder_count=$(ls -1d "$dir"/*/ 2>/dev/null | wc -l)
    file_count=$(find "$dir" -type f -printf "%i\n" | sort -u | wc -l)

    track_0=$(find "$dir" -type f -name "track-0*" -printf "%i\n" | sort -u | wc -l)
    track_1=$(find "$dir" -type f -name "track-1*" -printf "%i\n" | sort -u | wc -l)
    track_2=$(find "$dir" -type f -name "track-2*" -printf "%i\n" | sort -u | wc -l)
    track_3=$(find "$dir" -type f -name "track-3*" -printf "%i\n" | sort -u | wc -l)
    other_media=$(find "$dir" -type f \
    \( -iname "*.mp4" -o \
       -iname "*.avi" -o \
       -iname "*.mkv" -o \
       -iname "*.mov" -o \
       -iname "*.mp3" -o \
       -iname "*.wav" -o \
       -iname "*.flac" -o \
       -iname "*.m4a" -o \
       -iname "*.aac" -o \
       -iname "*.ogg" -o \
       -iname "*.webm" -o \
       -iname "*.m4v" -o \
       -iname "*.mpeg" -o \
       -iname "*.mpg" -o \
       -iname "*.ts" -o \
       -iname "*.mts" \) \
    ! -name "track-*" \
    -printf "%i\n" | sort -u | wc -l)

    hl_size=$(human_readable $unique_size)
    printf "        HL:%12s   Files: %5d\n" "$hl_size" "$file_count"
    printf "            Folders:%4d\n" "$folder_count"
    printf "            track-0:%4d   1:%4d   2:%4d   3:%4d   x:%4d\n" "$track_0" "$track_1" "$track_2" "$track_3" "$other_media"
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
    skip_tree=false
    # Parse -s flag
    if [ "$1" = "-s" ]; then
        skip_tree=true
        shift
    fi

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
    # api
    dir_api="/data/opencast/distribution/downloads/mh_default_org/api/$media"

    shared_workspace=$(dirUsed "$dir_shared_workspace")
    shared_files=$(dirUsed "$dir_shared_files")
    archive=$(dirUsed "$dir_archive")
    engage=$(dirUsed "$dir_engage")
    internal=$(dirUsed "$dir_internal")
    stream=$(dirUsed "$dir_stream")
    api=$(dirUsed "$dir_api")

    # Helper to print folder path and subfolder count
    print_folder_and_count() {
        local folder="$1"
        if [ -d "$folder" ]; then
        local count=$(find "$folder" -mindepth 1 -type d 2>/dev/null | wc -l)
        echo "$folder (subfolders: $count)"
        fi
    }

    if $skip_tree; then
        [ "$shared_workspace" -eq "1" ] && print_folder_and_count "$dir_shared_workspace"
        [ "$shared_files" -eq "1" ] && print_folder_and_count "$dir_shared_files"
        [ "$archive" -eq "1" ] && print_folder_and_count "$dir_archive"
        [ "$engage" -eq "1" ] && print_folder_and_count "$dir_engage"
        [ "$internal" -eq "1" ] && print_folder_and_count "$dir_internal"
        [ "$stream" -eq "1" ] && print_folder_and_count "$dir_stream"
        [ "$api" -eq "1" ] && print_folder_and_count "$dir_api"

    else
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

        if [ "$api" -eq "1" ]; then
            tree $dir_api
        fi
    fi

    # summary output helper
    show_folder_summary() {
        local label="$1"
        local folder="$2"
        local show_hardlinks="$3" # true/false

        printf '%11s' "$label:"
        dirSizeAndTime "$folder"

        printf " "
        getFileTypes "$folder"

        if [ "$label" = "Archive" ]; then
            printf "   Var: "
            checkForArchiveVariance "$folder"
        fi

        if [ "$show_hardlinks" = true ]; then
            getDirHardLinks "$folder"
        else
            printf "\n"
        fi
    }

    printf "\nSummary:\n"

    if [ "$archive" -eq "1" ]; then
        show_folder_summary "Archive" "$dir_archive" true
    fi

    if [ "$engage" -eq "1" ]; then
        show_folder_summary "Engage" "$dir_engage" false
    fi

    if [ "$internal" -eq "1" ]; then
        show_folder_summary "Internal" "$dir_internal" false
    fi

    if [ "$stream" -eq "1" ]; then
        show_folder_summary "Stream" "$dir_stream" false
    fi

    if [ "$api" -eq "1" ]; then
        show_folder_summary "API" "$dir_api" false
    fi

    if [ "$shared_workspace" -eq "1" ]; then
        show_folder_summary "Workspace" "$dir_shared_workspace" false
    fi

    if [ "$shared_files" -eq "1" ]; then
        show_folder_summary "Files" "$dir_shared_files" false
    fi
}

rmworkmedia() {
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

  rm -rf $dir_shared_workspace
  rm -rf $dir_shared_files

  shared_workspace=$(dirUsed "$dir_shared_workspace")
  shared_files=$(dirUsed "$dir_shared_files")

  printf "  Out: $shared_workspace $shared_files\n"
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

mine() {
    # Get the original user, even if running with sudo
    local user="${SUDO_USER:-$USER}"

    # Case 1: filename provided as first argument
    local file="$1"

    # Case 2 and 3: no filename passed as argument
    if [ -z "$file" ]; then
        read -p "Enter filename (leave blank to chown current directory recursively): " file
    fi

    if [ -n "$file" ]; then
        # File provided or entered interactively
        if [ ! -e "$file" ]; then
            echo "Error: File '$file' does not exist."
            return 1
        fi
        sudo chown "$user" "$file"
        echo "Ownership of '$file' changed to '$user'."
    else
        # No filename provided or entered — change ownership of current directory recursively
        sudo chown -R "$user" .
        echo "Ownership of current directory and all subfolders changed to '$user'."
    fi
}

to_root() {
    # Always use root as the owner
    local user="root"

    # Case 1: filename provided as first argument
    local file="$1"

    # Case 2 and 3: no filename passed as argument
    if [ -z "$file" ]; then
        read -p "Enter filename (leave blank to chown current directory recursively): " file
    fi

    if [ -n "$file" ]; then
        # File provided or entered interactively
        if [ ! -e "$file" ]; then
            echo "Error: File '$file' does not exist."
            return 1
        fi
        sudo chown "$user" "$file"
        echo "Ownership of '$file' changed to '$user'."
    else
        # No filename provided or entered — change ownership of current directory recursively
        sudo chown -R "$user" .
        echo "Ownership of current directory and all subfolders changed to '$user'."
    fi
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
