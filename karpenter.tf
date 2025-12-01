# Install Karpenter release for CRDs
resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_version
  namespace  = "karpenter"
  create_namespace = true
}


# Install Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = false
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart            = "karpenter"
  version          = var.karpenter_version
  wait             = true

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.eks.cluster_name}
      featureGates:
        StaticCapacity: false
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter_irsa.iam_role_arn}
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
    nodeSelector:
      role: karpenter-controller
    replicas: 2
    EOT
  ]

  depends_on = [
    kubectl_manifest.karpenter_namespace,
    module.karpenter_irsa,
    aws_sqs_queue.karpenter_interruption,
    aws_sqs_queue_policy.karpenter_interruption,
    aws_cloudwatch_event_target.karpenter_interruption,
    aws_iam_role_policy_attachment.karpenter_interruption,
    aws_iam_role_policy_attachment.karpenter_instance_profile,
    helm_release.karpenter_crd
  ]
}

# Default NodePool - supports both x86 and ARM64
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        metadata:
          labels:
            intent: apps
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64", "arm64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand", "spot"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["5"]
      limits:
        cpu: 1000
        memory: 1000Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# ARM64-specific NodePool for Graviton workloads
resource "kubectl_manifest" "karpenter_node_pool_graviton" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: graviton-spot
    spec:
      template:
        metadata:
          labels:
            intent: graviton
            arch: arm64
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["arm64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand", "spot"]
            - key: karpenter.k8s.aws/instance-family
              operator: In
              values: ["m7g", "c7g", "r7g", "m6g", "c6g", "r6g"]
      limits:
        cpu: 1000
        memory: 1000Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# EC2NodeClass - defines the node template
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${aws_iam_role.karpenter_node.name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      amiFamily: AL2023
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
            encrypted: true
            deleteOnTermination: true
      metadataOptions:
        httpEndpoint: enabled
        httpProtocolIPv6: disabled
        httpPutResponseHopLimit: 2
        httpTokens: required
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
        ManagedBy: Karpenter
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}
