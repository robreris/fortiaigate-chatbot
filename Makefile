export AWS_PAGER  =
include .env

## For cluster creation and testing, CLUSTER_NAME, SERVICE_NAME, TASK_FAMILY, and DOMAIN_NAME define a unique deployment.
## Changing all four (e.g. adding a common suffix) is sufficient to run a second isolated stack alongside an existing one.

AWS_REGION        ?= us-east-1
AWS_ACCOUNT_ID    ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
CLUSTER_NAME      ?= fortiaigate-chatbot
SERVICE_NAME      ?= fortiaigate-chatbot
TASK_FAMILY       ?= fortiaigate-chatbot
TAG               ?= latest

FRONTEND_REPO      = fortiaigate-chatbot-frontend
BACKEND_REPO       = fortiaigate-chatbot-backend
ECR_BASE           = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
FRONTEND_IMAGE     = $(ECR_BASE)/$(FRONTEND_REPO)
BACKEND_IMAGE      = $(ECR_BASE)/$(BACKEND_REPO)

# FortiAIGate settings — must be set for task-register and deploy
FORTIAIGATE_BASE_URL ?= https://fortiaigate.fortinetcloudcse.com
FORTIAIGATE_MODEL    ?= gpt-4o-mini
NGINX_USERNAME       ?= demo

# HTTPS / ALB settings — required for acm-setup, service-create, and teardown
DOMAIN_NAME      ?=
HOSTED_ZONE_ID   ?=
CERT_ARN         ?= $(shell aws acm list-certificates \
	--region $(AWS_REGION) \
	--query "CertificateSummaryList[?DomainName=='$(DOMAIN_NAME)'].CertificateArn | [0]" \
	--output text 2>/dev/null)

# ALB visibility — set ALB_SCHEME=internal for a private (non-internet-facing) ALB.
# When using an internal ALB:
#   - Set SUBNET_IDS to private subnet IDs (auto-detection only finds public/default subnets)
#   - Set ALB_INGRESS_SG to the FortiGate security group ID (preferred, e.g. sg-xxxxxxxxx)
#     OR set ALB_INGRESS_CIDR to a CIDR range if SG-based rules are not possible
#   - Set ASSIGN_PUBLIC_IP=DISABLED if tasks run in private subnets with a FortiGate/NAT egress
ALB_SCHEME       ?= internet-facing
ALB_INGRESS_CIDR ?= 0.0.0.0/0
ALB_INGRESS_SG   ?=
ASSIGN_PUBLIC_IP ?= ENABLED

# Subnets — auto-detects default VPC public subnets if not set.
# For internal ALBs, override with private subnet IDs: SUBNET_IDS=subnet-xxx,subnet-yyy
SUBNET_IDS ?= $(shell aws ec2 describe-subnets \
	--filters "Name=default-for-az,Values=true" \
	--region $(AWS_REGION) \
	--query "Subnets[*].SubnetId" \
	--output text 2>/dev/null | tr '\t' ',')

