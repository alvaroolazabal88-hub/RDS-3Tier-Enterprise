# Security Policy

## Shared Responsibility Model
While AWS manages the security **of** the cloud, this project follows best practices for security **in** the cloud.

## Implemented Controls
1. **Security Group Chaining:** - ALB (Public) only accepts HTTPS (443).
   - App Tier only accepts traffic from the ALB SG.
   - DB Tier only accepts traffic from the App Tier SG.
2. **Network Isolation:** Database and App tiers are located in private subnets with no direct internet access.
3. **Encryption:** - RDS Storage is encrypted at rest using AWS KMS.
   - All public traffic is encrypted via TLS/SSL.