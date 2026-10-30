# Three stacks in one image, each an overlay on the ros:rolling-ros-base packages in /opt/ros/rolling:
#   /opt/after        the probes, built against the released packages (rmw_fastrtps_cpp 9.6.0-1)
#   /opt/after-fixed  rmw_fastrtps_cpp built from source at the fix commit 9f7530797192f5f2726ccdfea021460ed2af6ccf
#   /opt/before       a complete stack without rosidl::Buffer: rosidl 5.1.3 and rmw_fastrtps 9.4.5 with one backport
ARG ROS_IMAGE=docker.io/library/ros@sha256:4a258503925b89534e71ec3f3ec41248b8339e73477749eaf6b529ff202c6494
FROM ${ROS_IMAGE} AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates patch build-essential cmake ninja-build python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY build.sh pins-before.txt pins-fixed.txt ./
COPY patches patches
COPY probe probe
RUN ./build.sh after -
RUN ./build.sh after-fixed pins-fixed.txt --packages-select rmw_fastrtps_cpp
RUN ./build.sh before pins-before.txt --packages-up-to buffer_probe

FROM ${ROS_IMAGE}
COPY --from=builder /opt/after /opt/after
COPY --from=builder /opt/after-fixed /opt/after-fixed
COPY --from=builder /opt/before /opt/before
COPY run.sh /run.sh
ENTRYPOINT ["/run.sh"]
