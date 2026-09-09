#!/bin/bash
# ==============================================================================
# create-backend.sh
# One-time setup: creates the S3 bucket + DynamoDB table that terraform/
# backend.tf points at for remote state. Run this BEFORE the first
# `terraform init` - Terraform's S3 backend does not create these for you.
#
# Usage:
#   ./create-backend.sh <bucket-name> <dynamodb-table-name> <aws-region>
#
# Example:
#   ./create-backend.sh your-terraform-state-bucket your-terraform-lock-table ap-south-1
# ==============================================================================
set -euo pipefail

BUCKET_NAME="ksys-k8s-terraform-state-bucket"
TABLE_NAME="ksys-k8s-terraform-state-DynamoDB"
REGION="ap-south-1"

echo ">>> Checking if bucket '$BUCKET_NAME' already exists"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket already exists - skipping creation, will still verify its settings below."
else
  echo ">>> Creating S3 bucket '$BUCKET_NAME' in $REGION"
  if [ "$REGION" = "us-east-1" ]; then
    # us-east-1 is the one region where you must NOT pass a LocationConstraint
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

echo ">>> Enabling versioning (lets you recover a previous state if something goes wrong)"
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo ">>> Enabling default encryption (AES256)"
aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo ">>> Blocking all public access on the bucket"
aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ">>> Checking if DynamoDB lock table '$TABLE_NAME' already exists"
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Table already exists - skipping creation."
else
 echo "Checking installed Terraform version..."
 if ! command -v terraform &> /dev/null; then
  echo "ERROR: terraform is not installed or not on PATH." >&2
  exit 1
  fi
  # Get the raw version string, e.g. "1.7.2" or "1.5.7"
TF_VERSION_RAW=$(terraform version -json | grep -o '"terraform_version": *"[^"]*"' | cut -d'"' -f4)
if [[ -z "$TF_VERSION_RAW" ]]; then
  echo "ERROR: could not determine Terraform version." >&2
  exit 1
fi
echo "Detected Terraform version: $TF_VERSION_RAW"
TF_MAJOR=$(echo "$TF_VERSION" | cut -d. -f1)
TF_MINOR=$(echo "$TF_VERSION" | cut -d. -f2)

if [[ "$TF_MAJOR" -eq 1 && "$TF_MINOR" -le 5 ]]; then
    CREATE_DYNAMODB=true
else
    CREATE_DYNAMODB=false
fi
  echo ">>> Creating DynamoDB table '$TABLE_NAME' for state locking"
  if [[ "$CREATE_DYNAMODB" == "true" ]]; then
      aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --region "$REGION" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST

      echo ">>> Waiting for table to become ACTIVE"
      aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"
  else
    echo "Terraform version detected as higher -> DynamoDB lock table will NOT be created."
  fi
fi

cat <<DONE

Backend is ready. Add this to terraform/backend.tf (copy from backend.tf.example):

terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "k8s-kubeadm/terraform.tfstate"
    region         = "$REGION"
    encrypt        = true
    dynamodb_table = "$TABLE_NAME"
  }
}

Then run: terraform init
DONE
