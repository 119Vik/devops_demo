```hcl
provider "aws" {
  region = "us-east-1" # Replace with your desired region
}

# Use default VPC and network ACLs
data "aws_vpc" "default" {
  default = true
}

# Web Servers
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "web_server" {
  name_prefix = "web-server-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "web_server" {
  name_prefix     = "web-server-"
  image_id        = data.aws_ami.ubuntu.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_server.id]
}

resource "aws_autoscaling_group" "web_server" {
  name                 = "web-server-asg"
  launch_configuration = aws_launch_configuration.web_server.name
  min_size             = 2
  max_size             = 2
  desired_capacity     = 2
  vpc_zone_identifier  = data.aws_vpc.default.private_subnets

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "alb-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "web_server" {
  name               = "web-server-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_vpc.default.public_subnets
}

resource "aws_lb_listener" "web_server" {
  load_balancer_arn = aws_lb.web_server.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.web_server.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_server.arn
  }
}

resource "aws_acm_certificate" "web_server" {
  domain_name       = "*.apps.digitalgalaxy.llc"
  validation_method = "DNS"
}

resource "aws_lb_target_group" "web_server" {
  name        = "web-server-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

# Database
resource "aws_security_group" "rds" {
  name_prefix = "rds-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier           = "postgres-rds"
  engine               = "postgres"
  engine_version       = "14.6"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp3"
  backup_retention_period = 0
  multi_az             = false
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot  = true
}

# Outputs
output "alb_dns_name" {
  value       = aws_lb.web_server.dns_name
  description = "DNS name of the Application Load Balancer"
}
```

This Terraform code creates the necessary resources based on the provided architecture diagram and requirements. It includes the following:

- Web Servers:
  - Uses the latest Ubuntu 22.04 AMI from Canonical
  - Auto Scaling Group with a minimum, maximum, and desired capacity of 2 instances
  - Launch Configuration for t2.micro instances
  - Security Group allowing HTTP traffic from the ALB and PostgreSQL traffic from the RDS

- Application Load Balancer:
  - Listens on HTTPS (port 443) and terminates TLS with a certificate from AWS Certificate Manager for *.apps.digitalgalaxy.llc
  - Forwards traffic to port 80 of the web servers
  - Security Group allowing incoming HTTPS traffic

- Database:
  - PostgreSQL 14.6 RDS instance with the smallest instance class (db.t3.micro)
  - gp3 storage type, no backups, and no multi-AZ deployment
  - Security Group allowing PostgreSQL traffic from the web servers

- Security and Networking:
  - Uses the default VPC and network ACLs
  - Security Groups for the ALB, web servers, and RDS as per the requirements

- Deployment and Automation:
  - Uses Terraform for Infrastructure as Code (IaC) deployment
  - Dependencies and resource creation order are handled automatically by Terraform

Note: You will need to configure the AWS provider with your desired region and replace the `aws_acm_certificate` resource with your own certificate or remove it if not required.