variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for all resource names"
  type        = string
  default     = "pdf-pipeline"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
  default = "pdf-pipeline-bucket-aie-rd"
}

variable "sample_pdf_path" {
  description = "Local path to the PDF file that will be uploaded to uploads/"
  type        = string
  default     = "file-example_PDF_500_kB.pdf"
}
