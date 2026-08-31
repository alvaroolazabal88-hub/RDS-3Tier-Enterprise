# Security notes

Every control below is implemented in `main.tf` and cited by line. Anything this
project does *not* do is listed at the end rather than left unsaid.

## Network isolation

| Control | Where |
|---|---|
| Three subnet tiers, each `count = 2` across two Availability Zones | `main.tf:49`, `:59`, `:68` |
| Private **data** subnets route table declared with **no routes at all** — the database tier has no path to the internet in either direction | `main.tf:127` |
| Private **application** subnets route outbound only, through the NAT Gateway in their own Availability Zone | `main.tf:111` |
| Application instance runs in a private subnet with `associate_public_ip_address = false` | `main.tf:224`, `:229` |
| RDS placed in the private data subnets through a DB subnet group | `main.tf:186` |

## Security group chaining

Rules reference other security groups by ID rather than by CIDR, so the chain
survives any change of address range.

| Control | Where |
|---|---|
| `app_sg` accepts HTTP `80` only from the VPC CIDR, not from the internet | `main.tf:149` |
| `app_sg` accepts SSH `22` only from `var.my_ip`, the operator's own address | `main.tf:157` |
| `db_sg` accepts PostgreSQL `5432` **only from `app_sg`** | `main.tf:173-176` |
| `db_sg` has **no egress rules at all** | `main.tf:179` |

**Why the database has no egress rules.** Security groups are stateful: the reply
to a connection the application opened is allowed back automatically, whether or
not an egress rule exists. Removing egress therefore costs nothing in normal
operation, and it removes the database's ability to *initiate* an outbound
connection. If the database were ever compromised, there is no route out for the
data and no way to fetch a second-stage payload. This is the practical difference
between security groups and network ACLs, which are stateless and would need the
return traffic permitted explicitly.

## Data protection

| Control | Where |
|---|---|
| `storage_encrypted = true` — encryption at rest, using the AWS-managed key `aws/rds` | `main.tf:213` |
| `publicly_accessible = false` — no public endpoint for the database | `main.tf:212` |
| `multi_az = true` — synchronous standby in the second Availability Zone | `main.tf:211` |
| `manage_master_user_password = true` — RDS generates the master password and stores it in AWS Secrets Manager | `main.tf:206` |

**Why the password is not a Terraform variable.** A variable marked
`sensitive = true` is hidden from the CLI output, but its value is still written
in plaintext into `terraform.tfstate`. Anyone with the state file has the
password. Having RDS generate it means it appears in neither the repository nor
the state, and it can be rotated without touching the code.

## Reproducibility

| Control | Where |
|---|---|
| `var.my_ip` and `var.key_name` — no personal address or key pair name hardcoded | `terraform.tfvars.example` |
| `.gitignore` excludes `*.tfstate`, `*.tfstate.*` and `*.tfvars` | `.gitignore` |

## Not implemented

- **No TLS anywhere.** Port 80 carries plain HTTP. Terminating TLS needs a load
  balancer and an ACM certificate, which needs a domain this project does not own.
- **No load balancer**, so the application security group is scoped to the VPC
  CIDR rather than to a load balancer's security group.
- **No customer-managed KMS key.** Encryption uses the AWS-managed `aws/rds` key,
  so key rotation and key access are not auditable independently of the database.
- **No VPC endpoints.** Calls to AWS services from the private application subnet
  leave through the NAT Gateway.
- **`app_sg` allows all outbound traffic** (`main.tf`, egress block). Least
  privilege is enforced on the database tier, not on the application tier.
- **No CloudTrail, GuardDuty, Config or CloudWatch alarms** are created by this
  stack.
