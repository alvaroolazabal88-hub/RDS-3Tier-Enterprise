terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_rds_engine_version" "latest_postgres" {
  engine       = "postgres"
  version      = "15"
  default_only = true
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

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
  tags                    = { Name = "public-subnet-${count.index + 1}" }
}

resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "private-app-subnet-${count.index + 1}" }
}

resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "private-db-subnet-${count.index + 1}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "production-igw" }
}

# TWO Elastic IPs and TWO NAT Gateways (One per AZ)
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "nat-gateway-${count.index + 1}" }
}

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

# TWO Private Route Tables for App Tier (each points to its own NAT)
resource "aws_route_table" "private_app" {
  count  = 2
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
}

resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# DB Tier Route Table (Strictly local, no internet out for maximum security)
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

resource "aws_security_group" "app_sg" {
  name   = "app-server-sg"
  vpc_id = aws_vpc.main.id

  # HTTP from inside the VPC only. The instance sits in a private subnet with
  # no public IP, so an internet-wide rule here would be dead weight that reads
  # like an oversight. A load balancer in the public subnets would still reach it.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # SSH access (Restricted to your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
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

  # Deliberately no egress block. Security groups are stateful, so replies to
  # the application still flow; what the database cannot do is open outbound
  # connections of its own. That blocks data exfiltration if it is ever
  # compromised.
}

resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.private_db[0].id, aws_subnet.private_db[1].id]
}

resource "aws_db_instance" "postgres" {
  identifier        = "lab-db"
  allocated_storage = 20
  db_name           = "myappdb"

  engine         = data.aws_rds_engine_version.latest_postgres.engine
  engine_version = data.aws_rds_engine_version.latest_postgres.version

  instance_class = "db.t3.micro"
  username       = "dbadmin"

  # A Terraform variable would still land in plaintext inside terraform.tfstate,
  # even marked sensitive. Letting RDS generate the password and hold it in
  # Secrets Manager keeps it out of the code and out of the state, and allows
  # rotation.
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

resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_app[0].id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = false
  key_name                    = var.key_name

  tags = { Name = "app-server" }
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in your account"
  type        = string
}

variable "my_ip" {
  description = "My personal IP address for SSH access (e.g., 203.0.113.5/32)"
  type        = string
}

output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "ec2_private_ip" {
  value = aws_instance.app_server.private_ip
}