provider "aws" {
  region = "us-west-2"  # Updated to a valid region
}

# 🔹 Generate SSH Key Pair
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "new_key_pair" {
  key_name   = "mayi"
  public_key = tls_private_key.new_key.public_key_openssh
}

output "private_key" {
  value     = tls_private_key.new_key.private_key_pem
  sensitive = true
}

# 🔹 Create VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# 🔹 Create Public & Private Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"  # Updated to a valid AZ
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-2a"  # Updated to a valid AZ
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-west-2b"  # Updated to a valid AZ
  map_public_ip_on_launch = false
}

# 🔹 Create an Internet Gateway for Public Subnet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# 🔹 Create a NAT Gateway for Private Subnet
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
}

# 🔹 Create Public & Private Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

# 🔹 Generate a Secure RDS Password
resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "db_secret" {
  name = "rds-db-password"
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = random_password.db_password.result
}

# 🔹 Create RDS Security Group
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict in production!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 🔹 Create RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "my-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

# 🔹 Create RDS PostgreSQL Instance
resource "aws_db_instance" "rds" {
  identifier             = "my-postgres-db"
  allocated_storage      = 20
  engine                = "postgres"
  engine_version        = "15"
  instance_class        = "db.t3.micro"
  db_name               = "mydatabase"
  username              = "admin_1"
  password              = random_password.db_password.result
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible   = false
  skip_final_snapshot   = true
  db_subnet_group_name  = aws_db_subnet_group.rds_subnet_group.name
}

# 🔹 Create EC2 Security Group (Allow SSH & RDS)
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.rds_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fetch the latest Amazon Linux 2 AMI ID
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 🔹 Create an EC2 Instance
resource "aws_instance" "ec2" {
  ami                    = data.aws_ami.amazon_linux_2.id  # Use the dynamically fetched AMI ID
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.new_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.public_subnet.id

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y postgresql
              EOF
}


# Outputs
output "vpc_id" {
  value = aws_vpc.my_vpc.id
}

output "ec2_public_ip" {
  value = aws_instance.ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.rds.endpoint
}