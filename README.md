# AWS FinOps Platform: CUR, Athena, QuickSight, Cost Alerts and Automated Remediation

A Terraform-defined FinOps platform for AWS that gives you **cost visibility** (Cost and Usage Reports queryable in Athena and visualized in QuickSight), **cost guardrails** (budgets and anomaly detection), and **automated savings** (stopping idle EC2 instances on a schedule or in response to monitoring alerts). It also wires in third-party FinOps and observability tools: **Apptio Cloudability**, **Dynatrace** and **Datadog**.

## Architecture

```
                    ┌──────────────────────────── Cost visibility ───────────────────────────┐
AWS Billing ──CUR (hourly, Parquet)──► S3 ──► Glue crawler (daily) ──► Athena ──► QuickSight dashboards
                                        │                                  ▲
                                        └── read-only role ──► Apptio Cloudability

                    ┌──────────────────────────── Cost guardrails ───────────────────────────┐
AWS Budgets (80% actual / 100% forecast) ──► email
Cost Anomaly Detection (per service) ──────► daily email digest

                    ┌──────────────────────────── Automated savings ─────────────────────────┐
EventBridge (daily) ──► Lambda: find opted-in EC2 with low 7-day CPU ──► stop (or dry-run report)
                                                     └──► CloudWatch metrics: FinOps/IdleInstances*
Dynatrace / Datadog alert ──webhook + secret──► API Gateway ──► Lambda ──► stop idle / flag scale-up
```

## What this demonstrates

- **Cost data pipeline:** CUR in Parquet → Glue catalog → Athena with saved queries (cost by service, by account, daily trend, top resources) → QuickSight dataset
- **Guardrails:** monthly budget with actual and forecast alerts; Cost Anomaly Detection with a dollar-impact threshold
- **Safe automation:** instances must opt in with an `AutoStop=true` tag, enforced in both code and IAM conditions; dry-run by default; results published as CloudWatch metrics
- **Secure integrations:** role-based cross-account access with external IDs for Cloudability, Datadog and Dynatrace (no long-lived access keys); webhook protected by a shared secret in Secrets Manager
- **Cost-aware storage:** S3 lifecycle rules (CUR to Infrequent Access, Athena results expire) and an Athena per-query scan limit
- **Infrastructure as code** with Terraform, validated in GitHub Actions

## Background

This platform packages the patterns I used in enterprise FinOps work, including a cloud cost programme at Ford that delivered about **$17M in savings**: make spend visible per team, alert before budgets are blown, and automate the safe, repeatable savings so engineers don't have to remember them.

## Measuring savings

- **Idle-instance automation:** the `FinOps/IdleInstancesStopped` CloudWatch metric counts instances stopped each day. Multiply stopped hours by each instance type's on-demand rate for an estimated saving.
- **Before/after:** run the saved `daily_cost_trend_last_90_days` query and compare the 30 days before enabling remediation with the 30 days after.
- **By owner:** add your cost allocation tags (for example `Team`) to the `top_20_resources_this_month` query to see who benefits.

## Deploy

Prerequisites: Terraform ≥ 1.5, AWS CLI credentials for the **management/payer account** (CUR is defined there), region `us-east-1`.

```bash
cp terraform.tfvars.example terraform.tfvars   # set bucket_name and alert_email
terraform init
terraform apply
```

AWS delivers the first Cost and Usage Report within about 24 hours. After that:

1. The Glue crawler runs daily (or start it now: `aws glue start-crawler --name finops-cur-crawler`) and creates the CUR table.
2. Run the saved queries in the Athena console (workgroup `finops-workgroup`).
3. To build dashboards, set `enable_quicksight = true` and `quicksight_user = "<your user>"`, grant QuickSight access to the bucket in its security settings, and `terraform apply` again.

## Idle-instance automation

- Tag instances that may be stopped automatically: `AutoStop = true`. Untagged instances are never touched.
- The daily job starts in **dry-run** mode and only logs what it would stop. Review the logs, then set `idle_cleanup_dry_run = false`.
- Alert webhook: configure your Dynatrace or Datadog alert to `POST` to the `remediation_webhook_url` output with header `x-webhook-token` (value in the secret from `webhook_token_secret_arn`) and body `{"instance_id": "i-...", "cpu": 3.1}`.

## Integrations (optional)

| Tool | Enable with | Notes |
|---|---|---|
| Apptio Cloudability | `enable_cloudability`, `cloudability_account_id`, `cloudability_external_id` | Read-only billing role; give the `cloudability_role_arn` output to Cloudability |
| Datadog | `enable_datadog`, `datadog_external_id` | Role for the Datadog AWS integration |
| Dynatrace | `enable_dynatrace`, `dynatrace_aws_account_id`, `dynatrace_external_id` | Then apply [`integrations/dynatrace`](integrations/dynatrace/main.tf) with `DYNATRACE_ENV_URL` and `DYNATRACE_API_TOKEN` set |

## Clean up

```bash
terraform destroy
```

The CUR bucket must be empty before it can be deleted.
