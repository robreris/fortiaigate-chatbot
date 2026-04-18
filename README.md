# FortiAIGate Chatbot Demo

A web-based chatbot that routes user prompts through FortiAIGate's AI security gateway before reaching the configured LLM backend. Demonstrates FortiAIGate features including prompt injection detection, DLP, and toxicity filtering.

## Architecture

```
Browser → ALB (HTTPS/443) → Nginx (frontend) → FastAPI (backend) → FortiAIGate (/v1/test) → LLM
```

TLS is terminated at the Application Load Balancer using an ACM certificate. HTTP (port 80) redirects to HTTPS automatically. The ALB forwards to the Nginx container on port 80; tasks are not directly reachable from the internet.

## Local Development

**Prerequisites:** Docker Desktop or Docker + Docker Compose v2

```bash
cp .env.example .env
# Edit .env — set FORTIAIGATE_BASE_URL, FORTIAIGATE_API_KEY, NGINX_USERNAME, NGINX_PASSWORD
docker compose up --build
```

Open `http://localhost:3000` and log in with the credentials from your `.env`.

### Switching FortiAIGate endpoints (local)

| Scenario | FORTIAIGATE_BASE_URL | FORTIAIGATE_SSL_VERIFY |
|---|---|---|
| Production ALB | `https://<alb-hostname>` | `true` |
| Local proxy (`make local-proxy`) | `https://host.docker.internal:9443` | `false` |
| Local port-forward (`make port-forwards`) | `https://host.docker.internal:28443` | `false` |

## AWS ECS Deployment

**Prerequisites:** AWS CLI configured, Docker, a Route 53 hosted zone for your domain

### One-time setup (run in order)

These steps create persistent resources that survive `make teardown`.

```bash
make iam-setup
make ecr-setup
make secrets-setup FORTIAIGATE_API_KEY=sk-xxx NGINX_PASSWORD=yourpassword
make cluster-create
make acm-setup DOMAIN_NAME=chatbot.example.com HOSTED_ZONE_ID=Z1234567890ABC
```

`acm-setup` requests an ACM certificate, adds the DNS validation CNAME to your Route 53 hosted zone, and waits for issuance (typically 1–5 minutes). The certificate is detected automatically on future runs from the domain name.

### Provisioning the service

```bash
make service-create \
  DOMAIN_NAME=chatbot.example.com \
  HOSTED_ZONE_ID=Z1234567890ABC \
  FORTIAIGATE_BASE_URL=https://fortiaigate.example.com
```

This creates in order: ALB security group, task security group, target group, ALB, HTTPS/HTTP listeners, ECS service, and a Route 53 alias A record pointing to the ALB. All steps are idempotent — safe to re-run after a partial failure.

After ~90 seconds check health:

```bash
make service-info DOMAIN_NAME=chatbot.example.com
```

The app is then available at `https://chatbot.example.com`.

### Deployment lifecycle

| Scenario | Command |
|---|---|
| New code changes | `make deploy FORTIAIGATE_BASE_URL=https://...` |
| Teardown (keep cluster) | `make teardown DOMAIN_NAME=... HOSTED_ZONE_ID=...` |
| Reprovision after teardown | `make service-create DOMAIN_NAME=... HOSTED_ZONE_ID=... FORTIAIGATE_BASE_URL=...` |
| Full destroy | `make teardown ... && make cluster-delete` |

`make teardown` leaves the ECS cluster and ACM certificate in place so reprovisioning is fast — no waiting for certificate issuance.

### Configuration overrides

```bash
make deploy AWS_REGION=us-west-2
make service-create SUBNET_IDS=subnet-abc,subnet-def DOMAIN_NAME=... HOSTED_ZONE_ID=...
make deploy FORTIAIGATE_MODEL=gpt-4o
```

### What teardown removes vs. retains

| Resource | `make teardown` |
|---|---|
| ECS service + tasks | Removed |
| ALB, listeners, target group | Removed |
| Security groups (ALB + task) | Removed |
| Route 53 A record | Removed |
| ECS cluster | **Retained** |
| ACM certificate | **Retained** |
| ECR repositories | **Retained** |
| Secrets Manager secrets | **Retained** |
| CloudWatch log group | **Retained** |

Re-running `make ecr-setup`, `make secrets-setup`, or `make acm-setup` after teardown is safe — they are all idempotent.
