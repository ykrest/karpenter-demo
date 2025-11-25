.PHONY: help init plan apply destroy configure-kubectl logs-karpenter status deploy-x86 deploy-graviton deploy-mixed clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform
	terraform init

plan: ## Run Terraform plan
	terraform plan

apply: ## Apply Terraform configuration
	terraform apply

destroy: ## Destroy all Terraform resources
	@echo "WARNING: This will destroy all resources!"
	@echo "Make sure to delete all workloads first with: make clean"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		terraform destroy -auto-approve; \
	fi

configure-kubectl: ## Configure kubectl to connect to the EKS cluster
	@aws eks update-kubeconfig --region $$(terraform output -raw region) --name $$(terraform output -raw cluster_name)
	@echo "kubectl configured successfully!"
	@kubectl get nodes

logs-karpenter: ## Tail Karpenter logs
	kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter

status: ## Show cluster and Karpenter status
	@echo "=== Cluster Info ==="
	kubectl cluster-info
	@echo ""
	@echo "=== Nodes ==="
	kubectl get nodes -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type
	@echo ""
	@echo "=== NodePools ==="
	kubectl get nodepools
	@echo ""
	@echo "=== EC2NodeClasses ==="
	kubectl get ec2nodeclasses
	@echo ""
	@echo "=== Karpenter Pods ==="
	kubectl get pods -n karpenter

deploy-x86: ## Deploy example x86 application
	kubectl apply -f deployment/x86-deployment.yaml
	@echo "Deployed x86 application. Watch with: kubectl get pods -l app=x86-nginx -w"

deploy-graviton: ## Deploy example Graviton application
	kubectl apply -f deployment/graviton-deployment.yaml
	@echo "Deployed Graviton application. Watch with: kubectl get pods -l app=graviton-nginx -w"

deploy-mixed: ## Deploy mixed architecture applications
	kubectl apply -f deployment/mixed-deployment.yaml
	@echo "Deployed mixed architecture applications. Watch with: kubectl get pods -w"

clean: ## Delete all example deployments
	-kubectl delete -f deployment/x86-deployment.yaml 2>/dev/null || true
	-kubectl delete -f deployment/graviton-deployment.yaml 2>/dev/null || true
	-kubectl delete -f deployment/mixed-deployment.yaml 2>/dev/null || true
	@echo "Waiting for pods to terminate..."
	@sleep 10
	@echo "Example deployments cleaned up"

watch-nodes: ## Watch nodes being created/destroyed
	watch -n 2 "kubectl get nodes -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type,AGE:.metadata.creationTimestamp"

watch-pods: ## Watch pods status
	kubectl get pods -A -o wide -w

describe-nodepool: ## Describe the default NodePool
	kubectl describe nodepool default

version: ## Show versions
	@echo "Terraform: $$(terraform version -json | jq -r '.terraform_version')"
	@echo "kubectl: $$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
	@echo "AWS CLI: $$(aws --version)"
	@echo ""
	@echo "Cluster version: $$(kubectl version -o json | jq -r '.serverVersion.gitVersion')"
