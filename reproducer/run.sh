#!/usr/bin/env bash
# Runs the rows of the reproducer. Builds the probe closures first (nix build), then starts the ROS
# processes of each row on this machine. Usage: ./run.sh [ROW...]   (default: T0 T2 T2-fixed)
#
#   T0        control. A legacy subscriber joins a publisher that never had a buffer-aware subscriber.
#   T2        a buffer-aware subscriber joins for 10 s and is killed with SIGKILL. 30 s later a legacy subscriber joins.
#   T2-fixed  the same sequence, with the publisher built with the patches in patches/.
#
# Variables: RUNS (runs per row, default 3), DOMBASE (first ROS domain id, default 20), OUT (log directory).
#
# Each run prints one line:
#   RESULT row=<row> run=<n> count=<messages the legacy subscriber received in 15 s, 75 at most> matched=<largest live subscription count the publisher reported while the legacy subscriber ran>
# A run without a RESULT line from the subscriber, or without a PUBSTAT line in the window, prints count=not-captured and the script exits 2.
set -u
cd "$(dirname "$0")"
RUNS_PER_ROW="${RUNS:-3}"; DOMBASE="${DOMBASE:-20}"; OUT="${OUT:-$PWD/out}"
[ "$#" -gt 0 ] || set -- T0 T2 T2-fixed
mkdir -p "$OUT/runs"; : > "$OUT/results.txt"

path_of() { nix build --no-link --print-out-paths ".#$1" || { echo "nix build .#$1 failed" >&2; exit 2; }; }
echo "building the probe closures (the first run compiles; later runs are cached)" >&2
AFTER=$(path_of after); AFTER_FIXED=$(path_of after-fixed); BEFORE=$(path_of before)

env_file() { # store path -> file with AMENT_PREFIX_PATH and LD_LIBRARY_PATH of its ROS closure
  local f="$OUT/env-$(basename "$1").sh" am="" ld="" x
  for x in $(nix-store -qR "$1" | grep 'ros-rolling'); do am="$am:$x"; ld="$ld:$x/lib"; done
  { echo "export AMENT_PREFIX_PATH='${am#:}'"; echo "export LD_LIBRARY_PATH='${ld#:}'"; } > "$f"; echo "$f"
}

DOM=0; RUNDIR=""; LAST_PID=""
# launch <store path> <log> <kill-after-seconds> <exe> [args...]
launch() {
  local p=$1 log=$2 ka=$3 exe=$4; shift 4
  ( . "$(env_file "$p")"
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_DOMAIN_ID=$DOM FASTDDS_BUILTIN_TRANSPORTS=UDPv4 \
           ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST HOME=$RUNDIR ROS_LOG_DIR=$RUNDIR/rlog
    exec timeout -s KILL "$ka" "$p/lib/buffer_probe/$exe" "$@" ) > "$log" 2>&1 &
  LAST_PID=$!
}
count_of() { local c; c=$(grep -h '^RESULT count=' "$1" 2>/dev/null | tail -1 | sed 's/.*count=//'); echo "${c:-not-captured}"; }
matched_max() { awk -v a="$2" -v b="$3" '/^PUBSTAT/{split($2,t,"=");split($3,m,"=");if(t[2]>=a&&t[2]<=b){n++;if(m[2]+0>mx)mx=m[2]+0}} END{if(n>0)print mx+0; else print "not-captured"}' "$1"; }

# row <name> <publisher store path> <seconds before the legacy subscriber joins> <churn: 0|1>
row() {
  local name=$1 pubp=$2 wait=$3 churn=$4 run FAULT=0
  for run in $(seq 1 "$RUNS_PER_ROW"); do
    DOM=$((DOMBASE + $(wc -l < "$OUT/results.txt") + 1)); RUNDIR="$OUT/runs/$name-$run"; mkdir -p "$RUNDIR/rlog"
    launch "$pubp" "$RUNDIR/pub.log" 400 pub_pc2 /probe; local pubpid=$LAST_PID
    sleep 4
    if [ "$churn" = 1 ]; then launch "$AFTER" "$RUNDIR/buffer-aware.log" 10 sub_pc2 0 /probe; wait "$LAST_PID" 2>/dev/null
    else sleep 10; fi
    sleep "$wait"
    local t0 t1; t0=$(date +%s.%N)
    launch "$BEFORE" "$RUNDIR/legacy.log" 40 sub_pc2 15 /probe; wait "$LAST_PID"; t1=$(date +%s.%N)
    local c m; c=$(count_of "$RUNDIR/legacy.log"); m=$(matched_max "$RUNDIR/pub.log" "$t0" "$t1")
    echo "RESULT row=$name run=$run count=$c matched=$m" | tee -a "$OUT/results.txt"
    { [ "$c" = not-captured ] || [ "$m" = not-captured ]; } && FAULT=1
    kill -9 "$pubpid" 2>/dev/null; wait "$pubpid" 2>/dev/null
  done
  return $FAULT
}

rc=0
for r in "$@"; do
  case $r in
    T0)       row T0 "$AFTER" 30 0 || rc=2 ;;
    T2)       row T2 "$AFTER" 30 1 || rc=2 ;;
    T2-fixed) row T2-fixed "$AFTER_FIXED" 30 1 || rc=2 ;;
    *) echo "unknown row: $r" >&2; exit 2 ;;
  esac
done
exit $rc
