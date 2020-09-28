#!/bin/bash

#refer to https://01.org/blogs/qwang59/2020/linux-s0ix-troubleshooting
set -e
result="pass"
command -v turbostat || exit 1

TARGET_STATS="GFX%rc6,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10,SYS%LPI"
declare -A stats_p
declare -A avg_criteria
op_mode="short-idle"
custom_avg_criteria="true"
i=0
for s in ${TARGET_STATS//,/ }; do
    stats_p[$i]="$s"
    avg_criteria["$s"]=0
    i=$((i+1))
done

usage() {
cat << EOF
usage: $(basename "$0") options [--output-directory <target-folder-for-turbostat-log>] [--op-mode <expected-operation-mode-of-e-star>]

This tool will run turbostat and check if the power state meet our requirement.
Most of operations are need root permission.
The generated turbostat log will be put in <target-folder-for-turbostat-log>/turbostat-<expected-operation-mode-of-e-star>.log"

    -h|--help Print this message
    --output-directory
            Sepcify the path of folder that you want to store turbostat logs. The default one is /tmp
    -f      Read external turbostat log instead of doing turbostat.; do not need root permission.

            Please get log by this command:
            turbostat --out external-log --show GFX%rc6,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10,SYS%LPI
            Then:
              $(basename "$0") -f path-to-external-log

    --op-mode The expected operation mode defined by e-star spec. The valuse could be short-idle, long-idle or sleep-mode
            It will be appended to the file name of the generated turbostat log file. If value is sleep-mode, this
            script will call turbostat with rtcwake to put system to s2i mode.
            The default is short-idle.

            Usage:
              $(basename "$0") --op-mode  sleep-mode ; # Enter s2i then get turbostat value

              $(basename "$0") --op-mode  long-idle ; # You execute $(basename "$0") during system in long-idle.

    --stat  Check if stat matchs expected percentage.

            Usage: $(basename "$0") --stat [stat:percentage]

            State could be GFX%rc6, Pk%pc10 or SYS%LPI
            e.g. $(basename "$0") --stat Pk%pc10:60 --stat SYS%LPI:70
EOF
exit 1
}

while [ $# -gt 0 ]
do
    case "$1" in
        -h | --help)
            usage 0
            exit 0
            ;;
        --op-mode)
            shift
            op_mode="$1";
            ;;
        --folder)
            shift
            [ -d "$1" ] || (echo "[ERROR] not exists folder $1" && usage)
            session_folder=$1;
            ;;
        -f)
            shift
            if [ -f "$1" ]; then
                EX_FILE="$1";
	    else
		echo"[ERROR] $1 is not there."
		usage
            fi
            ;;
        --stat)
            shift
            [ -z "${TARGET_STATS##*${1%%:*}*}" ] || (echo "[ERROR] illegle parameter $1" && usage)
            avg_criteria["${1%%:*}"]="${1##*:}"
	    custom_avg_criteria="true"
            ;;
        *)
        usage
       esac
       shift
done

if [ "$custom_avg_criteria" != "true" ]; then
    avg_criteria["GFX%rc6"]=50
    avg_criteria["Pk%pc10"]=80
    avg_criteria["SYS%LPI"]=70
fi

[ -n "$session_folder" ] || session_folder="/tmp"

STAT_FILE="$session_folder/turbostat-$op_mode.log"

require_root(){
   if [ "$(id -u)" != "0" ]; then
       >&2 echo "[ERROR]need root permission"
       usage
   fi
}

if [ -n "$EX_FILE" ]; then
    cp "$EX_FILE" "$STAT_FILE"
elif [ "$op_mode" == "sleep-mode" ]; then
    require_root
    echo "[INFO] getting turbostat log. Please wait for 60s"
    turbostat --out "$STAT_FILE" --show $TARGET_STATS rtcwake -m freeze -s 60
else
    require_root
    echo "[INFO] getting turbostat log. Please wait for about 120s"
    # turbostat take 3-4 secs per iteration
    turbostat --num_iterations 30 --out "$STAT_FILE" --show $TARGET_STATS
fi
i=0
while read -r avg; do
    if [ "${avg_criteria[${stats_p[$i]}]}" != "0" ]; then
        echo "[INFO] checking if ${stats_p[$i]}($avg%) >= ${avg_criteria[${stats_p[$i]}]}%"
        if [ "$(bc <<< "$avg >= ${avg_criteria[${stats_p[$i]}]}")" == "1" ]; then
            echo "Passed."
        else
            >&2 echo "Failed" "avg $i : $avg NOT >= ${avg_criteria[${stats_p[$i]}]} "
        fi
    fi
    i=$((i+1));
done< <(grep -v "[a-zA-Z]" "$STAT_FILE" | awk '
BEGIN { max = 0 }
{
    if (NF > max) max = NF;
    for (i = 1; i <= NF; i++)
    {
        a[i] = a[i] + $i;
    }
}
END {
    for (i = 1; i <= max; i++)
    {
        if (a[i] > 1 ) print a[i] / NR;
        else print 0
    }
}
')

if [ "$result" != "pass" ]; then
    echo "[ERROR] please refer to https://01.org/blogs/qwang59/2018/how-achieve-s0ix-states-linux and https://01.org/blogs/qwang59/2020/linux-s0ix-troubleshooting for debugging"
    exit 1
fi
