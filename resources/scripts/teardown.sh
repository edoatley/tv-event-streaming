#!/bin/bash
# This script deploys changes to the existing AWS stack for rapid development and testing.

set -e

STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"

WEBSITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucket'].OutputValue" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null)

if [ -z "$WEBSITE_BUCKET" ] || [ "$WEBSITE_BUCKET" == "None" ]; then
    echo "⚠️ Could not find WebsiteBucket in stack outputs. Constructing name manually."
    WEBSITE_BUCKET="${STACK_NAME}-website-${ACCOUNT_ID}"
fi

echo "🧹 Emptying S3 bucket: s3://${WEBSITE_BUCKET}..."
if aws s3 ls "s3://${WEBSITE_BUCKET}" --profile "${PROFILE}" --region "$REGION" > /dev/null 2>&1; then
    aws s3 rm "s3://${WEBSITE_BUCKET}" --recursive --profile "${PROFILE}" --region "$REGION"
    aws s3api delete-bucket --bucket "${WEBSITE_BUCKET}" --profile "${PROFILE}" --region "$REGION"
    echo "✅ Bucket emptied and deleted to be safe."
else
    echo "✅ Bucket does not exist or is already gone. No action needed."
fi

echo "🗑️ Deleting stack..."
aws cloudformation delete-stack --stack-name "$STACK_NAME" --profile "$PROFILE" --region "$REGION"
echo "⏳ Waiting for stack to be deleted..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --profile "$PROFILE" --region "$REGION"
echo "✅ Stack deleted."