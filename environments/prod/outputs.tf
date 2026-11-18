output "app_url" {
  description = "Open this in a browser after apply"
  value       = "http://${module.alb.alb_dns_name}"
}

output "asg_name" {
  value = module.asg.asg_name
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "db_secret_arn" {
  value = module.rds.db_secret_arn
}
