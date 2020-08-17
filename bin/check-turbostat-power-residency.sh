#!/bin/bash

#refer to https://01.org/blogs/qwang59/2020/linux-s0ix-troubleshooting
set -e
state="pass"
command -v turbostat || exit 1

declare -A stats_p=( [gfxrc6]=0 [pkg_pc10]=7 [s0ix]=8 )
declare -A turbostat=( [gfxrc6]=0 [pkg_pc10]=0 [s0ix]=0 )
declare -A avg_criteria

usage() {
cat << EOF
usage: $0 options [--folder {target-folder-for-turbostat-log}] [--stat {target-power-stat}]
    this tool will run turbostat and check if the power state meet our requirement.
    most of operations are need root permission.
    the generated turbostat log will be put in {target-folder-for-turbostat-log}/turbostat-{target-power-stat}.log"

    -h|--help print this message
    --s2i     get into s2i before run turbostat
    --folder  sepcify the path of folder that you want to store turbostat logs. The default one is /tmp
    -f        read external turbostat log instead of doing turbostat.; do not need root permission.
              please get log by this command:
              \$turbostat --out your-log --show GFX%rc6,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10,SYS%LPI
              then:
              \$$0 -f path-to-your-log
    --p_state get p_state after which system power state.
              usage:
                $0 --p_state  s2i ; # enter s2i then get turbostat value

                $0 --p_state  {other_state} ; # you execute $0 during system in {other_state}.
    --stat    check if stat matchs expected percentage.
              usage: $0 --stat [stat:percentage}

              state could be gfxrc6, pkg_pc10 or s0ix
              e.g. $0 --stat pkg_pc10:60 --stat s0ix:70
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
        state="failed"
    fi
done

if [ "$state" != "pass" ]; then
    echo "[ERROR] please refer to https://01.org/blogs/qwang59/2018/how-achieve-s0ix-states-linux and https://01.org/blogs/qwang59/2020/linux-s0ix-troubleshooting for debugging"
    exit 1
fi
