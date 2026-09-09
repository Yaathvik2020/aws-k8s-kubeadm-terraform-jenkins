#!/bin/bash
# ==============================================================================
# delete-backend.sh
# Tears down the S3 bucket + DynamoDB table created by create-backend.sh.
#
# IMPORTANT: run this ONLY after `terraform destroy` has already removed the
# actual cluster infrastructure, and only once you're truly done - deleting
# this bucket destroys your Terraform state history permanently. Because
# versioning is enabled, a normal bucket delete will fail until every
# version and delete-marker is removed first - this script does that for you.
#
# Usage:
#   ./delete-backend.sh <bucket-name> <dynamodb-table-name> <aws-region> [--force]
#
# Example:
#   ./delete-backend.sh your-terraform-state-bucket your-terraform-lock-table ap-south-1
# ==============================================================================
set -euo pipefail

BUCKET_NAME="${1:?Usage: $0 'ksys-k8s-terraform-state-bucket' 'ksys-k8s-terraform-state-DynamoDB' 'ap-south-1' [--force]}"
TABLE_NAME="${2:?Usage: $0 'ksys-k8s-terraform-state-bucket' 'ksys-k8s-terraform-state-DynamoDB' 'ap-south-1' [--force]}"
REGION="${3:?Usage: $0 'ksys-k8s-terraform-state-bucket' 'ksys-k8s-terraform-state-DynamoDB' 'ap-south-1' [--force]}"
FORCE="${4:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: this script needs 'jq' to parse S3 version listings. Install it first:"
  echo "  Ubuntu/Debian: sudo apt-get install -y jq"
  echo "  macOS:         brew install jq"
  exit 1
fi

if [ "$FORCE" != "--force" ]; then
  echo "This will PERMANENTLY delete:"
  echo "  - S3 bucket:      $BUCKET_NAME (including ALL state history/versions)"
  echo "  - DynamoDB table: $TABLE_NAME"
  echo ""
  read -r -p "Type the bucket name to confirm deletion: " CONFIRM
  if [ "$CONFIRM" != "$BUCKET_NAME" ]; then
    echo "Confirmation did not match - aborting, nothing was deleted."
    exit 1
  fi
fi

echo ">>> Emptying all object versions and delete markers from '$BUCKET_NAME'"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  # Versioned buckets refuse a plain delete until every version is gone.
  aws s3api list-object-versions --bucket "$BUCKET_NAME" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json > /tmp/versions.json
  if [ "$(jq '.Objects | length' /tmp/versions.json)" -gt 0 ]; then
    aws s3api delete-objects --bucket "$BUCKET_NAME" --delete file:///tmp/versions.json
  fi

  aws s3api list-object-versions --bucket "$BUCKET_NAME" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json > /tmp/markers.json
  if [ "$(jq '.Objects | length' /tmp/markers.json)" -gt 0 ]; then
    aws s3api delete-objects --bucket "$BUCKET_NAME" --delete file:///tmp/markers.json
  fi
  rm -f /tmp/versions.json /tmp/markers.json

  echo ">>> Deleting bucket '$BUCKET_NAME'"
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION"
else
  echo "Bucket '$BUCKET_NAME' not found - skipping."
fi

echo ">>> Deleting DynamoDB table '$TABLE_NAME'"
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null
  aws dynamodb wait table-not-exists --table-name "$TABLE_NAME" --region "$REGION"
else
  echo "Table '$TABLE_NAME' not found - skipping."
fi

echo ">>> Backend resources deleted."
