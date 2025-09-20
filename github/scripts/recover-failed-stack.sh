#!/bin/bash
# This script cleans up a failed stack

set -eou

echo "🚀 Checking stack status and cleaning up if necessary..."
########################################################################################################################
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text --region "$REGION" 2>/dev/null || echo "DOES_NOT_EXIST")
echo "  - Stack status: $STACK_STATUS"


if [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" == "DELETE_FAILED" ]; then
    echo "🗑️ Stack is in a recoverable but failed state ($STACK_STATUS). Cleaning up before deployment..."

    echo "Calling empty bucket"
    bash ./github/scripts/empty-bucket.sh

    echo "🗑️ Deleting stack..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
    echo "⏳ Waiting for stack to be deleted..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    echo "✅ Stack deleted."
elif [ "$STACK_STATUS" != "DOES_NOT_EXIST" ] && [ "$STACK_STATUS" != "CREATE_COMPLETE" ] && [ "$STACK_STATUS" != "UPDATE_COMPLETE" ] && [ "$STACK_STATUS" != "UPDATE_ROLLBACK_COMPLETE" ]; then
    echo "⚠️ Stack is in an unrecoverable state ($STACK_STATUS). Please check the AWS console. Aborting."
    exit 1
fi