#!/bin/bash
# This script deploys the CloudFormation stack for the GitHub Actions IAM Role.

set -e
set -o pipefail

STACK_NAME="tv-event-streaming-gh-actions"
PROFILE="streaming"
REGION="eu-west-2"

# Determine the script's directory to reliably locate the template file, making the script runnable from any location.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
TEMPLATE_FILE_PATH=$(realpath "${SCRIPT_DIR}/../../github/cloudformation/gh-actions-role.yaml")

if [ ! -f "${TEMPLATE_FILE_PATH}" ]; then
    echo "❌ Template file not found at: ${TEMPLATE_FILE_PATH}"
    exit 1
fi

########################################################################################################################
echo "🚀 Step 1: Refreshing AWS SSO session for profile: ${PROFILE}..."
########################################################################################################################
echo "🔎 Checking AWS SSO session for profile: ${PROFILE}..."
if ! aws sts get-caller-identity --profile "${PROFILE}" --region "${REGION}" > /dev/null 2>&1; then
   echo "⚠️ AWS SSO session expired or not found for profile '${PROFILE}'. Attempting to refresh..."
   aws sso login --profile "${PROFILE}"

   if ! aws sts get-caller-identity --profile "${PROFILE}" --region "${REGION}" > /dev/null 2>&1; then
       echo "❌ AWS login failed. Please check your configuration. Aborting."
       exit 1
   fi
   echo "✅ AWS login successful."
else
   echo "✅ AWS SSO session is active."
fi

########################################################################################################################
echo "🚀 Step 2: Validate the CloudFormation template..."
########################################################################################################################
echo "🔎 Validating template: ${TEMPLATE_FILE_PATH}"
aws cloudformation validate-template \
  --template-body "file://${TEMPLATE_FILE_PATH}" \
  --profile "${PROFILE}" \
  --region "${REGION}" | jq

echo "✅ Template is valid."

########################################################################################################################
echo "🚀 Step 3: Deploying the stack: ${STACK_NAME}..."
########################################################################################################################
# The IAM OIDC provider is a global resource, but we deploy it to a specific region.
# This is fine, as it only needs to be created once per account.
# The deploy command will create or update the stack.
# CAPABILITY_NAMED_IAM is required because the template creates an IAM role with a custom name.
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE_PATH}" \
  --stack-name "${STACK_NAME}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --profile "${PROFILE}" \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

echo "✅ Stack deployment complete for stack: ${STACK_NAME}"

########################################################################################################################
echo "🚀 Step 4: Fetching stack outputs..."
########################################################################################################################
ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='GitHubActionsRoleArn'].OutputValue" \
  --output text \
  --profile "${PROFILE}" \
  --region "${REGION}")

if [ -z "${ROLE_ARN}" ]; then
    echo "❌ Could not retrieve the GitHubActionsRoleArn from the stack outputs. Please check the AWS Console."
    exit 1
fi

echo ""
echo "🎉 Success! The IAM Role for GitHub Actions has been deployed."
echo "➡️  Role ARN: ${ROLE_ARN}"
echo ""
echo "Next steps:"
echo "1. Go to your GitHub repository settings: https://github.com/edoatley/tv-event-streaming/settings/secrets/actions"
echo "2. Create a new repository secret with the following details:"
echo "   - Name: AWS_ROLE_ARN"
echo "   - Value: ${ROLE_ARN}"
echo ""
echo "This will allow your GitHub Actions workflows to securely authenticate with AWS."