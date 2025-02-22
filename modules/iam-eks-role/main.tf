data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  role_name_condition = var.role_name != null ? var.role_name : "${var.role_name_prefix}*"
}

data "aws_eks_cluster" "main" {
  for_each = var.cluster_service_accounts

  name = each.key
}

data "aws_iam_policy_document" "assume_role_with_oidc" {
  dynamic "statement" {
    # https://aws.amazon.com/blogs/security/announcing-an-update-to-iam-role-trust-policy-behavior/
    for_each = var.allow_self_assume_role ? [1] : []

    content {
      sid     = "ExplicitSelfRoleAssumption"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${local.partition}:iam::${local.account_id}:role${var.role_path}${local.role_name_condition}"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.cluster_service_accounts

    content {
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type = "Federated"

        identifiers = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.main[statement.key].identity[0].oidc[0].issuer, "https://", "")}"
        ]
      }

      condition {
        test     = "StringEquals"
        variable = "${replace(data.aws_eks_cluster.main[statement.key].identity[0].oidc[0].issuer, "https://", "")}:sub"
        values   = [for s in statement.value : "system:serviceaccount:${s}"]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  assume_role_policy    = data.aws_iam_policy_document.assume_role_with_oidc.json
  description           = var.role_description
  force_detach_policies = var.force_detach_policies
  max_session_duration  = var.max_session_duration
  name                  = var.role_name
  name_prefix           = var.role_name_prefix
  path                  = var.role_path
  permissions_boundary  = var.role_permissions_boundary_arn
  tags                  = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for k, v in var.role_policy_arns : k => v if var.create_role }

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}
