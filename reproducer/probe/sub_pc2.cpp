// Counts PointCloud2 messages for <seconds> and prints "RESULT count=<n>". Usage: sub_pc2 <seconds> [topic]
// seconds = 0 runs until killed.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/point_cloud2.hpp"
using namespace std::chrono_literals;
int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  double window = argc > 1 ? std::atof(argv[1]) : 0.0;
  std::string topic = argc > 2 ? argv[2] : "/churn";
  auto node = rclcpp::Node::make_shared("churn_sub");
  unsigned long count = 0;
  auto sub = node->create_subscription<sensor_msgs::msg::PointCloud2>(
    topic, 10, [&](sensor_msgs::msg::PointCloud2::ConstSharedPtr) {++count;});
  auto t0 = std::chrono::steady_clock::now();
  auto check = node->create_wall_timer(100ms, [&]() {
      if (window > 0 && std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count() >= window) {
        std::printf("RESULT count=%lu\n", count);
        std::fflush(stdout);
        rclcpp::shutdown();
      }
    });
  auto gstat = node->create_wall_timer(1s, [&]() {
      std::printf("SUBSTAT nodes=%zu pubs=%zu\n", node->get_node_names().size(), node->count_publishers(topic));
      std::fflush(stdout);
    });
  rclcpp::spin(node);
  return 0;
}
