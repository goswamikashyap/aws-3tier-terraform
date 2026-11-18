# PROD: highly available (NAT per AZ, Multi-AZ database, protected from deletion)
environment            = "prod"
vpc_cidr               = "10.20.0.0/16"
single_nat_gateway     = false
instance_type          = "t3.small"
asg_min_size           = 2
asg_max_size           = 6
asg_desired            = 2
db_instance_class      = "db.t3.small"
db_multi_az            = true
db_backup_retention    = 7
db_deletion_protection = true
db_skip_final_snapshot = false
