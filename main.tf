provider "aws" {
  region = "eu-west-2"
}

# Create a new VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Main VPC"
  }
}

# Create new subnets in different AZs for LB purposes
resource "aws_subnet" "main_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "Main Subnet A"
  }
}

resource "aws_subnet" "main_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-2b"

  tags = {
    Name = "Main Subnet B"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Main Internet Gateway"
  }
}

# Create a route table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Main Route Table"
  }
}

# Associate the route table with the subnets
resource "aws_route_table_association" "subneta" {
  subnet_id      = aws_subnet.main_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnetb" {
  subnet_id      = aws_subnet.main_b.id
  route_table_id = aws_route_table.main.id
}

# Security group for the web server instances
resource "aws_security_group" "web" {
  name        = "Webserver-SG"
  description = "Security group for my Web server"
  vpc_id      = aws_vpc.main.id

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
    Name = "Webserver SG by Terraform"
  }
}

# Security group for the load balancer
resource "aws_security_group" "lb" {
  name        = "LoadBalancer-SG"
  description = "Security group for the Load Balancer"
  vpc_id      = aws_vpc.main.id

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
    Name = "LoadBalancer SG"
  }
}

# Web Application Load balancer
resource "aws_lb" "web_lb" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [aws_subnet.main_a.id, aws_subnet.main_b.id]

  tags = {
    Name = "Web Application Load Balancer"
  }
}

# Target group
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    path                = "/"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "Web Target Group"
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

# Read credentials from credentials.cf file
locals {
  credentials = jsondecode(templatefile("${path.module}/creds.json", {}))
}

# Store DB credentials in Parameter Store
resource "aws_ssm_parameter" "db_username" {
  name  = "db_username"
  type  = "String"
  value = local.credentials.db_username
  tags = {
    Name = "MySQL Username"
  }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "db_password"
  type  = "SecureString"
  value = local.credentials.db_password
  tags = {
    Name = "MySQL Password"
  }
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "autoscaling_role_policy" {
  role       = "AmazonEC2AutoScalingRole"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

# RDS instance for MySQL
resource "aws_db_instance" "mysqldb" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.35"
  instance_class       = "db.t3.micro"
  username             = aws_ssm_parameter.db_username.value
  password             = aws_ssm_parameter.db_password.value
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.web.id]
  db_subnet_group_name = aws_db_subnet_group.default.name

  tags = {
    Name = "WordPress Database"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web_lc.id
  vpc_zone_identifier  = [aws_subnet.main_a.id, aws_subnet.main_b.id]
  min_size             = 1
  max_size             = 2
  desired_capacity     = 1
  target_group_arns    = [aws_lb_target_group.web_tg.arn]

  tag {
    key                 = "Name"
    value               = "Webserver"
    propagate_at_launch = true
  }

  depends_on = [aws_iam_role_policy_attachment.autoscaling_role_policy]
}

# DB Subnet Group
resource "aws_db_subnet_group" "default" {
  name       = "main-subnet-group"
  subnet_ids = [aws_subnet.main_a.id, aws_subnet.main_b.id]

  tags = {
    Name = "Main Subnet Group"
  }
}

# Web server instances
resource "aws_instance" "web" {
  count                  = 1
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.main_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y apache2 php php-mysql wget
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/
systemctl start apache2
systemctl enable apache2
EOF

  tags = {
    Name = "Webserver"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto scaling group with launch configuration
resource "aws_launch_configuration" "web_lc" {
  name          = "web-launch-configuration"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web.id]
  user_data = <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y apache2 php php-mysql wget
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/
systemctl start apache2
systemctl enable apache2
EOF
  iam_instance_profile = "AmazonEC2AutoScalingRole"
}

#autoscaling group attachments
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  lb_target_group_arn    = aws_lb_target_group.web_tg.arn
}

# Data source for the latest Ubuntu AMI
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
  owners      = ["099720109477"]
}