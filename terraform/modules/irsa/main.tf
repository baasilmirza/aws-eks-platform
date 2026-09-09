locals {
  # oidc_provider_arn = arn:aws:iam::<acct>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<id>
  issuer = replace(var.oidc_provider_arn, "arn:aws:iam::${var.account_id}:oidc-provider/", "")
  bucket = "baasilmirza-eks-irsa-demo-${var.account_id}"
}

#checkov:skip=CKV_AWS_18:Demo bucket holds no sensitive data; access logging adds cost for a same-day-destroyed resource
#checkov:skip=CKV_AWS_144:Demo bucket intentionally single-region
#checkov:skip=CKV2_AWS_62:No event notifications needed for a demo bucket
resource "aws_s3_bucket" "demo" {
  bucket        = local.bucket
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }
  }
}

data "aws_iam_policy_document" "s3_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]
    resources = [
      aws_s3_bucket.demo.arn,
      "${aws_s3_bucket.demo.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "s3_read" {
  name        = "eks-irsa-demo-s3-read"
  description = "Least-privilege read access to the IRSA demo bucket"
  policy      = data.aws_iam_policy_document.s3_read.json
  tags        = var.tags
}

resource "aws_iam_role" "this" {
  name               = "eks-irsa-demo"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_read" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.s3_read.arn
}
