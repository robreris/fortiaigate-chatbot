# FortiAIGate Chatbot Demo

A web-based chatbot that routes user prompts through FortiAIGate's AI security gateway before reaching the configured LLM backend. Demonstrates FortiAIGate features including prompt injection detection, DLP, and toxicity filtering.

## Architecture

```
Browser → Nginx (frontend) → FastAPI (backend) → FortiAIGate (/v1/test) → LLM
```

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

**Prerequisites:** AWS CLI configured, Docker

### One-time setup (run in order)

```bash
make iam-setup
make ecr-setup
make secrets-setup FORTIAIGATE_API_KEY=sk-xxx NGINX_PASSWORD=yourpassword
make cluster-create
make service-create
```

After `service-create`, wait ~60 seconds then:

```bash
make service-info   # prints the public IP
```

### Deployment lifecycle

| Scenario | Command |
|---|---|
| New code changes | `make deploy` |
| Full teardown | `make teardown` |
| Fresh redeploy after teardown | `make cluster-create && make service-create` |

### Configuration overrides

```bash
make deploy AWS_REGION=us-west-2
make service-create SUBNET_IDS=subnet-abc,subnet-def
make deploy FORTIAIGATE_MODEL=gpt-4o
```

### What teardown removes vs. retains

| Resource | `make teardown` |
|---|---|
| ECS service + cluster | Removed |
| Security group | Removed |
| ECR repositories | **Retained** |
| Secrets Manager secrets | **Retained** |
| CloudWatch log group | **Retained** |

Re-running `make ecr-setup` or `make secrets-setup` after teardown is safe — they are idempotent.
