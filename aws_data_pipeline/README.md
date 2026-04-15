# AWS PDF Text Extraction Pipeline

Terraform infrastructure for automatic text extraction from PDF files using AWS S3, SQS, and Lambda.

## Architecture

```
S3 bucket (uploads/*.pdf)
    └─► SQS queue ──► Lambda (pypdf) ──► S3 bucket (extracted/*.txt)
              ▲
         S3 Event Notification
```

1. A PDF is uploaded to S3 under the `uploads/` prefix
2. S3 sends an `ObjectCreated` event to the SQS queue
3. SQS triggers the Lambda function
4. Lambda downloads the PDF, extracts text via `pypdf`, and saves the result under `extracted/`

## Project Structure

```
aws_data_pipeline/
├── main.tf                       # all AWS resources
├── variables.tf                  # input variables
├── outputs.tf                    # output values
├── file-example_PDF_500_kB.pdf   # sample PDF for testing
└── lambda/
    ├── extract_text.py           # Lambda function code
    └── requirements.txt          # dependencies (pypdf)
└── screenshots/                  # screnshots(aws infrastructer)   
```

## AWS Resources

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket` | Stores input PDFs and extracted text files |
| `aws_sqs_queue` | Event queue for file upload notifications |
| `aws_sqs_queue` (DLQ) | Dead Letter Queue for failed messages |
| `aws_lambda_function` | Text extraction function |
| `aws_lambda_layer_version` | Layer containing the `pypdf` library |
| `aws_cloudwatch_log_group` | Lambda logs (removed on `terraform destroy`) |
| `aws_iam_role` | Least-privilege IAM role for Lambda |

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) with configured credentials
- Python + `pip` (used locally to build the Lambda layer)

## Deployment

### 1. Configure AWS credentials

```bash
aws configure 
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
```

### 2. Initialize Terraform

```bash
cd aws_data_pipeline
terraform init
```

### 3. Apply the infrastructure

```bash
terraform apply
```

Terraform will:
- Build the `pypdf` layer locally via `pip`
- Create all AWS resources
- Upload the sample PDF to `uploads/`

### 4. Verify the result

```bash
# List extracted files
aws s3 ls s3://<bucket-name>/extracted/

# Print extracted text
aws s3 cp s3://<bucket-name>/extracted/file-example_PDF_500_kB.txt -

# Stream Lambda logs
aws logs tail /aws/lambda/pdf-pipeline-pdf-extractor --follow
```

### 5. Tear down

```bash
terraform destroy
```

This removes all resources including the S3 bucket (and its contents), SQS queues, Lambda, IAM role, and CloudWatch log group.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `project_name` | `pdf-pipeline` | Prefix used for all resource names |
| `bucket_name` | `pdf-pipeline-bucket-aie-rd` | Globally unique S3 bucket name |
| `sample_pdf_path` | `file-example_PDF_500_kB.pdf` | Path to the sample PDF file |

Override variables via flag or a `.tfvars` file:

```bash
terraform apply -var="bucket_name=my-unique-bucket-name"
```

## Uploading a New PDF Manually

```bash
aws s3 cp my-document.pdf s3://<bucket-name>/uploads/my-document.pdf
```

Lambda will trigger automatically and the extracted text will appear at `s3://<bucket-name>/extracted/my-document.txt`.
