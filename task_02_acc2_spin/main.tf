# Specify the provider and region for Account 2
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

# Create a new VPC in Account 2
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

# Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.new_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-1b"
  map_public_ip_on_launch = true  # Automatically assign public IPs to instances

  tags = {
    Name = "public-subnet"
  }
}

# Create a route table
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

# Associate the route table with the public subnet
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
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

# Fetch the shared AMI from Account 1
data "aws_ami" "shared_ami" {
  most_recent = true
  owners      = ["533267066784"]  # Replace with the Account 1 ID

  filter {
    name   = "name"
    values = ["web-server-ami"]  # Match the AMI name
  }
}

# Launch an EC2 instance using the shared AMI
resource "aws_instance" "web_instance" {
  ami                    = data.aws_ami.shared_ami.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.new_key_pair.key_name  # Use the key pair created above
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "Shared-AMI-Instance"
  }
}

# Allocate Elastic IP and associate it with the EC2 instance
resource "aws_eip" "web_instance_eip" {
  instance = aws_instance.web_instance.id
  domain   = "vpc"  # Make sure it's associated with a VPC
}

# Output the public IP of the instance (Elastic IP)
output "instance_public_ip" {
  value = aws_eip.web_instance_eip.public_ip
}

# Output the public DNS of the instance
output "instance_public_dns" {
  value = aws_instance.web_instance.public_dns
}

# Output the private key (sensitive)
output "private_key" {
  value     = tls_private_key.new_key.private_key_pem
  sensitive = true
}