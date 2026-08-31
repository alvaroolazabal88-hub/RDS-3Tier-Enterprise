# Cost

`us-east-1`, on-demand, 730 hours a month, with the stack idle. **None of this is
covered by the AWS free tier** — see the note at the end.

| Resource | Rate | Monthly |
|---|---|---|
| NAT Gateway × 2 | $0.045 / hour each | **$65.70** |
| Elastic IP × 2, attached to the NAT Gateways | $0.005 / hour each | **$7.30** |
| RDS `db.t3.micro`, Multi-AZ | $0.036 / hour | **$26.28** |
| RDS storage, 20 GB gp2, Multi-AZ | $0.23 / GB-month | **$4.60** |
| EC2 `t3.micro` | $0.0104 / hour | **$7.59** |
| EC2 root volume, 8 GiB gp3 | $0.08 / GB-month | **$0.64** |
| Secrets Manager secret (created by RDS) | $0.40 / secret | **$0.40** |
| **Total** | | **≈ $112 / month** |

NAT data processing is billed separately at $0.045 per GB. The stack as published
generates no traffic, so that line is zero here and will not be once anything
actually runs.

## Where the money goes

**The two NAT Gateways and their Elastic IPs cost $73 — more than twice the
Multi-AZ database.** Halving that is a single decision: one shared NAT instead of
one per Availability Zone, which saves about $36 a month and makes a zone failure
take outbound access away from the surviving zone. This stack chooses
availability; a development environment should choose the saving.

Adding a gateway VPC endpoint for S3 costs nothing and removes S3 traffic from
the NAT's per-gigabyte charge entirely. It is the first optimisation worth making
once the stack carries real traffic.

## Why none of this is free tier

- **RDS Multi-AZ was never eligible.** The free tier covers "750 hours on a
  selection of **Single-AZ** instance databases". Setting `multi_az = true` leaves
  the free tier by definition.
- **`t3.micro` is not free tier in `us-east-1`.** The legacy free tier covers
  `t2.micro`, and `t3.micro` qualifies only in regions where `t2.micro` is
  unavailable. It is available in `us-east-1`, so the instance is billed.
- **The legacy free tier is closed to new accounts.** It applies only to accounts
  activated before 15 July 2025. Anyone cloning this repository today has none.
- **NAT Gateways, Elastic IPs and Secrets Manager secrets have never had a free
  tier.**

Run `terraform destroy` when you are finished. An idle NAT Gateway bills at the
same rate as a busy one.
