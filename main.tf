# --- 1. PROVIDER CONFIGURATION ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # You can change this to your preferred region
}

# --- 2. DATA SOURCES ---
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_rds_engine_version" "latest_postgres" {
  engine  = "postgres"
  version = "15"
  # This is the secret: it picks the version AWS recommends as default
  default_only = true
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    # This wildcard finds any 2023 AMI for x86 architecture
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- 3. NETWORK LAYER ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "production-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "private-subnet-${count.index}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat" { domain = "vpc" }

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
}

# --- 4. ROUTING ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- 5. SECURITY GROUPS ---
resource "aws_security_group" "app_sg" {
  name   = "app-server-sg"
  vpc_id = aws_vpc.main.id

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH restricted to the operator workstation only, never 0.0.0.0/0
  ingress {
    description = "SSH from operator workstation"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "rds-private-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
}

# --- 6. DATABASE LAYER ---
resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
}

resource "aws_db_instance" "postgres" {
  identifier        = "lab-db"
  allocated_storage = 20
  db_name           = "myappdb"

  # Update these references to match the new data source name
  engine         = data.aws_rds_engine_version.latest_postgres.engine
  engine_version = data.aws_rds_engine_version.latest_postgres.version

  instance_class = "db.t3.micro"
  username       = "dbadmin"

  # var.db_password would still be written in plaintext into terraform.tfstate.
  # Letting RDS generate and store it in Secrets Manager keeps it out of both.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  multi_az            = true
  publicly_accessible = false
  storage_encrypted   = true
  skip_final_snapshot = true

  lifecycle {
    ignore_changes = [engine_version]
  }

  tags = { Name = "production-db" }
}

# --- 7. COMPUTE LAYER ---
resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  tags = { Name = "app-server" }
}

# --- 8. VARIABLES ---
variable "admin_cidr" {
  description = "Your workstation public IP in CIDR form, e.g. 203.0.113.4/32"
  type        = string
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in your account"
  type        = string
}

# --- 9. OUTPUTS ---
output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}