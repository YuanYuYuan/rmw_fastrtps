{ lib, buildRosPackage, ament-cmake, rclcpp, std-msgs, sensor-msgs, rmw-implementation, rmw-fastrtps-cpp }:
buildRosPackage {
  pname = "ros-rolling-buffer-probe";
  version = "0.0.1";
  src = ../probe;
  buildType = "ament_cmake";
  buildInputs = [ ament-cmake rclcpp std-msgs sensor-msgs ];
  propagatedBuildInputs = [ rclcpp std-msgs sensor-msgs rmw-implementation rmw-fastrtps-cpp ];
  nativeBuildInputs = [ ament-cmake ];
  meta = {
    description = "Publisher and subscriber probes for a buffer-aware rmw_fastrtps_cpp publisher";
    license = with lib.licenses; [ asl20 ];
  };
}
