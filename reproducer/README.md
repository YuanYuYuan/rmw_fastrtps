# A buffer-aware publisher stops writing to a legacy subscriber

This directory reproduces a defect in `rmw_fastrtps_cpp` 9.6.0-1 (ROS 2 Rolling). A publisher of a message with a `rosidl::Buffer` field stops writing to its main DataWriter after one buffer-aware subscriber has left. A legacy subscriber (one without buffer support) that joins later stays matched and receives nothing. The run builds the pull request fix and shows that the legacy subscriber receives every message with it.

## Requirements

Docker or Podman, Linux on x86_64, and network access to GitHub and the Ubuntu and ROS package servers. The probes run on the loopback interface with UDP only, so no network setup is needed. The build takes about 3 minutes and the run about 25 minutes.

## Build and run

```
docker build -t rmw-fastrtps-939 .
docker run --rm rmw-fastrtps-939
```

Run both commands in this directory. Replace `docker` with `podman` to use Podman. `docker run --rm rmw-fastrtps-939 T0 T2` runs only the rows named after the image. `docker run --rm -e RUNS=1 rmw-fastrtps-939` runs each row once.

## Output

One `RESULT` line per run, in this form:

```
RESULT row=<row> run=<n> count=<messages the legacy subscriber received in 15 s> matched=<largest live subscription count the publisher reported while it ran>
```

The output of the run command, with 5 runs per row:

```
RESULT row=T0 run=1 count=75 matched=1
RESULT row=T0 run=2 count=75 matched=1
RESULT row=T0 run=3 count=75 matched=1
RESULT row=T0 run=4 count=75 matched=1
RESULT row=T0 run=5 count=75 matched=1
RESULT row=T2 run=1 count=0 matched=1
RESULT row=T2 run=2 count=0 matched=1
RESULT row=T2 run=3 count=0 matched=1
RESULT row=T2 run=4 count=0 matched=1
RESULT row=T2 run=5 count=0 matched=1
RESULT row=T2-sigint run=1 count=0 matched=1
RESULT row=T2-sigint run=2 count=0 matched=1
RESULT row=T2-sigint run=3 count=0 matched=1
RESULT row=T2-sigint run=4 count=0 matched=1
RESULT row=T2-sigint run=5 count=0 matched=1
RESULT row=T2-fixed run=1 count=75 matched=1
RESULT row=T2-fixed run=2 count=75 matched=1
RESULT row=T2-fixed run=3 count=75 matched=1
RESULT row=T2-fixed run=4 count=75 matched=1
RESULT row=T2-fixed run=5 count=75 matched=1
RESULT row=T2-fixed-sigint run=1 count=75 matched=1
RESULT row=T2-fixed-sigint run=2 count=75 matched=1
RESULT row=T2-fixed-sigint run=3 count=75 matched=1
RESULT row=T2-fixed-sigint run=4 count=75 matched=1
RESULT row=T2-fixed-sigint run=5 count=75 matched=1
```

Every run has `count` equal to 75 or to 0, and `matched=1` in all 25 runs.

## Rows

The publisher sends a 16000-byte `sensor_msgs/PointCloud2` at 5 Hz, so a 15 s window carries 75 messages. All rows use the default QoS and one message type.

| Row | Sequence | Publisher |
|---|---|---|
| `T0` | A legacy subscriber joins 44 s after the publisher starts. No buffer-aware subscriber ever existed (control) | released packages |
| `T2` | A buffer-aware subscriber joins for 10 s and is killed with SIGKILL. 30 s later a legacy subscriber joins | released packages |
| `T2-sigint` | The sequence of `T2`, but the buffer-aware subscriber ends on SIGINT and shuts down normally | released packages |
| `T2-fixed` | The sequence of `T2` | built from the fix commit |
| `T2-fixed-sigint` | The sequence of `T2-sigint` | built from the fix commit |

The legacy subscriber is the probe `sub_pc2` built against a stack without `rosidl::Buffer`. The publisher is the probe `pub_pc2`.

## Stacks in the image

| Stack | Content |
|---|---|
| released | `docker.io/library/ros@sha256:4a258503925b89534e71ec3f3ec41248b8339e73477749eaf6b529ff202c6494` (`ros:rolling-ros-base`). It has `rmw_fastrtps_cpp` 9.6.0-1resolute.20260916.193506 and `rosidl_buffer` support. The `Dockerfile` pins the image by this digest |
| fix | `rmw_fastrtps_cpp` built from commit [ab677e3](https://github.com/YuanYuYuan/rmw_fastrtps/commit/ab677e36cd99fc7b04e109606f5be5f9e5dada4c) of the branch `fix/forget-buffer-subscribers-that-leave`, installed in front of the released packages |
| legacy | `rosidl` 5.1.3-1, `rosidl_typesupport_fastrtps` 3.9.3-1, `rmw_fastrtps` 9.4.5-1 and the other packages listed in `pins-before.txt`, built from release tarballs on top of the image. This stack has no `rosidl::Buffer` and never registers buffer information |

The legacy stack needs one backport. The change [ros2/rmw_fastrtps#875](https://github.com/ros2/rmw_fastrtps/pull/875) landed in 9.4.6 together with the buffer feature. It changes the type object of every message with a sequence field. Without it a 9.4.5 endpoint and a 9.5.x or later endpoint never match. The backport is `patches/rmw-fastrtps-shared-cpp-9.4.5-collection-flag-backport.patch`. It does not touch the publish path. The source archive of every pinned package is listed with its sha256 in the build output.

## Reading the result

`T0` must give 75. If it does not, the legacy and released stacks do not talk to each other in your setup, and the other rows say nothing. `T2` and `T2-sigint` give 0 when the defect is present: `matched` is 1, so the publisher still counts the legacy subscriber, and the subscriber receives nothing. A fixed publisher gives 75 in `T2-fixed` and `T2-fixed-sigint`. A line with `not-captured` means a probe printed nothing, and the script exits with status 2.

## Not verified

The runs use `rmw_fastrtps_cpp` 9.6.0-1 and the fix commit on Rolling, with CPU buffers, UDP on loopback, one Linux x86_64 machine and Podman.

| Item | Why it matters | How to verify |
|---|---|---|
| Docker | the commands are the same, but the runs used Podman | run the two commands with `docker` |
| the fix commit on its own base (21ae052) | the fix was built over the 9.6.0-1 packages, and the base of the commit is a later source tree | build the fix branch in a ROS workspace on `rolling` and run `T2-fixed` against it |
| counts below 75 in a fixed row | a count below 75 would mean the fix loses messages when a subscriber joins late | run the fixed rows with `RUNS=20` |
