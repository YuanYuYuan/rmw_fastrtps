// Publishes a 16000-byte sensor_msgs/PointCloud2 at 5 Hz. Usage: pub_pc2 [topic]
// Once per second prints the publisher's own live subscription count:
//   PUBSTAT t=<unix seconds> matched=<n>
#include <chrono>
#include <cstdio>
#include <string>
#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/point_cloud2.hpp"
using namespace std::chrono_literals;
int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  std::string topic = argc > 1 ? argv[1] : "/churn";
  auto node = rclcpp::Node::make_shared("churn_pub");
  auto pub = node->create_publisher<sensor_msgs::msg::PointCloud2>(topic, 10);
  auto send = node->create_wall_timer(200ms, [&]() {
      sensor_msgs::msg::PointCloud2 m;
      m.height = 1; m.width = 1000; m.point_step = 16; m.row_step = 16000;
      m.data.resize(16000);
      pub->publish(m);
    });
  auto stat = node->create_wall_timer(1s, [&]() {
      double t = std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
      std::printf("PUBSTAT t=%.1f matched=%zu nodes=%zu\n", t, pub->get_subscription_count(), node->get_node_names().size());
      std::fflush(stdout);
    });
  rclcpp::spin(node);
  return 0;
}
