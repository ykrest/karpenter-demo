resource "aws_sqs_queue" "karpenter_interruption" {
  name = var.cluster_name

  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  name        = "${local.name}-karpenter-interruption"
  description = "Send EC2 interruption and rebalance events to Karpenter SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = [
      "EC2 Spot Instance Interruption Warning",
      "EC2 Instance Rebalance Recommendation",
      "EC2 Instance State-change Notification"
    ]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  rule = aws_cloudwatch_event_rule.karpenter_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

data "aws_iam_policy_document" "karpenter_interruption" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]

    resources = [
      aws_sqs_queue.karpenter_interruption.arn
    ]
  }
}

resource "aws_iam_policy" "karpenter_interruption" {
  name   = "${local.name}-karpenter-interruption"
  policy = data.aws_iam_policy_document.karpenter_interruption.json
}

resource "aws_iam_role_policy_attachment" "karpenter_interruption" {
  role       = module.karpenter_irsa.iam_role_name
  policy_arn = aws_iam_policy.karpenter_interruption.arn
}

data "aws_iam_policy_document" "karpenter_instance_profile" {
  statement {
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile"
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${local.name}*"
    ]
  }

  statement {
    actions = [
      "iam:PassRole"
    ]

    resources = [
      aws_iam_role.karpenter_node.arn
    ]
  }
}

resource "aws_iam_policy" "karpenter_instance_profile" {
  name   = "${local.name}-karpenter-instance-profile"
  policy = data.aws_iam_policy_document.karpenter_instance_profile.json
}

resource "aws_iam_role_policy_attachment" "karpenter_instance_profile" {
  role       = module.karpenter_irsa.iam_role_name
  policy_arn = aws_iam_policy.karpenter_instance_profile.arn
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter_interruption.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.karpenter_interruption.arn
          }
        }
      }
    ]
  })
}
