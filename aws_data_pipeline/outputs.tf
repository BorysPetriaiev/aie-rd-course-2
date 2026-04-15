output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.pdf_pipeline.id
}

output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.pdf_queue.url
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.pdf_extractor.function_name
}


