# EDIT bucket to the name you used in bootstrap/ (must match exactly).
bucket         = "REPLACE-WITH-YOUR-STATE-BUCKET"
key            = "three-tier/prod/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "terraform-locks"
encrypt        = true
