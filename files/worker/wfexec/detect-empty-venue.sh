#!/bin/bash

# Initialize our variables:
media=""
output_file=""

# -d, --debug   If the flag exists then output debug file
DEBUG=false

OPTIONS=o:i:d
LONGOPTIONS=debug,input:,output:

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

python3 /opt/VAD-python/detectVoiceInWave.py -i $media -o $output_file