.PHONY: help iam-setup ecr-setup secrets-setup acm-setup login build push task-register \
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
	@echo "  make cluster-create     Create ECS cluster (persistent — survives teardown)"
	@echo "  make acm-setup          Request ACM certificate with Route 53 DNS validation"
	@echo "                          Required: DOMAIN_NAME=chatbot.example.com HOSTED_ZONE_ID=Z..."
	@echo ""
	@echo "Deploy (run after setup, or after teardown to reprovision):"
	@echo "  make service-create     Create ALB, ECS service, and Route 53 record"
	@echo "                          Required: DOMAIN_NAME=... HOSTED_ZONE_ID=..."
	@echo "                                    FORTIAIGATE_BASE_URL=https://..."
	@echo "                          Internal ALB: add ALB_SCHEME=internal"
	@echo "                                            ALB_INGRESS_SG=sg-xxx (FortiGate SG, preferred)"
	@echo "                                            ALB_INGRESS_CIDR=10.0.0.0/8 (fallback if no SG)"
	@echo "                                            ASSIGN_PUBLIC_IP=DISABLED"
	@echo "                                            SUBNET_IDS=subnet-xxx,subnet-yyy (private)"
	@echo "  make deploy             Build, push, re-register task def, restart service"
	@echo "                          Required: FORTIAIGATE_BASE_URL=https://..."
	@echo ""
	@echo "Operations:"
	@echo "  make service-info       Show HTTPS URL and ALB target health"
	@echo "  make teardown           Delete service, ALB, Route 53 record, SGs — keeps cluster"
	@echo "                          Required: DOMAIN_NAME=... HOSTED_ZONE_ID=..."
	@echo "  make service-delete     Delete ECS service only"
	@echo "  make cluster-delete     Delete ECS cluster (full infrastructure destroy)"
	@echo ""
	@echo "Current config:"
	@echo "  AWS_ACCOUNT_ID = $(AWS_ACCOUNT_ID)"
	@echo "  AWS_REGION     = $(AWS_REGION)"
	@echo "  CLUSTER_NAME   = $(CLUSTER_NAME)"
	@echo "  DOMAIN_NAME    = $(DOMAIN_NAME)"
	@echo "  TAG            = $(TAG)"
	@echo ""

# ── One-time setup ─────────────────────────────────────────────────────────────

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

secret-rotate: secrets-setup
	@echo "Force-redeploying service to pick up new secrets..."
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--force-new-deployment \
		--region $(AWS_REGION) > /dev/null
	@echo "Done."

cluster-create:
	@echo "Creating ECS cluster $(CLUSTER_NAME)..."
	aws ecs create-cluster \
		--cluster-name $(CLUSTER_NAME) \
		--region $(AWS_REGION) > /dev/null
	@echo "Done."

