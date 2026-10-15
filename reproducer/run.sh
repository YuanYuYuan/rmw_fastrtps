#!/usr/bin/env bash
# run.sh [ROW...]   runs inside the image; rows: T0 T2 T2-sigint T2-fixed T2-fixed-sigint (default: all five)
#   T0        control. A legacy subscriber joins a publisher that never had a buffer-aware subscriber.
#   T2        a buffer-aware subscriber joins for 10 s and is killed with SIGKILL. 30 s later a legacy subscriber joins.
#   T2-sigint the sequence of T2, but the buffer-aware subscriber ends on SIGINT (graceful shutdown)
#   T2-fixed  the sequence of T2 against a publisher built from the fix commit
#   T2-fixed-sigint  the sequence of T2-sigint against that publisher
# Variables: RUNS (runs per row, default 5), DOMBASE (first ROS domain id, default 20), OUT (log directory).
# One line per run:
#   RESULT row=<row> run=<n> count=<messages the legacy subscriber received in 15 s, 75 at most> matched=<largest live subscription count the publisher reported while the legacy subscriber ran>
# A run without a RESULT line from the subscriber, or without a PUBSTAT line in the window, prints not-captured and the script exits 2.
set -u
RUNS_PER_ROW="${RUNS:-5}"; DOMBASE="${DOMBASE:-20}"; OUT="${OUT:-/out}"
[ "$#" -gt 0 ] || set -- T0 T2 T2-sigint T2-fixed T2-fixed-sigint
mkdir -p "$OUT/runs"; : > "$OUT/results.txt"
DOM=0; RUNDIR=""; LAST_PID=""
# launch <stack: after|before|fixed> <log> <kill-after-seconds> <exe> [args...]
launch() {
  local stack=$1 log=$2 ka=$3 exe=$4; shift 4
  ( set +u; . /opt/ros/rolling/setup.bash
    case $stack in
      after)  . /opt/after/setup.bash ;;
      before) . /opt/before/setup.bash ;;
      fixed)  . /opt/after/setup.bash; . /opt/after-fixed/setup.bash ;;
    esac
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_DOMAIN_ID=$DOM FASTDDS_BUILTIN_TRANSPORTS=UDPv4 \
           ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST HOME=$RUNDIR ROS_LOG_DIR=$RUNDIR/rlog
    exe_path=/opt/before/lib/buffer_probe/$exe; [ "$stack" = before ] || exe_path=/opt/after/lib/buffer_probe/$exe
    exec timeout -s "${SIG:-KILL}" -k 5 "$ka" "$exe_path" "$@" ) > "$log" 2>&1 &
  LAST_PID=$!
}
count_of() { local c; c=$(grep -h '^RESULT count=' "$1" 2>/dev/null | tail -1 | sed 's/.*count=//'); echo "${c:-not-captured}"; }
matched_max() { awk -v a="$2" -v b="$3" '/^PUBSTAT/{split($2,t,"=");split($3,m,"=");if(t[2]>=a&&t[2]<=b){n++;if(m[2]+0>mx)mx=m[2]+0}} END{if(n>0)print mx+0; else print "not-captured"}' "$1"; }
row() { # row <name> <publisher stack> <churn 0|1> <signal that ends the buffer-aware subscriber>
  local name=$1 pubstack=$2 churn=$3 sig=${4:-KILL} run FAULT=0
  for run in $(seq 1 "$RUNS_PER_ROW"); do
    DOM=$((DOMBASE + $(wc -l < "$OUT/results.txt") + 1)); RUNDIR="$OUT/runs/$name-$run"; mkdir -p "$RUNDIR/rlog"
    launch "$pubstack" "$RUNDIR/pub.log" 400 pub_pc2 /probe; local pubpid=$LAST_PID
    sleep 4
    if [ "$churn" = 1 ]; then SIG=$sig launch after "$RUNDIR/buffer-aware.log" 10 sub_pc2 0 /probe; wait "$LAST_PID" 2>/dev/null
    else sleep 10; fi
    sleep 30
    local t0 t1; t0=$(date +%s.%N)
    launch before "$RUNDIR/legacy.log" 40 sub_pc2 15 /probe; wait "$LAST_PID"; t1=$(date +%s.%N)
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
    T0) row T0 after 0 || rc=2 ;;
    T2) row T2 after 1 || rc=2 ;;
    T2-sigint) row T2-sigint after 1 INT || rc=2 ;;
    T2-fixed) row T2-fixed fixed 1 || rc=2 ;;
    T2-fixed-sigint) row T2-fixed-sigint fixed 1 INT || rc=2 ;;
    *) echo "unknown row: $r" >&2; exit 2 ;;
  esac
done
exit $rc
