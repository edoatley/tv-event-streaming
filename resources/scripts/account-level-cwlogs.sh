#!/bin/bash
# Step 1: Create the IAM Role

# Create trust policy file
cat > /tmp/apigateway-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name APIGatewayCloudWatchLogsRole \
  --assume-role-policy-document file:///tmp/apigateway-trust-policy.json \
  --profile streaming

# Step 2: Attach the CloudWatch Policy

## Attach policy
aws iam attach-role-policy \
  --role-name APIGatewayCloudWatchLogsRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs \
  --profile streaming


# Step 3: Set the Role in API Gateway Account Settings

# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile streaming)
aws apigateway update-account \
  --patch-operations  '[{"op":"replace","path":"/cloudwatchRoleArn","value":"arn:aws:iam::'${ACCOUNT_ID}':role/APIGatewayCloudWatchLogsRole"}]' \
  --profile streaming

# Replace with your actual API ID and stage name
#API_ID="your-api-id"
#STAGE_NAME="your-stage-name"
#
### Step 4: Now Enable Logging on Your API
#
#aws apigateway update-stage \
#  --rest-api-id $API_ID \
#  --stage-name $STAGE_NAME \
#  --patch-operations op=replace,path=/*/logging/loglevel,value=INFO \
#  --patch-operations op=replace,path=/*/logging/dataTrace,value=true

