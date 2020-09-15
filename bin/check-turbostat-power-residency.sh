#!/bin/bash

#refer to https://01.org/blogs/qwang59/2020/linux-s0ix-troubleshooting
set -e
result="pass"
command -v turbostat || exit 1

declare -A stats_p=( [GFX%rc6]=0 [Pk%pc10]=7 [SYS%LPI]=8 )
declare -A turbostat=( [GFX%rc6]=0 [Pk%pc10]=0 [SYS%LPI]=0 )
declare -A avg_criteria

usage() {
cat << EOF
usage: $0 options [--folder <target-folder-for-turbostat-log>] [--stat <target-power-stat>]

This tool will run turbostat and check if the power state meet our requirement.
Most of operations are need root permission.
The generated turbostat log will be put in {target-folder-for-turbostat-log}/turbostat-{target-power-stat}.log"

    -h|--help Print this message
    --output-directory
              Sepcify the path of folder that you want to store turbostat logs. The default one is /tmp
    -f        Read external turbostat log instead of doing turbostat.; do not need root permission.

              Please get log by this command:
              \$turbostat --out your-log --show GFX%rc6,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10,SYS%LPI
              Then:
              \$$0 -f path-to-your-log

    --p_state Get p_state after which system power state, the valuse could be s2i, longidle or shortidle

              Usage:
                $0 --p_state  s2i ; # Enter s2i then get turbostat value

                $0 --p_state  {other_state} ; # You execute $0 during system in {other_state}.

    --stat    Check if stat matchs expected percentage.

              Usage: $0 --stat [stat:percentage]

              State could be GFX%rc6, Pk%pc10 or SYS%LPI
              e.g. $0 --stat Pk%pc10:60 --stat SYS%LPI:70
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
        --p_state)
            shift
            p_state="$1";
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
            fi
            ;;
        --stat)
            shift
            [ -n "${stats_p["$(cut -d':' -f1 <<<"$1")"]}" ] || (echo "[ERROR] illegle parameter $1" && usage)
            avg_criteria["$(cut -d':' -f1 <<<"$1")"]="$(cut -d':' -f2 <<<"$1")"
            #echo ${!avg_criteria[@]}
            #echo ${avg_criteria[@]}
            ;;
        *)
        usage
       esac
       shift
done

[ "${#avg_criteria[@]}" != "0" ] || avg_criteria=( [gfxrc6]=50 [pkg_pc10]=80 [s0ix]=70 )

[ -n "$session_folder" ] || session_folder="/tmp"

STAT_FILE="$session_folder/turbostat-$p_state.log"

if_root(){
   if [ "$(id -u)" != "0" ]; then
       >&2 echo "[ERROR]need root permission"
       usage
   fi
}
if [ "$p_state" == "s2i" ]; then
    if_root
    echo "[INFO] getting turbostat log. Please wait for 60s"
    turbostat --out "$STAT_FILE" --show GFX%rc6,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10,SYS%LPI rtcwake -m freeze -s 60
elif [ -n "$EX_FILE" ]; then
    cp "$EX_FILE" "$STAT_FILE"
else
    if_root
    echo "[INFO] getting turbostat log. Please wait for about 120s"
    # turbostat take 3-4 secs per iteration
    turbostat --num_iterations 30 --out "$STAT_FILE" --show GFX%rc6,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10,SYS%LPI
fi
while read -r -a line; do
    c=$((c+1));
    for i in "${!turbostat[@]}"; do
        turbostat[$i]=$(bc <<< "${turbostat[$i]}+${line[${stats_p[$i]}]}");
    done
done < <(grep -v "[a-zA-Z]" "$STAT_FILE")

for i in "${!avg_criteria[@]}"; do
    turbostat[$i]=$(bc <<< "${turbostat[$i]}/$c");
    echo "[INFO] checking if $i >= ${avg_criteria[$i]}%"
    if [ "$(bc <<< "${turbostat[$i]} >= ${avg_criteria[$i]}")" == "1" ]; then
        echo "Passed."
    else
        >&2 echo "Failed" "avg $i : ${turbostat[$i]} NOT >= ${avg_criteria[$i]} "
        result="failed"
    fi
done

if [ "$result" != "pass" ]; then
    echo "[ERROR] please refer to https://01.org/blogs/qwang59/2018/how-achieve-s0ix-states-linux and https://01.org/blogs/qwang59/2020/linux-s0ix-troubleshooting for debugging"
    exit 1
fi
