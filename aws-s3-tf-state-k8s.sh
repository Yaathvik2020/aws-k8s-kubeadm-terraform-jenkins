### Step 1: Create the S3 bucket

 aws s3api create-bucket \
  --bucket ksys-k8s-terraform-state-bucket \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
  
 ### Step 2: Enable versioning (recovery safety net)
 
 aws s3api put-bucket-versioning \
  --bucket ksys-k8s-terraform-state-bucket \
  --versioning-configuration Status=Enabled
  
 ### Step 4: Grant your  mechine IAM user access to both
 
 cat > state-backend-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::ksys-k8s-terraform-state-bucket",
        "arn:aws:s3:::ksys-k8s-terraform-state-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/terraform-state-lock"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name JenkinsUser  \
  --policy-name terraform-state-access \
  --policy-document file://state-backend-policy.json
  
  
  
aws sts get-caller-identity