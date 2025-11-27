# Innovate Inc. Cloud Infrastructure Architecture Design

---

## 1. Cloud Environment Structure

### Multi-Account Strategy: 4 AWS Accounts

**Management Account**
- Centralized billing and organizational governance
- Service Control Policies enforcement
- No workloads deployed

**Development Account**
- Development and testing environments
- Lower security controls for productivity
- Non-production data only

**Staging Account**
- Pre-production testing and QA
- Production-equivalent configuration
- Integration and performance validation

**Production Account**
- Customer-facing live environment
- Strictest security controls
- High availability configuration

---

## 2. Network Design

### VPC Architecture

**Structure:** Multi-AZ deployment across three availability zones in us-east-1

**CIDR Allocation:** 10.0.0.0/16 providing 65,536 IP addresses

**Subnet Design (per Availability Zone):**

**Public Subnets** (10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24)
- Application Load Balancer deployment
- NAT Gateways for outbound connectivity
- Internet Gateway attached

**Private Application Subnets** (10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24)
- EKS worker nodes and application containers
- No direct internet access
- Outbound traffic via NAT Gateways

**Private Database Subnets** (10.0.20.0/24, 10.0.21.0/24, 10.0.22.0/24)
- RDS PostgreSQL instances
- Most restrictive access controls
- Isolated from internet

### Network Security Implementation

**Layer 1: Edge Protection**
- AWS WAF on Application Load Balancer
- AWS Shield for DDoS mitigation
- CloudFront CDN for static content delivery

**Layer 2: Network ACLs**
- Stateless firewall rules at subnet boundaries
- Default deny with explicit allow rules
- Separate ACLs per subnet type

**Layer 3: Security Groups**
- Stateful firewall rules for granular control
- ALB Security Group: accepts HTTPS (443) from internet, forwards to port 8080 on EKS nodes
- EKS Nodes Security Group: accepts traffic from ALB and EKS control plane only, can reach RDS on port 5432
- RDS Security Group: accepts PostgreSQL (5432) exclusively from EKS nodes

**Layer 4: Encryption & Monitoring**
- VPC Flow Logs capturing all network traffic
- AWS GuardDuty for intelligent threat detection
- CloudTrail for comprehensive API auditing

**Traffic Flow:** Users connect via CloudFront CDN, which routes through AWS WAF to the Application Load Balancer. The ALB distributes traffic to EKS pods in private subnets. Pods access RDS database in isolated database subnets. All egress traffic from private subnets routes through NAT Gateways.

---

## 3. Compute Platform

### Amazon EKS Configuration

**Cluster Architecture**

The EKS control plane is fully managed by AWS across three availability zones, running Kubernetes version 1.31. Both private and public endpoints are enabled, with the public endpoint restricted to CI/CD systems via IP allowlisting.

**Node Groups Strategy**

The primary application node group utilizes t3.medium instances (2 vCPU, 4GB RAM) with autoscaling configured between 3 and 10 nodes. These nodes run Amazon Linux 2023 EKS-optimized AMIs with 50GB gp3 EBS volumes and mandatory IMDSv2 for enhanced security. Future expansion includes a high-memory node group using r6i.large instances for memory-intensive workloads, deployed with appropriate node taints.

**Scaling Configuration**

Horizontal Pod Autoscaler targets 70% CPU and 80% memory utilization, scaling backend pods from 3 to 50 replicas and frontend pods from 2 to 20 replicas. The Node Autoscaler (Karpenter) manages node provisioning based on unscheduled pods.

**Resource Allocation**

Backend Flask pods request 100 millicores CPU and 256MB memory, with limits at 500 millicores and 512MB. Frontend React/Nginx pods request 50 millicores and 128MB memory, limited to 200 millicores and 256MB. This ensures predictable performance whilst maximizing cluster utilization.

### Containerization Strategy

**Image Building Process**

Docker multi-stage builds. Backend images start from python:3.11-slim base, whilst frontend uses node:18-alpine for building and nginx:alpine for runtime. All images run as non-root users for security compliance.

**Container Registry**

Amazon ECR hosts private registries per AWS account with automated vulnerability scanning on every push. 

**Deployment Process**

The CI/CD pipeline executes through GitHub Actions, progressing through build, test, security scanning (Trivy), ECR push, and deployment stages. ArgoCD implements GitOps methodology, maintaining Git repositories as the single source of truth for all Kubernetes manifests. Deployments utilize rolling updates for zero-downtime releases, with blue-green and canary strategies available for major releases.

---

## 4. Database

### Amazon RDS for PostgreSQL. Why?
- Eliminates operational overhead for patching, backups, and maintenance 
- Multi-AZ deployment with automatic failover

**Instance Configuration**

The initial deployment uses db.t4g.medium instances running PostgreSQL 16.1. Storage begins at 100GB automatically scaling to 1TB as required.  

**High Availability Architecture**

Multi-AZ deployment places the primary instance in us-east-1a with a synchronous standby replica in us-east-1b. An asynchronous read replica in us-east-1c handles read-scaling requirements. 

**Backup Strategy**

Automated daily snapshots retain for thirty days with five-minute point-in-time recovery capability. 

**Disaster Recovery**

Recovery Time Objective is one hour with Recovery Point Objective of five minutes. The primary DR mechanism is Multi-AZ automatic failover (1-2 minutes, zero data loss). Point-in-time restore from automated backups provides thirty-minute recovery with five-minute data loss. Quarterly DR drills validate procedures.

---
