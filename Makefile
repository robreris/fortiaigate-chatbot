export AWS_PAGER  =

AWS_REGION        ?= us-east-1
AWS_ACCOUNT_ID    ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
CLUSTER_NAME      ?= fortiaigate-chatbot
SERVICE_NAME      ?= fortiaigate-chatbot
TAG               ?= latest

FRONTEND_REPO      = fortiaigate-chatbot-frontend
BACKEND_REPO       = fortiaigate-chatbot-backend
ECR_BASE           = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
FRONTEND_IMAGE     = $(ECR_BASE)/$(FRONTEND_REPO)
BACKEND_IMAGE      = $(ECR_BASE)/$(BACKEND_REPO)

# FortiAIGate settings — must be set for task-register and deploy
FORTIAIGATE_BASE_URL ?= fortiaigate.fortinetcloudcse.com
FORTIAIGATE_MODEL    ?= gpt-4o-mini
NGINX_USERNAME       ?= demo

# Subnets for service-create — auto-detects default VPC public subnets if not set
SUBNET_IDS ?= $(shell aws ec2 describe-subnets \
	--filters "Name=default-for-az,Values=true" \
	--region $(AWS_REGION) \
	--query "Subnets[*].SubnetId" \
	--output text 2>/dev/null | tr '\t' ',')

.PHONY: help iam-setup ecr-setup secrets-setup login build push task-register \
        cluster-create service-create deploy service-info \
        service-delete cluster-delete teardown

help:
	@echo ""
	@echo "FortiAIGate Chatbot — ECS Deployment"
	@echo ""
	@echo "One-time setup (run in order):"
	@echo "  make ecr-setup          Create ECR repos and CloudWatch log group"
	@echo "  make secrets-setup      Store API key and password in Secrets Manager"
	@echo "                          Required env vars: FORTIAIGATE_API_KEY, NGINX_PASSWORD"
	@echo "  make cluster-create     Create ECS cluster"
	@echo "  make service-create     Create ECS service (public Fargate task)"
	@echo "                          Override subnets: SUBNET_IDS=subnet-xxx,subnet-yyy"
	@echo ""
	@echo "Deploy (after each image change):"
	@echo "  make deploy             Build, push, re-register task def, and restart service"
	@echo "                          Required: FORTIAIGATE_BASE_URL=https://..."
	@echo ""
	@echo "Operations:"
	@echo "  make service-info       Show running task public IP"
	@echo "  make service-delete     Stop and delete the ECS service"
	@echo "  make cluster-delete     Delete the ECS cluster"
	@echo "  make teardown           Full teardown: service + cluster + security group"
	@echo "                          (ECR repos, secrets, and log group are kept)"
	@echo ""
	@echo "Current config:"
	@echo "  AWS_ACCOUNT_ID = $(AWS_ACCOUNT_ID)"
	@echo "  AWS_REGION     = $(AWS_REGION)"
	@echo "  CLUSTER_NAME   = $(CLUSTER_NAME)"
	@echo "  TAG            = $(TAG)"
	@echo ""

# ── One-time setup ────────────────────────────────────────────────────────────

iam-setup:
	@echo "Creating ecsTaskExecutionRole..."
	aws iam create-role \
		--role-name ecsTaskExecutionRole \
		--assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
	aws iam attach-role-policy \
		--role-name ecsTaskExecutionRole \
		--policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
	aws iam put-role-policy \
		--role-name ecsTaskExecutionRole \
		--policy-name FortiAIGateChatbotSecrets \
		--policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"secretsmanager:GetSecretValue","Resource":"arn:aws:secretsmanager:*:*:secret:fortiaigate-chatbot/*"}]}'
	@echo "Done."

ecr-setup:
	@echo "Creating ECR repositories..."
	aws ecr create-repository --repository-name $(FRONTEND_REPO) --region $(AWS_REGION) 2>/dev/null || true
	aws ecr create-repository --repository-name $(BACKEND_REPO)  --region $(AWS_REGION) 2>/dev/null || true
	@echo "Creating CloudWatch log group..."
	aws logs create-log-group --log-group-name /ecs/fortiaigate-chatbot --region $(AWS_REGION) 2>/dev/null || true
	@echo "Done."

secrets-setup:
	@[ -n "$(FORTIAIGATE_API_KEY)" ] || (echo "ERROR: FORTIAIGATE_API_KEY env var is required" && exit 1)
	@[ -n "$(NGINX_PASSWORD)" ]      || (echo "ERROR: NGINX_PASSWORD env var is required" && exit 1)
	@echo "Storing FortiAIGate API key in Secrets Manager..."
	aws secretsmanager create-secret \
		--name fortiaigate-chatbot/api-key \
		--secret-string "$(FORTIAIGATE_API_KEY)" \
		--region $(AWS_REGION) 2>/dev/null || \
	aws secretsmanager put-secret-value \
		--secret-id fortiaigate-chatbot/api-key \
		--secret-string "$(FORTIAIGATE_API_KEY)" \
		--region $(AWS_REGION)
	@echo "Storing Nginx password in Secrets Manager..."
	aws secretsmanager create-secret \
		--name fortiaigate-chatbot/nginx-password \
		--secret-string "$(NGINX_PASSWORD)" \
		--region $(AWS_REGION) 2>/dev/null || \
	aws secretsmanager put-secret-value \
		--secret-id fortiaigate-chatbot/nginx-password \
		--secret-string "$(NGINX_PASSWORD)" \
		--region $(AWS_REGION)
	@echo "Done."

