#!/bin/bash
# Runs once at first boot. Installs nginx and serves a page that shows which
# instance answered, so you can SEE load balancing working.
set -euxo pipefail
dnf install -y nginx

# IMDSv2: must fetch a session token first (IMDSv1 is disabled on this instance)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<HTML
<h1>3-tier app (${environment})</h1>
<p>Served by instance <b>$INSTANCE_ID</b> in <b>$AZ</b></p>
HTML

# Endpoint used by the ALB health check
echo "ok" > /usr/share/nginx/html/health

systemctl enable --now nginx
