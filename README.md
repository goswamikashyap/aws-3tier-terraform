# AWS 3-Tier Infrastructure with Terraform

Production-style web stack on AWS, built entirely from code. One command creates
the network, load balancer, auto-scaling web servers and a private database, with
**identical dev and prod environments** (only sizes differ).

## What it does

```
                    Internet
                       |
                +--------------+       PUBLIC subnets (2 AZs)
                |     ALB      |  <--  SG: 80 from internet
                +--------------+
                       |
        +--------------+--------------+  PRIVATE app subnets (2 AZs)
        |  EC2 (ASG)        EC2 (ASG) |  SG: 80 only from ALB SG
        +--------------+--------------+  self-heal + scale on CPU, SSM access
                       |
                +--------------+       PRIVATE db subnets (no internet route)
                |  RDS MySQL   |  <--  SG: 3306 only from app SG
                +--------------+       password in Secrets Manager
```

| Tier | What | Security |
|------|------|----------|
| 1 - Web entry | Application Load Balancer | Only port 80 from the internet |
| 2 - App | EC2 Auto Scaling Group (nginx) | Private subnets, chained SG, **SSM instead of SSH**, **IMDSv2**, encrypted EBS |
| 3 - Data | RDS MySQL 8 | Private + isolated subnets, encrypted, **Secrets Manager** credentials |

## Tech used
Terraform (modules, remote state, multi-environment), AWS VPC / ALB / Auto Scaling /
EC2 / RDS / S3 / DynamoDB / IAM / SSM / Secrets Manager, GitHub Actions.

## Project structure
```
bootstrap/            one-time S3 bucket + DynamoDB lock table (remote state)
modules/vpc           VPC, 3 subnet tiers, NAT, route tables
modules/alb           load balancer, target group, listener, ALB security group
modules/asg           launch template, ASG, scaling policy, IAM role, app security group
modules/rds           MySQL, DB security group, Secrets Manager access policy
environments/dev      small/cheap config  (terraform.tfvars + backend.hcl)
environments/prod     HA config           (terraform.tfvars + backend.hcl)
.github/workflows     CI: terraform fmt + validate on every pull request
```

## Prerequisites
- An AWS account + an IAM user/role with admin-like access (for learning)
- [Terraform >= 1.5](https://developer.hashicorp.com/terraform/install)
- [AWS CLI v2](https://aws.amazon.com/cli/) configured: `aws configure`
- (Optional) Session Manager plugin, to open a shell on instances

## How to run (Windows CMD; same commands work in Linux/macOS)

### 1. Create the remote state backend (one time)
```bat
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=YOUR-UNIQUE-BUCKET-NAME"
cd ..
```

### 2. Point the environment at that bucket
Open `environments\dev\backend.hcl` and replace `REPLACE-WITH-YOUR-STATE-BUCKET`
with the bucket name from step 1 (do the same for `prod` later).

### 3. Deploy dev
```bat
cd environments\dev
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```
The full stack takes roughly 10-15 minutes (RDS and NAT gateway are the slow parts).
Time it yourself and put the real number on your resume.

### 4. Test it
`terraform apply` prints `app_url`. Open it in a browser and refresh a few times;
you will see different **instance IDs / AZs** as the ALB balances traffic.

### 5. See self-healing and auto scaling
```bat
:: Self-healing: terminate one instance, the ASG launches a replacement
aws ec2 terminate-instances --instance-ids i-xxxxxxxxxxxx --region ap-south-1

:: Open a shell WITHOUT SSH (SSM) and generate CPU load to trigger scale-out
aws ssm start-session --target i-xxxxxxxxxxxx --region ap-south-1
:: inside the shell:   yes > /dev/null &      (run it a few times)
:: watch:  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names three-tier-dev-asg
```

### 6. Read the DB credentials (shows Secrets Manager integration)
```bat
terraform output db_secret_arn
aws secretsmanager get-secret-value --secret-id <that-arn> --query SecretString --output text
```

### 7. Destroy everything (avoid charges!)
```bat
terraform destroy
```
Prod works the same way from `environments\prod` (deletion protection is on:
set `db_deletion_protection = false` and apply before destroying).

## CI/CD
`.github/workflows/terraform-ci.yml` runs `terraform fmt -check` and
`terraform validate` for dev and prod on every pull request. Run
`terraform fmt -recursive` locally before pushing so the check passes.

## Cost warning
NAT Gateways, ALB and RDS are billed hourly (roughly a few USD per day for dev).
Destroy the stack when you are done.

## Ideas to extend
HTTPS with ACM + Route 53, WAF on the ALB, RDS read replica, VPC endpoints for SSM
(removes NAT dependency), remote-state per team, `terraform plan` comment on PRs.
