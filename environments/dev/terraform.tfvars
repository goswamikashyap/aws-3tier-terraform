# DEV: small and cheap
environment            = "dev"
vpc_cidr               = "10.10.0.0/16"
single_nat_gateway     = true
instance_type          = "t3.micro"
asg_min_size           = 1
asg_max_size           = 2
asg_desired            = 1
db_instance_class      = "db.t3.micro"
db_multi_az            = false
db_backup_retention    = 1
db_deletion_protection = false
db_skip_final_snapshot = true
