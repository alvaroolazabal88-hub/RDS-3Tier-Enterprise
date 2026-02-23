Service,Estimated Monthly Cost (USD),Optimization Strategy
NAT Gateway,~$32.00,Used for secure outbound updates only.
ALB,~$18.00,Handles traffic distribution across AZs.
EC2 (t3.micro),~$0.00 (Free Tier),Managed by Auto Scaling to minimize idle time.
RDS (db.t3.micro),~$15.00,Multi-AZ enabled for production durability.