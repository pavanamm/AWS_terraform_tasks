# Specify the provider and region
provider "aws" {
  region = "us-west-1"
}

# Generate a new SSH key pair using the TLS provider
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Upload the public key to AWS as a key pair
resource "aws_key_pair" "new_key_pair" {
  key_name   = "mayi"  # Name for the new key pair
  public_key = tls_private_key.new_key.public_key_openssh  # Public key from the TLS resource
}

# Create a new VPC
resource "aws_vpc" "new_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true  # Enable DNS resolution
  enable_dns_hostnames = true  # Enable DNS hostnames

  tags = {
    Name = "new-vpc"
  }
}

# Create an Internet Gateway (IGW)
resource "aws_internet_gateway" "new_igw" {
  vpc_id = aws_vpc.new_vpc.id

  tags = {
    Name = "new-igw"
  }
}

# Create two public subnets in different AZs
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.new_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-1c"  # First AZ
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.new_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-1b"  # Second AZ
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-2"
  }
}

# Create a private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.new_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-west-1b"
  map_public_ip_on_launch = false  # No public IP for private subnet

  tags = {
    Name = "private-subnet"
  }
}

# Create a route table for the public subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.new_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.new_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate the route table with the public subnets
resource "aws_route_table_association" "public_rt_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Create a NAT Gateway in the public subnet
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "nat-gw"
  }
}

# Create a route table for the private subnet
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.new_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Associate the route table with the private subnet
resource "aws_route_table_association" "private_rt_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Create a security group to allow HTTP (port 80) and SSH (port 22) access
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow inbound HTTP and SSH traffic"
  vpc_id      = aws_vpc.new_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

# Fetch the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Launch an EC2 instance in the private subnet
resource "aws_instance" "web_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.new_key_pair.key_name  # Use the key pair created above
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # User data to install and configure the web server
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              echo "<html><body><h1>Welcome to My Web Server!</h1></body></html>" | sudo tee /var/www/html/index.html
              EOF

  tags = {
    Name = "Web-Server-Instance"
  }
}

# Create an Application Load Balancer (ALB)
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false  # Set to true if you want an internal ALB
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]  # Use both subnets

  tags = {
    Name = "web-alb"
  }
}

# Create a target group for the ALB
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.new_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

# Attach the EC2 instance to the target group
resource "aws_lb_target_group_attachment" "web_tg_attachment" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web_instance.id
  port             = 80
}

# Create a listener for the ALB
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Create a Network Load Balancer (NLB)
resource "aws_lb" "web_nlb" {
  name               = "web-nlb"
  internal           = false  # Set to true if you want an internal NLB
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]  # Use both subnets

  tags = {
    Name = "web-nlb"
  }
}

# Create a target group for the NLB
resource "aws_lb_target_group" "web_nlb_tg" {
  name     = "web-nlb-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.new_vpc.id

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
}

# Attach the EC2 instance to the NLB target group
resource "aws_lb_target_group_attachment" "web_nlb_tg_attachment" {
  target_group_arn = aws_lb_target_group.web_nlb_tg.arn
  target_id        = aws_instance.web_instance.id
  port             = 80
}

# Create a listener for the NLB
resource "aws_lb_listener" "web_nlb_listener" {
  load_balancer_arn = aws_lb.web_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_nlb_tg.arn
  }
}

# Output the ALB DNS name
output "alb_dns_name" {
  value = aws_lb.web_alb.dns_name
}

# Output the NLB DNS name
output "nlb_dns_name" {
  value = aws_lb.web_nlb.dns_name
}

# Output the private key (sensitive)
output "private_key" {
  value     = tls_private_key.new_key.private_key_pem
  sensitive = true
}