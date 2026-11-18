#### AWS 3-Tier Infrastructure with Terraform

 

Production-style, multi-AZ 3-tier web architecture on AWS provisioned entirely with modular Terraform. A single deployment creates an isolated VPC network, an internet-facing Application Load Balancer (ALB), a self-healing EC2 Auto Scaling Group (ASG), and an encrypted private RDS MySQL database—with identical **dev** and **prod** codebases separated only by configuration variables. 

#### Architecture & Security Design

                          Internet
                             |
                   +-------------------+       PUBLIC Subnets (2 AZs)

                   |        ALB        |  <--  ALB SG: Port 80 from 0.0.0.0/0
                   +-------------------+
                             |
            +----------------+----------------+  PRIVATE App Subnets (2 AZs)

            |  EC2 (ASG)           EC2 (ASG)  |  App SG: Port 80 ONLY from ALB SG
            +----------------+----------------+  Auto-healing, CPU scaling, SSM access
                             |
                   +-------------------+       PRIVATE DB Subnets (No Internet Route)

                   |    RDS MySQL 8    |  <--  DB SG: Port 3306 ONLY from App SG
                   +-------------------+       Credentials auto-stored in Secrets Manager

#### Layer-by-Layer Breakdown

Tier / ComponentAWS Services UsedSecurity & Reliability Controls
****Network Layer****
VPC (10.10.0.0/16), 6 Subnets across 2 AZs (ap-south-1a, ap-south-1b), IGW, NAT GatewayStrict 3-tier subnet segmentation; private subnets route outbound traffic via NAT Gateway with zero inbound internet exposure.
****Tier 1: Web Entry****
Application Load Balancer (ALB), Target Group, HTTP ListenerPublicly accessible only on HTTP port 80; drop_invalid_header_fields = true enabled to prevent HTTP request smuggling.
****Tier 2: App Compute****
EC2 Launch Template, Auto Scaling Group (Nginx), IAM Instance ProfileDeployed in private subnets; Security Group accepts traffic **only** from ALB SG; **IMDSv2 enforced**; encrypted EBS volumes; **AWS SSM** replaces SSH (no port 22 or .pem keys needed).
****Tier 3: Database****
Amazon RDS (MySQL 8), DB Subnet Group, AWS Secrets ManagerIsolated in private DB subnets with no internet route; storage encrypted at rest; SG allows port 3306 **only** from App SG; DB password auto-generated in Secrets Manager.
****State & CI/CD****
Amazon S3, DynamoDB, GitHub ActionsVersioned, AES-256 encrypted S3 remote state with DynamoDB state locking (terraform-locks); automated terraform fmt and terraform validate checks on PRs.

#### Repository Structure

text

aws-3tier-terraform/
├── bootstrap/                  # One-time S3 state bucket + DynamoDB lock table
│   └── main.tf
├── modules/
│   ├── vpc/                    # VPC, public/app/db subnets, IGW, NAT Gateway, route tables
│   ├── alb/                    # Internet-facing ALB, target group (/health), listener, ALB SG
│   ├── asg/                    # Launch template, user_data.sh.tpl, ASG, CPU scaling, SSM IAM role
│   └── rds/                    # RDS MySQL 8 instance, subnet group, DB SG, Secrets Manager secret
├── environments/
│   ├── dev/                    # Cost-optimized lab config (t3.micro, single NAT, single-AZ RDS)
│   │   ├── backend.hcl
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   └── prod/                   # High-availability config (Multi-AZ RDS, deletion protection, 2 NATs)
│       ├── backend.hcl
│       ├── main.tf
│       ├── outputs.tf
│       └── terraform.tfvars
└── .github/workflows/
    └── terraform-ci.yml        # Automated CI checks (fmt + validate) across dev and prod

Use code with caution.

Copy code text to clipboard.

#### Step-by-Step Prerequisites (Zero-to-Ready Setup)

#### Step 1: Create a Dedicated IAM User in AWS (Do This First)

Never use your AWS root account or reuse keys from unrelated projects. Create an isolated IAM deployer user before running Terraform: 

1. Log in to the **AWS Console** → search for **IAM** → go to **Users** → click **Create user**.
2. **User name:** Enter terraform-3tier-deployer (leave console access unchecked) → click **Next**.
3. **Permissions:** Select **Attach policies directly** → search and check **AdministratorAccess** *(for quick lab execution; delete this user after finishing the lab)* → click **Next** → **Create user**.
4. **Generate Access Keys:** 

  * Click on **terraform-3tier-deployer** in the Users list → open the **Security credentials** tab.
  * Under **Access keys**, click **Create access key** → select **Command Line Interface (CLI)** → check the confirmation box → click **Next** → **Create access key**.
  * Copy both the **Access key ID** and **Secret access key** (never commit or screenshot these keys).

