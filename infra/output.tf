output "cloudfront_url" {
  description = "URL CloudFront"
  value       = aws_cloudfront_distribution.cdn.domain_name
}
