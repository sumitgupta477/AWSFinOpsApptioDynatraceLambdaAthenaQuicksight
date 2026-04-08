/*output "role_arn" {
  value = aws_iam_role.cloudability_role.arn
}*/

output "s3_bucket" {
  value = aws_s3_bucket.cur_bucket.bucket
} 
