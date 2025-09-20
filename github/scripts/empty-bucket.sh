#!/bin/bash
# This script empties the website bucket to allow teardown of the stack

set -eou


WEBSITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucket'].OutputValue" --output text --region "$REGION" 2>/dev/null)

if [ -z "$WEBSITE_BUCKET" ] || [ "$WEBSITE_BUCKET" == "None" ]; then
  echo "⚠️ Could not find WebsiteBucket in stack outputs. Constructing name manually."
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
  WEBSITE_BUCKET="${STACK_NAME}-website-${ACCOUNT_ID}"
fi

echo "🧹 Emptying S3 bucket: s3://${WEBSITE_BUCKET}..."
if aws s3 ls "s3://${WEBSITE_BUCKET}" --region "$REGION" > /dev/null 2>&1; then
  aws s3 rm "s3://${WEBSITE_BUCKET}" --recursive --region "$REGION"
  aws s3api delete-bucket --bucket "${WEBSITE_BUCKET}" --region "$REGION"
  echo "✅ Bucket emptied and deleted to be safe."
else
  echo "✅ Bucket does not exist or is already gone. No action needed."
fi