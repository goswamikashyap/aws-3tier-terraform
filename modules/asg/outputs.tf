output "app_sg_id" {
  value = aws_security_group.app.id
}

output "instance_role_name" {
  value = aws_iam_role.instance.name
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}
