# Enterprise-Grade 3-Tier AWS Infrastructure

## Architecture Overview
This project implements a highly available, scalable, and secure 3-tier architecture on AWS using Infrastructure as Code (Terraform). 

### Key Components:
- **VPC:** Custom 10.0.0.0/16 network.
- **Tier 1 (Web/Public):** Application Load Balancer (ALB) and NAT Gateways across 2 Availability Zones.
- **Tier 2 (Application):** Auto Scaling Group (ASG) with EC2 instances in private subnets.
- **Tier 3 (Database):** Multi-AZ Amazon RDS (MySQL/PostgreSQL) for synchronous data replication.

## Features
- **High Availability:** Deployed across 2 AZs to ensure 99.9% uptime.
- **Security:** Strict Security Group chaining (Least Privilege Principle).
- **Scalability:** Integrated ASG to handle traffic spikes automatically.
- **Cost-Optimization:** Single NAT Gateway option available for development environments.

## Deployment
1. Initialize Terraform: `terraform init`
2. Review Plan: `terraform plan`
3. Deploy: `terraform apply`