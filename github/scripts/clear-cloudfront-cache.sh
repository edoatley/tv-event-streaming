#!/bin/bash
# This script invalidates the cloudfront distribution to pick up the changes

set -eou

STACK_NAME="uktv-event-streaming-app"
REGION="eu-west-2"

DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='WebsiteDistributionId'].OutputValue" \
  --output text \
  --region "$REGION")

if [ -z "$DISTRIBUTION_ID" ]; then
  echo "❌ Could not retrieve CloudFront Distribution ID from stack outputs. Aborting cache clear."
  exit 1
fi

aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --region "$REGION" | jq

echo "✅ CloudFront cache invalidation created. Changes will be live shortly."