#### Step 2: Install Required CLI Tools (Ubuntu / WSL2)

Run this block once in your WSL2 or Ubuntu terminal to install **AWS CLI v2**, **Terraform**, and **unzip**: 

bash

# 1. Install unzip, curl, and GPG utilities
sudo apt update && sudo apt install -y unzip curl wget gpg

# 2. Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# 3. Install HashiCorp Terraform (>= 1.5.0)
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# 4. Verify versions
terraform -version
aws --version

Use code with caution.

Copy code text to clipboard.

#### Step 3: Configure an Isolated AWS CLI Profile

Store your new IAM keys under a dedicated profile named 3tier: 

bash

aws configure --profile 3tier
# Enter:
#   AWS Access Key ID:     <your new key ID>
#   AWS Secret Access Key: <your new secret key>
#   Default region name:   ap-south-1
#   Default output format: json

# Activate the profile for your current terminal session and verify
export AWS_PROFILE=3tier
aws sts get-caller-identity

Use code with caution.

Copy code text to clipboard.

**Important:** Every time you open a **new** terminal window, run export AWS_PROFILE=3tier before running Terraform or AWS CLI commands. 

#### Complete Runbook: Build, Test, Destroy & Re-Run

#### Phase 1: Create the Remote State S3 Bucket & Lock Table (bootstrap/)

Terraform needs an S3 bucket to store terraform.tfstate and a DynamoDB table (terraform-locks) to prevent concurrent state corruption. 

**S3 Naming Rule:** S3 bucket names must be **globally unique across all AWS accounts**, lowercase, and contain no underscores (e.g., kashyap-3tier-tfstate-202611). 

bash

export AWS_PROFILE=3tier
export BUCKET_NAME="your-unique-3tier-tfstate-2026"

cd bootstrap
terraform init
terraform apply -var="state_bucket_name=$BUCKET_NAME" -auto-approve
cd ..

Use code with caution.

Copy code text to clipboard.

*(Creates 5 resources: S3 bucket, versioning, AES-256 encryption, public access block, and DynamoDB lock table.)* 

#### Phase 2: Deploy the dev Environment (~10–12 Minutes)

Connect environments/dev to your new S3 state bucket, validate syntax/formatting, and provision all **35 AWS resources**: 

bash

cd environments/dev

# 1. Inject your S3 bucket name into backend.hcl
sed -i "s/REPLACE-WITH-YOUR-STATE-BUCKET/$BUCKET_NAME/g" backend.hcl

# 2. Initialize remote backend & run CI validation checks
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ../../
terraform validate

# 3. Preview and deploy the 3-tier stack
terraform plan
terraform apply -auto-approve

Use code with caution.

Copy code text to clipboard.

**Expected Wait Time:** Deployment takes **10–12 minutes** because Amazon RDS (db.t3.micro) and the NAT Gateway take ~8–10 minutes to provision. 

#### Phase 3: Verify & Test Live Infrastructure

##### 1. Verify Application Load Balancer & Health Endpoint

bash

ALB_URL=$(terraform output -raw app_url)
echo "Live Application URL: $ALB_URL"

curl -i "$ALB_URL/"
curl -i "$ALB_URL/health"

Use code with caution.

Copy code text to clipboard.

Expected response on /: 

html

<h1>3-tier app (dev)</h1>
<p>Served by instance <b>i-09f38880e6843a161</b> in <b>ap-south-1a</b></p>

Use code with caution.

Copy code text to clipboard.

##### 2. Retrieve Auto-Generated DB Credentials from Secrets Manager

bash

SECRET_ARN=$(terraform output -raw db_secret_arn)
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text

Use code with caution.

Copy code text to clipboard.

##### 3. Test Self-Healing & Auto Scaling (Optional)

bash

# Get the active EC2 Instance ID inside the Auto Scaling Group
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names three-tier-dev-asg \
  --query 'AutoScalingGroups.Instances.InstanceId' --output text)

# Connect to the private EC2 instance via AWS SSM (no SSH key or port 22 needed)
aws ssm start-session --target "$INSTANCE_ID" --region ap-south-1

# Or terminate the instance and watch ASG automatically replace it within ~2 minutes
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region ap-south-1

Use code with caution.

Copy code text to clipboard.

#### Phase 4: Full Teardown (Prevent Ongoing AWS Charges!)

**Cost Warning:** NAT Gateways, Application Load Balancers, EC2 instances, and RDS databases bill hourly. Destroy everything immediately after verifying your deployment. 

##### 1. Destroy the dev Environment (35 Resources, ~6 Minutes)

bash

export AWS_PROFILE=3tier
cd environments/dev
terraform destroy -auto-approve

