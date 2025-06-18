output "ec2_global_ips" {
  value = ["${aws_instance.rhel_instance.*.public_ip}"]
}