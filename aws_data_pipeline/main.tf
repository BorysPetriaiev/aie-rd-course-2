terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 

resource "aws_s3_bucket" "pdf_pipeline" {
  bucket        = var.bucket_name
  force_destroy = true
}


resource "aws_s3_bucket_public_access_block" "pdf_pipeline" {
  bucket                  = aws_s3_bucket.pdf_pipeline.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SQS

resource "aws_sqs_queue" "pdf_queue" {
  name                       = "${var.project_name}-pdf-queue"
  visibility_timeout_seconds = 300  
  message_retention_seconds  = 86400 
}

resource "aws_sqs_queue" "pdf_dlq" {
  name                      = "${var.project_name}-pdf-dlq"
  message_retention_seconds = 86400 # 7 days
}

resource "aws_sqs_queue_redrive_policy" "pdf_queue" {
  queue_url = aws_sqs_queue.pdf_queue.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pdf_dlq.arn
    maxReceiveCount     = 3
  })
}

# Allow S3 to send messages to the SQS queue
resource "aws_sqs_queue_policy" "pdf_queue" {
  queue_url = aws_sqs_queue.pdf_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3SendMessage"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.pdf_queue.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.pdf_pipeline.arn
        }
      }
    }]
  })
}

# S3 → SQS 
resource "aws_s3_bucket_notification" "pdf_upload" {
  bucket = aws_s3_bucket.pdf_pipeline.id

  queue {
    id            = "pdf-upload-notification"
    queue_arn     = aws_sqs_queue.pdf_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
    filter_suffix = ".pdf"
  }

  depends_on = [aws_sqs_queue_policy.pdf_queue]
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.pdf_pipeline.arn}/*"
      },
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.pdf_queue.arn
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda layer with pypdf 

resource "null_resource" "build_layer" {
  triggers = {
    requirements = filemd5("${path.module}/lambda/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/.build/layer
      mkdir -p ${path.module}/.build/layer/python
      pip install \
        --quiet \
        --platform manylinux2014_x86_64 \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all: \
        --target ${path.module}/.build/layer/python \
        -r ${path.module}/lambda/requirements.txt
      cd ${path.module}/.build/layer && zip -r ../pypdf_layer.zip python
    EOT
  }
}

resource "aws_lambda_layer_version" "pypdf" {
  filename            = "${path.module}/.build/pypdf_layer.zip"
  layer_name          = "${var.project_name}-pypdf"
  compatible_runtimes = ["python3.12"]

  depends_on = [null_resource.build_layer]
}

# Lambda

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/extract_text.py"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_lambda_function" "pdf_extractor" {
  function_name = "${var.project_name}-pdf-extractor"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "extract_text.handler"
  timeout       = 120
  memory_size   = 512

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers = [aws_lambda_layer_version.pypdf.arn]

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.pdf_pipeline.id
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.pdf_extractor.function_name}"
  retention_in_days = 7
}

# SQS → Lambda 
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.pdf_queue.arn
  function_name    = aws_lambda_function.pdf_extractor.arn
  batch_size       = 1
  enabled          = true
}