acm-setup:
	@[ -n "$(DOMAIN_NAME)" ]    || (echo "ERROR: DOMAIN_NAME is required, e.g. make acm-setup DOMAIN_NAME=chatbot.example.com HOSTED_ZONE_ID=Z..." && exit 1)
	@[ -n "$(HOSTED_ZONE_ID)" ] || (echo "ERROR: HOSTED_ZONE_ID is required" && exit 1)
	@existing=$$(aws acm list-certificates \
		--region $(AWS_REGION) \
		--query "CertificateSummaryList[?DomainName=='$(DOMAIN_NAME)'].CertificateArn | [0]" \
		--output text 2>/dev/null); \
	if [ -n "$$existing" ] && [ "$$existing" != "None" ]; then \
		echo "Certificate already exists for $(DOMAIN_NAME): $$existing"; \
		exit 0; \
	fi; \
	echo "Requesting ACM certificate for $(DOMAIN_NAME)..."; \
	CERT=$$(aws acm request-certificate \
		--domain-name $(DOMAIN_NAME) \
		--validation-method DNS \
		--region $(AWS_REGION) \
		--query CertificateArn --output text); \
	echo "Certificate ARN: $$CERT"; \
	echo "Waiting for validation records to be generated..."; \
	sleep 10; \
	NAME=$$(aws acm describe-certificate --certificate-arn $$CERT \
		--region $(AWS_REGION) \
		--query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text); \
	VALUE=$$(aws acm describe-certificate --certificate-arn $$CERT \
		--region $(AWS_REGION) \
		--query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' --output text); \
	echo "Adding DNS validation CNAME to Route 53: $$NAME"; \
	aws route53 change-resource-record-sets \
		--hosted-zone-id $(HOSTED_ZONE_ID) \
		--change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$$NAME\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$$VALUE\"}]}}]}" \
		> /dev/null; \
	echo "Waiting for certificate to be issued (may take 1-5 minutes)..."; \
	aws acm wait certificate-validated --certificate-arn $$CERT --region $(AWS_REGION); \
	echo ""; \
	echo "Certificate issued: $$CERT"

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
		-e 's|{{TASK_FAMILY}}|$(TASK_FAMILY)|g' \
		-e 's|{{FORTIAIGATE_BASE_URL}}|$(FORTIAIGATE_BASE_URL)|g' \
		-e 's|{{FORTIAIGATE_MODEL}}|$(FORTIAIGATE_MODEL)|g' \
		-e 's|{{NGINX_USERNAME}}|$(NGINX_USERNAME)|g' \
		infra/ecs-task-definition.json > /tmp/$(TASK_FAMILY)-task-def.json
	aws ecs register-task-definition \
		--region $(AWS_REGION) \
		--cli-input-json file:///tmp/$(TASK_FAMILY)-task-def.json > /dev/null
	@echo "Task definition registered."

# ── Deploy ─────────────────────────────────────────────────────────────────────

deploy: push task-register
	@echo "Updating ECS service..."
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--task-definition $(TASK_FAMILY) \
		--force-new-deployment \
		--region $(AWS_REGION) > /dev/null
	@echo ""
	@echo "Deployment started. Run 'make service-info' in ~90s to check target health."

# ── Operations ─────────────────────────────────────────────────────────────────

service-create: task-register
	@[ -n "$(SUBNET_IDS)" ]     || (echo "ERROR: No subnets found. Set SUBNET_IDS=subnet-xxx,subnet-yyy" && exit 1)
	@[ -n "$(DOMAIN_NAME)" ]    || (echo "ERROR: DOMAIN_NAME is required, e.g. DOMAIN_NAME=chatbot.example.com" && exit 1)
	@[ -n "$(HOSTED_ZONE_ID)" ] || (echo "ERROR: HOSTED_ZONE_ID is required" && exit 1)
	@CERT="$(CERT_ARN)"; \
	[ -n "$$CERT" ] && [ "$$CERT" != "None" ] || \
		{ echo "ERROR: No ACM certificate found for $(DOMAIN_NAME). Run: make acm-setup DOMAIN_NAME=$(DOMAIN_NAME) HOSTED_ZONE_ID=$(HOSTED_ZONE_ID)"; exit 1; }; \
	\
	echo "Looking up VPC..."; \
	VPC_ID=$$(aws ec2 describe-subnets \
		--subnet-ids $$(echo "$(SUBNET_IDS)" | cut -d',' -f1) \
		--region $(AWS_REGION) --query 'Subnets[0].VpcId' --output text); \
	\
	echo "Creating ALB security group..."; \
	aws ec2 create-security-group --group-name $(SERVICE_NAME)-alb-sg \
		--description "FortiAIGate chatbot ALB" --vpc-id $$VPC_ID \
		--region $(AWS_REGION) > /dev/null 2>&1 || true; \
	ALB_SG=$$(aws ec2 describe-security-groups \
		--filters "Name=group-name,Values=$(SERVICE_NAME)-alb-sg" "Name=vpc-id,Values=$$VPC_ID" \
		--region $(AWS_REGION) --query 'SecurityGroups[0].GroupId' --output text); \
	if [ -n "$(ALB_INGRESS_SG)" ]; then \
		aws ec2 authorize-security-group-ingress --group-id $$ALB_SG \
			--protocol tcp --port 80 --source-group $(ALB_INGRESS_SG) --region $(AWS_REGION) 2>/dev/null || true; \
		aws ec2 authorize-security-group-ingress --group-id $$ALB_SG \
			--protocol tcp --port 443 --source-group $(ALB_INGRESS_SG) --region $(AWS_REGION) 2>/dev/null || true; \
	else \
		aws ec2 authorize-security-group-ingress --group-id $$ALB_SG \
			--protocol tcp --port 80 --cidr $(ALB_INGRESS_CIDR) --region $(AWS_REGION) 2>/dev/null || true; \
		aws ec2 authorize-security-group-ingress --group-id $$ALB_SG \
			--protocol tcp --port 443 --cidr $(ALB_INGRESS_CIDR) --region $(AWS_REGION) 2>/dev/null || true; \
	fi; \
	\
	echo "Creating task security group..."; \
	aws ec2 create-security-group --group-name $(SERVICE_NAME)-sg \
		--description "FortiAIGate chatbot tasks" --vpc-id $$VPC_ID \
		--region $(AWS_REGION) > /dev/null 2>&1 || true; \
	TASK_SG=$$(aws ec2 describe-security-groups \
		--filters "Name=group-name,Values=$(SERVICE_NAME)-sg" "Name=vpc-id,Values=$$VPC_ID" \
		--region $(AWS_REGION) --query 'SecurityGroups[0].GroupId' --output text); \
	aws ec2 authorize-security-group-ingress --group-id $$TASK_SG \
		--protocol tcp --port 80 --source-group $$ALB_SG \
		--region $(AWS_REGION) 2>/dev/null || true; \
	\
	echo "Creating target group..."; \
	TG_ARN=$$(aws elbv2 describe-target-groups --names $(SERVICE_NAME)-tg \
		--region $(AWS_REGION) --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null); \
	if [ -z "$$TG_ARN" ] || [ "$$TG_ARN" = "None" ]; then \
		TG_ARN=$$(aws elbv2 create-target-group \
			--name $(SERVICE_NAME)-tg \
			--protocol HTTP --port 80 \
			--vpc-id $$VPC_ID \
			--target-type ip \
			--health-check-path / \
			--health-check-interval-seconds 30 \
			--healthy-threshold-count 2 \
			--matcher HttpCode=200-401 \
			--region $(AWS_REGION) \
			--query 'TargetGroups[0].TargetGroupArn' --output text); \
	fi; \
	\
	echo "Creating ALB..."; \
	ALB_ARN=$$(aws elbv2 describe-load-balancers --names $(SERVICE_NAME)-alb \
		--region $(AWS_REGION) --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null); \
	if [ -z "$$ALB_ARN" ] || [ "$$ALB_ARN" = "None" ]; then \
		SUBNET_LIST=$$(echo "$(SUBNET_IDS)" | tr ',' ' '); \
		ALB_ARN=$$(aws elbv2 create-load-balancer \
			--name $(SERVICE_NAME)-alb \
			--subnets $$SUBNET_LIST \
			--security-groups $$ALB_SG \
			--scheme $(ALB_SCHEME) \
			--region $(AWS_REGION) \
			--query 'LoadBalancers[0].LoadBalancerArn' --output text); \
	fi; \
	echo "Waiting for ALB to be active..."; \
	aws elbv2 wait load-balancer-available --load-balancer-arns $$ALB_ARN --region $(AWS_REGION); \
	ALB_DNS=$$(aws elbv2 describe-load-balancers --load-balancer-arns $$ALB_ARN \
		--region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text); \
	ALB_ZONE=$$(aws elbv2 describe-load-balancers --load-balancer-arns $$ALB_ARN \
		--region $(AWS_REGION) --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text); \
	\
	echo "Creating ALB listeners..."; \
	HTTPS_EXISTS=$$(aws elbv2 describe-listeners --load-balancer-arn $$ALB_ARN \
		--region $(AWS_REGION) --query 'Listeners[?Port==`443`].ListenerArn' --output text 2>/dev/null); \
	if [ -z "$$HTTPS_EXISTS" ] || [ "$$HTTPS_EXISTS" = "None" ]; then \
		aws elbv2 create-listener \
			--load-balancer-arn $$ALB_ARN --protocol HTTPS --port 443 \
			--certificates CertificateArn=$$CERT \
			--default-actions Type=forward,TargetGroupArn=$$TG_ARN \
			--region $(AWS_REGION) > /dev/null; \
		aws elbv2 create-listener \
			--load-balancer-arn $$ALB_ARN --protocol HTTP --port 80 \
			--default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
			--region $(AWS_REGION) > /dev/null; \
	fi; \
	\
	echo "Creating ECS service..."; \
	aws ecs create-service \
		--cluster $(CLUSTER_NAME) \
		--service-name $(SERVICE_NAME) \
		--task-definition $(TASK_FAMILY) \
		--desired-count 1 \
		--launch-type FARGATE \
		--network-configuration "awsvpcConfiguration={subnets=[$(SUBNET_IDS)],securityGroups=[$$TASK_SG],assignPublicIp=$(ASSIGN_PUBLIC_IP)}" \
		--load-balancers "targetGroupArn=$$TG_ARN,containerName=frontend,containerPort=80" \
		--health-check-grace-period-seconds 60 \
		--region $(AWS_REGION) > /dev/null; \
	\
	echo "Updating Route 53 record..."; \
	aws route53 change-resource-record-sets \
		--hosted-zone-id $(HOSTED_ZONE_ID) \
		--change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$(DOMAIN_NAME)\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"$$ALB_ZONE\",\"DNSName\":\"$$ALB_DNS\",\"EvaluateTargetHealth\":true}}}]}" \
		> /dev/null; \
	echo ""; \
	echo "Done. HTTPS endpoint: https://$(DOMAIN_NAME)"; \
	echo "Run 'make service-info' in ~90s to check target health."

service-info:
	@[ -n "$(DOMAIN_NAME)" ] || (echo "ERROR: DOMAIN_NAME is required" && exit 1)
	@echo ""
	@echo "Chatbot URL: https://$(DOMAIN_NAME)"
	@echo ""
	@TG_ARN=$$(aws elbv2 describe-target-groups --names $(SERVICE_NAME)-tg \
		--region $(AWS_REGION) --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null); \
	if [ -n "$$TG_ARN" ] && [ "$$TG_ARN" != "None" ]; then \
		echo "Target health:"; \
		aws elbv2 describe-target-health --target-group-arn $$TG_ARN \
			--region $(AWS_REGION) \
			--query 'TargetHealthDescriptions[*].{State:TargetHealth.State,Reason:TargetHealth.Reason}' \
			--output table; \
	else \
		echo "(no target group found)"; \
	fi; \
	echo ""

service-delete:
	@echo "Scaling service to 0..."
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--desired-count 0 \
		--region $(AWS_REGION) > /dev/null
	@echo "Waiting for tasks to stop (this may take ~60s)..."
	aws ecs wait services-stable \
		--cluster $(CLUSTER_NAME) \
		--services $(SERVICE_NAME) \
		--region $(AWS_REGION)
	@echo "Deleting service..."
	aws ecs delete-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--region $(AWS_REGION) > /dev/null
	@echo "Service deleted."

cluster-delete:
	aws ecs delete-cluster \
		--cluster $(CLUSTER_NAME) \
		--region $(AWS_REGION) > /dev/null
	@echo "Cluster deleted."

teardown:
	@[ -n "$(DOMAIN_NAME)" ]    || (echo "ERROR: DOMAIN_NAME is required" && exit 1)
	@[ -n "$(HOSTED_ZONE_ID)" ] || (echo "ERROR: HOSTED_ZONE_ID is required" && exit 1)
	@echo "Scaling ECS service to 0..."
	@aws ecs update-service --cluster $(CLUSTER_NAME) --service $(SERVICE_NAME) \
		--desired-count 0 --region $(AWS_REGION) > /dev/null 2>&1 || true
	@echo "Waiting for tasks to stop..."
	@aws ecs wait services-stable --cluster $(CLUSTER_NAME) --services $(SERVICE_NAME) \
		--region $(AWS_REGION) 2>/dev/null || true
	@echo "Deleting ECS service..."
	@aws ecs delete-service --cluster $(CLUSTER_NAME) --service $(SERVICE_NAME) \
		--region $(AWS_REGION) > /dev/null 2>&1 || true
	@echo "Waiting for all tasks to stop (service draining)..."
	@while [ -n "$$(aws ecs list-tasks --cluster $(CLUSTER_NAME) --family $(TASK_FAMILY) \
		--region $(AWS_REGION) --query 'taskArns' --output text 2>/dev/null)" ]; do \
		echo "  Tasks still running, retrying in 10s..."; \
		sleep 10; \
	done
	@echo "All tasks stopped."
	@echo "Removing Route 53 record and deleting ALB..."
	@ALB_ARN=$$(aws elbv2 describe-load-balancers --names $(SERVICE_NAME)-alb \
		--region $(AWS_REGION) --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null); \
	if [ -n "$$ALB_ARN" ] && [ "$$ALB_ARN" != "None" ]; then \
		ALB_DNS=$$(aws elbv2 describe-load-balancers --load-balancer-arns $$ALB_ARN \
			--region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text); \
		ALB_ZONE=$$(aws elbv2 describe-load-balancers --load-balancer-arns $$ALB_ARN \
			--region $(AWS_REGION) --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text); \
		aws route53 change-resource-record-sets \
			--hosted-zone-id $(HOSTED_ZONE_ID) \
			--change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"$(DOMAIN_NAME)\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"$$ALB_ZONE\",\"DNSName\":\"$$ALB_DNS\",\"EvaluateTargetHealth\":true}}}]}" \
			> /dev/null 2>&1 || true; \
		aws elbv2 delete-load-balancer --load-balancer-arn $$ALB_ARN --region $(AWS_REGION); \
		echo "Waiting for ALB to be deleted..."; \
		aws elbv2 wait load-balancers-deleted --load-balancer-arns $$ALB_ARN --region $(AWS_REGION); \
	fi
	@echo "Deleting target group..."
	@TG_ARN=$$(aws elbv2 describe-target-groups --names $(SERVICE_NAME)-tg \
		--region $(AWS_REGION) --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null); \
	[ -n "$$TG_ARN" ] && [ "$$TG_ARN" != "None" ] && \
		aws elbv2 delete-target-group --target-group-arn $$TG_ARN --region $(AWS_REGION) 2>/dev/null || true
	@echo "Deleting security groups..."
	@VPC_ID=$$(aws ec2 describe-subnets \
		--subnet-ids $$(echo "$(SUBNET_IDS)" | cut -d',' -f1) \
		--region $(AWS_REGION) --query 'Subnets[0].VpcId' --output text 2>/dev/null); \
	TASK_SG=$$(aws ec2 describe-security-groups \
		--filters "Name=group-name,Values=$(SERVICE_NAME)-sg" "Name=vpc-id,Values=$$VPC_ID" \
		--region $(AWS_REGION) --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null); \
	ALB_SG=$$(aws ec2 describe-security-groups \
		--filters "Name=group-name,Values=$(SERVICE_NAME)-alb-sg" "Name=vpc-id,Values=$$VPC_ID" \
		--region $(AWS_REGION) --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null); \
	[ -n "$$TASK_SG" ] && [ "$$TASK_SG" != "None" ] && \
		aws ec2 delete-security-group --group-id $$TASK_SG --region $(AWS_REGION) 2>/dev/null || true; \
	[ -n "$$ALB_SG" ] && [ "$$ALB_SG" != "None" ] && \
		aws ec2 delete-security-group --group-id $$ALB_SG --region $(AWS_REGION) 2>/dev/null || true
	@echo ""
	@echo "Teardown complete. Cluster '$(CLUSTER_NAME)' and ACM cert retained."
	@echo "Run 'make service-create DOMAIN_NAME=$(DOMAIN_NAME) HOSTED_ZONE_ID=$(HOSTED_ZONE_ID) FORTIAIGATE_BASE_URL=...' to redeploy."
