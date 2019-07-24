#!/bin/bash

## Run the audio detection trim python script and it returns:
## (see https://github.com/cilt-uct/TrimPointDetector for explanation)
# audio_trim_duration=3300000
# audio_trim_autotrim=false
# audio_trim_ishour=true
# audio_trim_good_start=true
# audio_trim_good_end=true
# audio_trim_detected=24-3089-3252-3254
# audio_trim_segments=4000-3089000;3252000-3284000;
# audio_trim_segments_len=218
# audio_trim_segments_speech=109
# audio_trim_segments_speech_ms=2423000
# audio_trim_segments_notspeech=1
# audio_trim_segments_notspeech_ms=163000
# audio_trim_segments_notspeech_used=108
# audio_trim_segments_notspeech_used_ms=2405000
# audio_trim_threshold=3:5;90
# audio_trim_adjust=-20:30
# audio_trim_buffer=3:1
# audio_trim_good=300:600
# audio_trim_model=model_svmNoLapelSpeechModel
# audio_trim_lapel=false
# audio_trim_exec_time=67.93;138.718

# Original (2018-02-06): Corne Oosthuizen
# 2018-02-21: Corne Oosthuizen
#   Add additional arguments to process
#
# 2018-11-15: Corne Oosthuizen
#   Changed defaults

DEBUG_LOG="/opt/opencast/data/log/auto_trim.log"

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our variables:
media=""
output_file=""

# List of valid venues to use - remove temp [ m209 ]
venue_list=("hahn4" hoerilt1" "hoerilt2" "em4" "alex1a" "anatlt1" "beattielt" "cs302" "snapelt1" "cengsem" "menz12" "ls3a" "ls1a")

#--start-speech (seconds)    Threshold for speech at the start of the recording [sec] (default: 3)
start_speech=3

#--end-speech (seconds)      Threshold value for speech at the end of the recording [sec] (default: 5)
end_speech=5

#--non-speech (seconds)      Threshold value for non-speech segments [sec](default: 90)
non_speech=90

#--start-adjust (seconds)      Adjust the first speech segment start time by a number of seconds [sec] (default: -20)
start_adjust=-20

#--end-adjust (seconds)      Move the last speech segments end time longer by anumber of seconds [sec] (default: 30)
end_adjust=30

#--start-buffer (seconds)    If the start of the segment list is 0 then use thisbuffer [sec] (default: 3)
start_buffer=3

#--end-buffer (seconds)      If the last segment ends at the end of the wav fileadjust by this buffer [sec] (default: 1)
end_buffer=1

#--good-start (seconds)      Does the first segment start within this number ofseconds, if true then good start [sec] (default: 300 = 5min)
start_good=300

#--good-end (seconds)        Does the last segment end within this number of seconds, if true then good end [sec] (default: 600 = 10min)
end_good=600

#--venue        The venue that the recording took place in (default: none
venue="none"

# -d, --debug   If the flag exists then output debug file
DEBUG=false

usage() {

    if [ $# -ne 0 ]; then
        echo
        echo "One or more options cannot be processed: '$@' (See below)."
        echo
    fi

    echo "Usage: $PROGNAME -i /path/to/file-media-wav -o /path/to/output.txt"
    echo
    echo "Options:"
    echo
    echo "  -i wav, --input wav"
    echo "      The wav file to detect trimpoints from"
    echo
    echo "  -o txt, --output txt"
    echo "      The file to write the properties in"
    echo
    echo "  --venue"
    echo "      The venue for venue specific models for audio analysis"
    echo
    echo "  --start-speech (seconds)"
    echo "  --end-speech (seconds)"
    echo "  --non-speech (seconds)"
    echo "  --end-adjust (seconds)"
    echo "  --start-buffer (seconds)"
    echo "  --end-buffer (seconds)"
    echo "  --good-start (seconds)"
    echo "  --good-end (seconds)"
    echo
}

OPTIONS=o:i:dv:
LONGOPTIONS=debug,input:,output:,venue:,start-speech:,end-speech:,non-speech:,end-adjust:,start-buffer:,end-buffer:,good-start:,good-end:

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
        --start-speech)
            start_speech="$2"
            shift 2
            ;;
        --end-speech)
            end_speech="$2"
            shift 2
            ;;
        --non-speech)
            non_speech="$2"
            shift 2
            ;;
        --end-adjust)
            end_adjust="$2"
            shift 2
            ;;
        --start-buffer)
            start_buffer="$2"
            shift 2
            ;;
        --end-buffer)
            end_buffer="$2"
            shift 2
            ;;
        --good-start)
            start_good="$2"
            shift 2
            ;;
        --good-end)
            end_good="$2"
            shift 2
	    ;;
        -v|--venue)
            venue="$2"
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

$DEBUG && echo "-i $media -o $output_file \
--start-speech $start_speech --end-speech $end_speech --non-speech $non_speech \
--start-adjust $start_adjust --end-adjust $end_adjust \
--start-buffer $start_buffer --end-buffer $end_buffer \
--good-start $start_good --good-end $end_good --venue $venue" >> $DEBUG_LOG

cd /opt/trimpointdetector
python /opt/trimpointdetector/detectTrimPoints_woh.py -i $media -o $output_file \
    --start-speech $start_speech --end-speech $end_speech --non-speech $non_speech \
    --start-adjust $start_adjust --end-adjust $end_adjust \
    --start-buffer $start_buffer --end-buffer $end_buffer \
    --good-start $start_good --good-end $end_good --venue $venue

result=$?

# Add if the venue is valid to output file
if [[ " ${venue_list[@]} " =~ " ${venue} " ]]; then
   echo "audio_trim_valid_venue=true" >> $output_file;
   $DEBUG && echo "audio_trim_valid_venue=true" >> $DEBUG_LOG
else
   echo "audio_trim_valid_venue=false" >> $output_file;
   $DEBUG && echo "audio_trim_valid_venue=true" >> $DEBUG_LOG
fi

# for testing - force
$DEBUG && echo "timetabled=true" >> $output_file;

exit $result
