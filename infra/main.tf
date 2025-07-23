resource "aws_s3_bucket" "main" {
  bucket = "${var.bucket_name}-${random_integer.random.result}"

  tags = var.tags
}

resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_content_public" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.allow_content_public.json

  depends_on = [aws_s3_bucket_public_access_block.main]
}


data "aws_iam_policy_document" "allow_content_public" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.main.arn}/*",
    ]
  }
}

resource "aws_s3_object" "sync_remote_website_content" {
  for_each = fileset(var.sync_directories[0].local_source_directory, "**/*.*")

  bucket = aws_s3_bucket.main.id
  key    = "${var.sync_directories[0].s3_target_directory}/${each.value}"
  source = "${var.sync_directories[0].local_source_directory}/${each.value}"
  etag   = filemd5("${var.sync_directories[0].local_source_directory}/${each.value}")
  content_type = try(
    lookup(var.mime_types, split(".", each.value)[length(split(".", each.value)) - 1]),
    "binary/octet-stream"
  )

}

resource "random_integer" "random" {
  min = 1
  max = 50000
}

resource "aws_cloudfront_origin_access_identity" "origin_identity" {
  comment = "OAI for CloudFront to access S3 bucket"
}


data "aws_iam_policy_document" "cloudfront_read_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_identity.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_read" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.cloudfront_read_access.json
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.main.bucket_regional_domain_name
    origin_id   = "s3Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}
