# A buffer-aware publisher stops writing to a legacy subscriber

This directory reproduces a defect in `rmw_fastrtps_cpp` 9.5.2-1 (ROS 2 Rolling). A publisher of a message with a `rosidl::Buffer` field stops writing to its main DataWriter after one buffer-aware subscriber has left. A legacy subscriber that joins later stays matched and receives nothing.

## Prerequisites

You need Linux on x86_64 and Nix with flakes enabled. The probes run on the loopback interface with UDP only, so you need no network setup. The first build compiles ROS 2 packages. Expect a long first build. Pass `--accept-flake-config` to use the public ROS binary cache named in `flake.nix`, or configure that cache yourself.

## Build

```
nix build --accept-flake-config .#after .#after-fixed .#before
```

`run.sh` runs the same builds first, so this step is optional.

| Output | Content |
|---|---|
| `after` | probes built against nix-ros-overlay Rolling at the pinned commit. It has `rmw_fastrtps_cpp` 9.5.2-1 with `rosidl::Buffer` support |
| `before` | probes built against the same distribution without `rosidl::Buffer`. It uses `rmw_fastrtps_cpp` 9.4.5-1, `rosidl` 5.1.3-1 and `rosidl_typesupport_fastrtps` 3.9.3-1 |
| `after-fixed` | `after` plus the two patches in `patches/` that make the publisher forget a subscriber that left |
| `after-debug`, `after-fixed-debug` | `after` and `after-fixed` plus a patch that prints the numbers `rmw_publish` compares, one line per publish |

`before` is the legacy side. It has no buffer support, so it never registers buffer information. It is not a released stack. It is the stack the same distribution had before the feature.

`before` needs one backport. The change [ros2/rmw_fastrtps#875](https://github.com/ros2/rmw_fastrtps/pull/875) landed in 9.4.6 together with the buffer feature. It changes the type object of every message with a sequence field. Without it, a 9.4.5 endpoint and a 9.5.x endpoint never match. The backport is `patches/rmw-fastrtps-shared-cpp-9.4.5-collection-flag-backport.patch`. It does not touch the publish path.

## Run

```
./run.sh
```

The script runs three rows. Each row runs 3 times. A run lasts about 65 seconds.

| Row | Sequence | Expected without the defect |
|---|---|---|
| `T0` | A legacy subscriber joins a publisher that never had a buffer-aware subscriber (control) | 75 messages |
| `T2` | A buffer-aware subscriber joins for 10 s and is killed with SIGKILL. After 30 s a legacy subscriber joins | 75 messages |
| `T2-fixed` | The sequence of `T2` against the publisher from `after-fixed` | 75 messages |

The publisher sends a 16000-byte `sensor_msgs/PointCloud2` at 5 Hz, so a 15 s window carries 75 messages. `run.sh` prints one line per run:

```
RESULT row=<row> run=<n> count=<messages the legacy subscriber received> matched=<largest live subscription count the publisher reported>
```

Use `RUNS=1 ./run.sh T2` to run one row once. The variables `DOMBASE` and `OUT` set the first ROS domain id and the log directory.

## Measured output

Output of `./run.sh` from a clean checkout of these files, on x86_64 Linux. The live count is the largest value the publisher reported while the legacy subscriber ran.

| Row | Messages received in 15 s, runs 1 to 3 | Live count |
|---|---|---|
| `T0` | 75, 75, 75 | 1, 1, 1 |
| `T2` | **0, 0, 0** | 1, 1, 1 |
| `T2-fixed` | 75, 67, 67 | 1, 1, 1 |

Row `T2` is the defect. The publisher still matches the legacy subscriber, and that subscriber receives nothing. A count of 67 means a few early messages were missing in that run. The cause is not investigated.

With `after-debug`, the publisher prints one line per publish. In row `T2` the live count falls to 0 after the buffer-aware subscriber is gone. The size of the list in `cpu_only_subscribers` stays 1. With `after-fixed-debug` the list size falls to 0 in the same second.

## Files

| File | Purpose |
|---|---|
| `flake.nix`, `flake.lock` | pin nix-ros-overlay and expose the outputs above |
| `nix/ab.nix` | builds the `after` and `before` stacks and applies the patches |
| `nix/probe.nix`, `probe/` | the publisher `pub_pc2` and the subscriber `sub_pc2` |
| `patches/` | the `before` backport, the fix and the debug print |
| `run.sh` | runs the rows |

## Not verified

| Item | State |
|---|---|
| Other transports than UDP | not run |
| Fast DDS shared memory and data sharing | not run, the probes force UDP |
| `rmw_fastrtps_dynamic_cpp` | not run |
| A graceful shutdown of the buffer-aware subscriber | not run, every run uses SIGKILL |
| Another host or another Nix version | not run |
| The released `ros:rolling` or Lyrical packages | not run, this flake builds from source |
| Subscribers that use a non-CPU buffer backend | not run, all runs are CPU only |
