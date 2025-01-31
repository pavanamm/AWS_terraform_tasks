# Specify the provider and region
provider "aws" {
  region = "us-west-1"  # Change to your desired region
}

# Use the default VPC in the specified region
data "aws_vpc" "default" {
  default = true
}

# Create an Internet Gateway (IGW)
resource "aws_internet_gateway" "default" {
  vpc_id = data.aws_vpc.default.id
}

# Create a subnet in the default VPC
resource "aws_subnet" "default_subnet" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.32.0/24"  # Modify the CIDR block as needed
  availability_zone       = "us-west-1b"  # Updated availability zone
  map_public_ip_on_launch = true
  tags = {
    Name = "default-subnet"
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "default" {
  vpc_id = data.aws_vpc.default.id

  # Add route to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name = "default-route-table"
  }
}

# Associate the route table with the subnet
resource "aws_route_table_association" "default" {
  subnet_id      = aws_subnet.default_subnet.id
  route_table_id = aws_route_table.default.id
}

# Create a security group to allow HTTP (port 80) and SSH (port 22) access
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow inbound HTTP and SSH traffic"
  vpc_id      = data.aws_vpc.default.id  # Correct reference to the data resource

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

# Create an EC2 instance
resource "aws_instance" "web_instance" {
  ami           = "ami-0d382e80be7ffdae5"  # Replace with your correct AMI ID
  instance_type = "t2.micro"  # Free tier instance type
  key_name      = "mayi"  # Use your SSH key for instance access
  subnet_id     = aws_subnet.default_subnet.id  # Reference the subnet created above
  vpc_security_group_ids = [aws_security_group.web_sg.id]  # Corrected parameter

  tags = {
    Name = "Web-server"
  }

  # User data script to install Apache web server on Ubuntu
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2
              systemctl enable apache2
              systemctl start apache2
              echo "<!DOCTYPE html>
              <html>
              <head>
                  <title>Welcome to My Cool Website!</title>
                  <style>
                      body {
                          font-family: Arial, sans-serif;
                          background-color: #f0f0f0;
                          text-align: center;
                          padding: 50px;
                      }
                      h1 {
                          color: #333;
                      }
                      p {
                          color: #666;
                      }
                  </style>
              </head>
              <body>
                  <h1>Hello, World!</h1>
                  <p>Welcome to my cool website hosted on AWS!</p>
              </body>
              </html>" > /var/www/html/index.html
              EOF
}

# Create an AMI from the web instance
resource "aws_ami_from_instance" "web_ami" {
  name                 = "web-server-ami"
  source_instance_id   = aws_instance.web_instance.id
  description          = "AMI created from the web server instance"

  tags = {
    Name = "WebServerAMI"
  }
}

# Share the AMI with Account 2
resource "aws_ami_launch_permission" "share_ami" {
  image_id   = aws_ami_from_instance.web_ami.id
  account_id = "654654298266"  # Replace with Account 2’s AWS Account ID
}

output "instance_public_ip" {
  value = aws_instance.web_instance.public_ip
}

output "web_ami_id" {
  value = aws_ami_from_instance.web_ami.id
}