cluster-create:
	@echo "Creating ECS cluster $(CLUSTER_NAME)..."
	aws ecs create-cluster \
		--cluster-name $(CLUSTER_NAME) \
		--region $(AWS_REGION)
	@echo "Done."

service-create: task-register
	@[ -n "$(SUBNET_IDS)" ] || (echo "ERROR: No subnets found. Set SUBNET_IDS=subnet-xxx,subnet-yyy" && exit 1)
	@echo "Creating security group..."
	$(eval SG_ID := $(shell aws ec2 create-security-group \
		--group-name $(SERVICE_NAME)-sg \
		--description "FortiAIGate chatbot" \
		--region $(AWS_REGION) \
		--query GroupId --output text))
	aws ec2 authorize-security-group-ingress \
		--group-id $(SG_ID) \
		--protocol tcp --port 80 --cidr 0.0.0.0/0 \
		--region $(AWS_REGION)
	aws ec2 authorize-security-group-egress \
		--group-id $(SG_ID) \
		--protocol tcp --port 443 --cidr 0.0.0.0/0 \
		--region $(AWS_REGION) 2>/dev/null || true
	@echo "Creating ECS service..."
	aws ecs create-service \
		--cluster $(CLUSTER_NAME) \
		--service-name $(SERVICE_NAME) \
		--task-definition fortiaigate-chatbot \
		--desired-count 1 \
		--launch-type FARGATE \
		--network-configuration "awsvpcConfiguration={subnets=[$(SUBNET_IDS)],securityGroups=[$(SG_ID)],assignPublicIp=ENABLED}" \
		--region $(AWS_REGION)
	@echo ""
	@echo "Service created. Run 'make service-info' in ~60s to get the public IP."

# ── Build and push ─────────────────────────────────────────────────────────────

login:
	aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(ECR_BASE)

build:
	docker build -t $(FRONTEND_IMAGE):$(TAG) ./frontend
	docker build -t $(BACKEND_IMAGE):$(TAG)  ./backend

push: login build
	docker push $(FRONTEND_IMAGE):$(TAG)
	docker push $(BACKEND_IMAGE):$(TAG)

# ── Task definition ────────────────────────────────────────────────────────────

task-register:
	@[ -n "$(FORTIAIGATE_BASE_URL)" ] || (echo "ERROR: FORTIAIGATE_BASE_URL is required, e.g. make task-register FORTIAIGATE_BASE_URL=https://..." && exit 1)
	@sed \
		-e 's|{{ACCOUNT_ID}}|$(AWS_ACCOUNT_ID)|g' \
		-e 's|{{REGION}}|$(AWS_REGION)|g' \
		-e 's|{{TAG}}|$(TAG)|g' \
		-e 's|{{FORTIAIGATE_BASE_URL}}|$(FORTIAIGATE_BASE_URL)|g' \
		-e 's|{{FORTIAIGATE_MODEL}}|$(FORTIAIGATE_MODEL)|g' \
		-e 's|{{NGINX_USERNAME}}|$(NGINX_USERNAME)|g' \
		infra/ecs-task-definition.json > /tmp/fortiaigate-chatbot-task-def.json
	aws ecs register-task-definition \
		--region $(AWS_REGION) \
		--cli-input-json file:///tmp/fortiaigate-chatbot-task-def.json
	@echo "Task definition registered."

# ── Deploy ─────────────────────────────────────────────────────────────────────

deploy: push task-register
	@echo "Updating ECS service..."
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--task-definition fortiaigate-chatbot \
		--force-new-deployment \
		--region $(AWS_REGION)
	@echo ""
	@echo "Deployment started. Run 'make service-info' in ~60s to get the public IP."

# ── Operations ─────────────────────────────────────────────────────────────────

service-info:
	$(eval TASK_ARN := $(shell aws ecs list-tasks \
		--cluster $(CLUSTER_NAME) \
		--service-name $(SERVICE_NAME) \
		--region $(AWS_REGION) \
		--query "taskArns[0]" --output text))
	@[ "$(TASK_ARN)" != "None" ] || (echo "No running tasks found." && exit 1)
	$(eval ENI_ID := $(shell aws ecs describe-tasks \
		--cluster $(CLUSTER_NAME) \
		--tasks $(TASK_ARN) \
		--region $(AWS_REGION) \
		--query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
		--output text))
	$(eval PUBLIC_IP := $(shell aws ec2 describe-network-interfaces \
		--network-interface-ids $(ENI_ID) \
		--region $(AWS_REGION) \
		--query "NetworkInterfaces[0].Association.PublicIp" \
		--output text))
	@echo ""
	@echo "Chatbot is running at: http://$(PUBLIC_IP)"
	@echo ""

service-delete:
	@echo "Scaling service to 0..."
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--desired-count 0 \
		--region $(AWS_REGION)
	@echo "Deleting service..."
	aws ecs delete-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--region $(AWS_REGION)
	@echo "Done."

cluster-delete:
	aws ecs delete-cluster \
		--cluster $(CLUSTER_NAME) \
		--region $(AWS_REGION)
	@echo "Cluster deleted."

teardown: service-delete cluster-delete
	@echo "Deleting security group..."
	$(eval SG_ID := $(shell aws ec2 describe-security-groups \
		--filters "Name=group-name,Values=$(SERVICE_NAME)-sg" \
		--region $(AWS_REGION) \
		--query "SecurityGroups[0].GroupId" --output text))
	@[ "$(SG_ID)" != "None" ] && \
		aws ec2 delete-security-group --group-id $(SG_ID) --region $(AWS_REGION) || true
	@echo "Teardown complete. ECR repos, Secrets Manager secrets, and log group retained."
	@echo "Run 'make cluster-create service-create' to redeploy."
