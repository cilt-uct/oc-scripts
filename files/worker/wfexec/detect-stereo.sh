#!/bin/bash

## Run ffmpeg audio filter to chnage audio
## Mono > Mono
## Stereo > Left (Default) > Mono
##        > Right (Selected) > Mono

# Original (2019-01-25): Corne Oosthuizen

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our variables:
media=""
output_file=""
channel="left"

usage() {

    if [ $# -ne 0 ]; then
        echo
        echo "One or more options cannot be processed: '$@' (See below)."
        echo
    fi

    echo "Usage: $PROGNAME -i /path/to/audio.flac -o /path/to/audio-output.flac"
    echo
    echo "Options:"
    echo
    echo "  -i audio.flac, --input audio.flac"
    echo "      Input audio file"
    echo
    echo "  -o audio-output.flac, --output audio-output.flac"
    echo "      Output audio file"
    echo
    echo "  -c, --channel right/left"
    echo "      Select the left or the right channel (left:default)"
    echo
    echo "  -d, --debug"
    echo "      debug output"
    echo
}

OPTIONS=o:i:dc:
LONGOPTIONS=debug,input:,output:,channel:

# -temporarily store output to be able to check for errors
# -e.g. use “--options” parameter by name to activate quoting/enhanced mode
# -pass arguments only via   -- "$@"   to separate them correctly
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    # e.g. $? == 1
    #  then getopt has complained about wrong arguments to stdout
    usage $@
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -i|--input)
            media="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -c|--channel)
            channel="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

# handle non-option arguments
if [ -z "$media" ] && [ -z "$output_file" ]; then
    echo "Required: input and output file (-i /path/to/file-media-wav -o /path/to/output.txt)"
    exit 4
fi

if ffprobe $media 2>&1 | egrep 'stereo'; then
    $DEBUG && echo "-i $media -o $output_file stereo $channel"

    if [ "$channel" == "left" ]; then
        ffmpeg -i $media -af "pan=mono|c0=FL" $output_file
    else
        ffmpeg -i $media -af "pan=mono|c0=FR" $output_file
    fi
else
    $DEBUG && echo "-i $media -o $output_file mono"
    ffmpeg -i $media -acodec copy $output_file
fi
