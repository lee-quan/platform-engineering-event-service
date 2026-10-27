# Terraform: ECS Fargate deployment (skeleton)

Deploys the event service container to AWS ECS Fargate behind an Application Load Balancer.

## What it creates

| Resource | Purpose |
|----------|---------|
| ECR repository (+ lifecycle policy) | Stores the container image, keeps the last 10 |
| CloudWatch log group `/ecs/<app>-<env>` | Container stdout/stderr |
| IAM task execution role | Lets ECS pull from ECR and write logs |
| ECS cluster, task definition, service | Runs `desired_count` Fargate tasks |
| ALB + HTTP:80 listener + target group | Public entry point, health-checks `/ready` |
| Security groups | Internet → ALB:80, ALB → tasks on `container_port` only |

## Assumptions

- **Default VPC.** The account has a default VPC in the chosen region, and its default subnets are public and span at least two AZs (the ALB needs two).
- **Public IPs for tasks.** The default VPC has no NAT gateway, so tasks get a public IP (`assign_public_ip = true`) to reach ECR and CloudWatch. Inbound traffic is still restricted to the ALB security group. For production, use private subnets with a NAT gateway or VPC endpoints.
- **HTTP only.** There's no TLS. For production, add an ACM certificate, an HTTPS:443 listener, and redirect port 80 to it.
- **Remote state.** State lives in the S3 bucket created by `bootstrap/`, one key per environment (`event-service/<env>.tfstate`), with S3-native locking.
- **Single task.** Events are stored in memory in each task. With `desired_count > 1`, tasks don't share events, `GET /events` shows a different list depending on which task answers, and duplicate detection only works within one task. Keep `desired_count = 1` until state moves to a shared store.
- **Image architecture.** `cpu_architecture` defaults to `ARM64` because `docker build` on Apple Silicon produces arm64 images. If you build with `--platform linux/amd64`, set it to `X86_64`.

## One-time bootstrap

`bootstrap/` creates the Terraform state bucket and the IAM user `event-service-github-deploy` that GitHub Actions deploys with. Apply it once, locally, with admin credentials:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output
```

GitHub Actions authenticates with an access key for this user. The usual keyless GitHub OIDC setup isn't possible here because the AWS organization's SCPs deny `iam:*OpenIDConnectProvider` in this account. Create the key in the AWS console (**IAM → Users → event-service-github-deploy → Security credentials → Create access key**) and paste it straight into GitHub. The key is kept out of Terraform so the secret never lands in state. Rotate it regularly.

The user has `PowerUserAccess`, plus IAM rights limited to `event-service-*` roles, and is denied every region except `aws_region`. Replace that with a least-privilege policy for production.

Bootstrap keeps its own state locally (`bootstrap/terraform.tfstate`, gitignored). Keep that file safe, or move it to the new bucket afterwards.

## Deploying with GitHub Actions

`.github/workflows/deploy.yml`:

- **Pull requests to `main`** run `go vet`, the build, `go test`, a Docker build, and `terraform fmt`/`validate`. Nothing is deployed.
- **Pushes to `main`** run the same checks, then deploy to `dev`.
- **Run workflow** (manual) deploys to the environment you pick: `dev`, `staging` or `prod`.

A deploy creates the ECR repository if needed, then builds and pushes an `amd64` image tagged with the commit SHA. It then runs `terraform apply`, waits for the ECS service to become stable, and checks `/health` and `/ready` on the ALB URL.

GitHub setup (repository **Settings**):

1. **Environments:** create `dev`, `staging` and `prod`. Add required reviewers to `prod` if you want an approval step.
2. **Secrets and variables → Actions → Secrets** (repository secrets), from the access key you created:

   | Secret | Value |
   |--------|-------|
   | `AWS_ACCESS_KEY_ID` | Access key ID |
   | `AWS_SECRET_ACCESS_KEY` | Secret access key |

3. **Secrets and variables → Actions → Variables** (repository variables), using the bootstrap outputs:

   | Variable | Value |
   |----------|-------|
   | `TF_STATE_BUCKET` | `tf_state_bucket` |
   | `AWS_REGION` | `aws_region` |

## Deploying manually

The ECS service needs an image in ECR, so create the repository first:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # adjust as needed
terraform init \
  -backend-config="bucket=<tf_state_bucket>" \
  -backend-config="key=event-service/dev.tfstate" \
  -backend-config="region=ap-southeast-2"

# 1. Create the ECR repo
terraform apply -target=aws_ecr_repository.this

# 2. Build and push the image
REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region ap-southeast-2 \
  | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build -t "$REPO:latest" ..
docker push "$REPO:latest"

# 3. Create everything else
terraform apply

# 4. Open the service
open "$(terraform output -raw service_url)"
```

To roll out a new image, push it with a new tag and run `terraform apply -var image_tag=<tag>`.

## Variables

| Name | Default | Description |
|------|---------|-------------|
| `env` | `dev` | `dev`, `staging` or `prod`. Used in resource names and passed to the container as `ENV` |
| `cpu` | `256` | Task CPU units |
| `memory` | `512` | Task memory (MiB). Must be a valid Fargate pairing with `cpu` |
| `desired_count` | `1` | Number of tasks |
| `container_port` | `8080` | Container port. Passed to the container as `PORT` |
| `aws_region` | `ap-southeast-2` | Region |
| `image_tag` | `latest` | ECR image tag to deploy |
| `cpu_architecture` | `ARM64` | `ARM64` or `X86_64`. Must match the image |
| `processing_delay_ms` | `1000` | Passed to the container as `PROCESSING_DELAY_MS` |
| `log_retention_days` | `14` | CloudWatch retention |

## Outputs

`service_url`, `alb_dns_name`, `ecr_repository_url`, `ecs_cluster_name`, `ecs_service_name`, `log_group_name`.
