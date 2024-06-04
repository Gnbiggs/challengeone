#--------------------------------------------
# My Terraform
#
# Build WebServer during Bootstrap
#
# Made by AP
#--------------------------------------------

provider "aws" {
  region = "eu-west-2"
}

# Checks for the latest version of Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# Security group for web server instances
resource "aws_security_group" "web" {
  name        = "Webserver-SG"
  description = "Security group for my Web server"

  ingress {
    from_port   = 80
    to_port     = 83
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
  tags = {
    name = "Webserver SG by Terraform"
  }
}

# Security group for load balancer
resource "aws_security_group" "lb" {
  name        = "LoadBalancer-SG"
  description = "Security group for the Load Balancer"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
  tags = {
    name = "LoadBalancer SG by Terraform"
  }
}

# Load balancer
resource "aws_lb" "web_lb" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = ["subnet-abc123", "subnet-def456"]  # Replace with your subnets

  tags = {
    name = "Web Load Balancer by Terraform"
  }
}

# Target group
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-abc123"  # Replace with your VPC ID

  health_check {
    interval            = 30
    path                = "/"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    name = "Web Target Group by Terraform"
  }
}

# Load balancer listener
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Web server instances
resource "aws_instance" "web" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y apache2
MYIP=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
echo "<h2>WebServer with PrivateIP: $MYIP</h2><br>Built by Terraform" > /var/www/html/index.html
systemctl start apache2
systemctl enable apache2
EOF

  tags = {
    name = "Webserver built by Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }

  # Register instances with the load balancer target group
  provisioner "local-exec" {
    command = "aws elbv2 register-targets --target-group-arn ${aws_lb_target_group.web_tg.arn} --targets Id=${self.id}"
  }
}
