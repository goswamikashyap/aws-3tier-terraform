# ---------------------------------------------------------------------------
# RDS module: the database tier (tier 3)
#   - private subnets only, not publicly accessible
#   - port 3306 open ONLY to the app tier's security group
#   - encrypted at rest
#   - master password generated and stored by RDS in AWS Secrets Manager
#     (manage_master_user_password) -> no password in code or tfvars
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name}-db-sg"
  description = "Allow MySQL only from the app security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from app tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }

  tags = { Name = "${var.name}-db-sg" }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.db_subnet_ids
}

resource "aws_db_instance" "this" {
  identifier        = "${var.name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  db_name           = "appdb"
  username          = "appadmin"

  # RDS creates the password and keeps it in Secrets Manager for us.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az                  = var.multi_az # standby copy in a 2nd AZ (prod)
  backup_retention_period   = var.backup_retention_days
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"
}

# Allow the app instances to read the generated DB credentials at runtime.
resource "aws_iam_role_policy" "read_db_secret" {
  name = "${var.name}-read-db-secret"
  role = var.app_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_db_instance.this.master_user_secret[0].secret_arn
    }]
  })
}
