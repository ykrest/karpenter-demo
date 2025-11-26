# EKS Cluster with Karpenter Autoscaling

This repository contains Terraform code to deploy a production-ready Amazon EKS cluster (1.34) with Karpenter (1.8.1) for autoscaling, supporting both x86 and ARM64 (Graviton) instances with Spot instance capabilities.

## Deployment Instructions

### 1. Clone the Repository

```bash
git clone <repository-url>
cd eks-karpenter-demo-v2
```

### 2. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired settings.
# Repo example points to EKS 1.34 and matching Karpenter 1.8.1
```

### 3. Add AWS credentials (via export or profiles), Initialize Terraform, Deploy the Infrastructure

```bash
export AWS_ACCESS_KEY_ID="<your-key-here>"
export AWS_SECRET_ACCESS_KEY="<your-key-here>"
export AWS_DEFAULT_REGION=eu-west-1
#### or use aws profiles 
terraform init
terraform plan
terraform apply
```
The deployment will take approximately 15-20 minutes.

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
```

### 5. Verify Installation

```bash
# Check cluster access
kubectl get nodes

# Verify Karpenter is running
kubectl get pods -n karpenter

# Check Karpenter NodePools
kubectl get nodepools
```
## Using Karpenter with Different Architectures

Karpenter will automatically provision nodes based on pod requirements. This repository includes two NodePools:

1. **default**: Supports both x86 and ARM64 with Spot instances (on-demand fallback)
2. **graviton-spot**: ARM64-only with Spot instances for cost-optimized workloads

### Running Workloads on x86 Instances

Use `nodeSelector` to specify AMD64 architecture:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x86-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: x86-app
  template:
    metadata:
      labels:
        app: x86-app
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 1
            memory: 1Gi
```

Deploy:
```bash
kubectl apply -f examples/x86-deployment.yaml
```

### Running Workloads on Graviton (ARM64) Instances

Use `nodeSelector` to specify ARM64 architecture:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: graviton-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: graviton-app
  template:
    metadata:
      labels:
        app: graviton-app
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 1
            memory: 1Gi
```

Deploy:
```bash
kubectl apply -f examples/graviton-deployment.yaml
```

### Watching Karpenter Provision Nodes

```bash
# Watch Karpenter logs
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter

# Watch nodes being created
kubectl get nodes -w

# Check pending pods
kubectl get pods -A -o wide
```

## Cleanup

To destroy all resources:

```bash
# Delete all workloads first (important!)
kubectl delete deployments --all -A

# Wait for nodes to be deprovisioned
kubectl get nodes -w

# Destroy infrastructure
terraform destroy
```
