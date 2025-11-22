import boto3
import json
import secrets
import string
import urllib.request
import urllib.error
from botocore.exceptions import ClientError

# cfnresponse replacement for Python 3.12 (not available in runtime)
def send_response(event, context, response_status, response_data, physical_resource_id=None):
    """Send a response to CloudFormation for a custom resource."""
    response_url = event['ResponseURL']
    
    response_body = {
        'Status': response_status,
        'Reason': f'See the details in CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': physical_resource_id or context.log_stream_name,
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': response_data
    }
    
    json_response_body = json.dumps(response_body).encode('utf-8')
    
    try:
        req = urllib.request.Request(
            response_url,
            data=json_response_body,
            method='PUT',
            headers={'Content-Type': ''}
        )
        with urllib.request.urlopen(req) as response:
            print(f"CloudFormation response status: {response.status}")
    except urllib.error.HTTPError as e:
        print(f"Error sending response to CloudFormation: HTTP {e.code} - {e.reason}")
        # Still raise to ensure CloudFormation knows something went wrong
        raise
    except Exception as e:
        print(f"Error sending response to CloudFormation: {str(e)}")
        raise


def generate_password():
    """Generate a random password that meets Cognito requirements"""
    # Password requirements: min 8 chars, uppercase, lowercase, numbers
    length = 16
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    password = ''.join(secrets.choice(alphabet) for _ in range(length))
    # Ensure it has at least one of each required type
    if not any(c.isupper() for c in password):
        password = password[:-1] + secrets.choice(string.ascii_uppercase)
    if not any(c.islower() for c in password):
        password = password[:-1] + secrets.choice(string.ascii_lowercase)
    if not any(c.isdigit() for c in password):
        password = password[:-1] + secrets.choice(string.digits)
    return password


def lambda_handler(event, context):
    cognito_client = boto3.client('cognito-idp')
    user_pool_id = event['ResourceProperties']['UserPoolId']
    # Handle both list and string inputs
    usernames_raw = event['ResourceProperties']['UserNames']
    admin_usernames_raw = event['ResourceProperties'].get('AdminUserNames', [])
    
    # Convert to list if it's a string (comma-separated)
    if isinstance(usernames_raw, str):
        usernames = [u.strip() for u in usernames_raw.split(',') if u.strip()]
    else:
        usernames = usernames_raw if isinstance(usernames_raw, list) else [usernames_raw]
    
    if isinstance(admin_usernames_raw, str):
        admin_usernames = [u.strip() for u in admin_usernames_raw.split(',') if u.strip()]
    else:
        admin_usernames = admin_usernames_raw if isinstance(admin_usernames_raw, list) else [admin_usernames_raw] if admin_usernames_raw else []
    
    request_type = event['RequestType']
    
    response_data = {}
    
    try:
        if request_type == 'Delete':
            # Delete all users
            for username in usernames:
                try:
                    cognito_client.admin_delete_user(
                        UserPoolId=user_pool_id,
                        Username=username
                    )
                except ClientError as e:
                    if e.response['Error']['Code'] != 'UserNotFoundException':
                        raise
                    pass
            send_response(event, context, 'SUCCESS', response_data)
            return
        
        # Create or update users
        user_passwords = {}
        
        for username in usernames:
            password = generate_password()
            user_passwords[username] = password
            
            try:
                # Check if user exists
                cognito_client.admin_get_user(
                    UserPoolId=user_pool_id,
                    Username=username
                )
                # User exists, just update password
                cognito_client.admin_set_user_password(
                    UserPoolId=user_pool_id,
                    Username=username,
                    Password=password,
                    Permanent=True
                )
            except ClientError as e:
                if e.response['Error']['Code'] != 'UserNotFoundException':
                    raise
                # User doesn't exist, create it
                cognito_client.admin_create_user(
                    UserPoolId=user_pool_id,
                    Username=username,
                    UserAttributes=[
                        {'Name': 'email', 'Value': username},
                        {'Name': 'email_verified', 'Value': 'true'}
                    ],
                    MessageAction='SUPPRESS'  # Don't send welcome email
                )
                # Set the password
                cognito_client.admin_set_user_password(
                    UserPoolId=user_pool_id,
                    Username=username,
                    Password=password,
                    Permanent=True
                )
            
            # Add to admin group if specified
            if username in admin_usernames:
                try:
                    cognito_client.admin_add_user_to_group(
                        UserPoolId=user_pool_id,
                        Username=username,
                        GroupName='SecurityAdmins'
                    )
                except ClientError as e:
                    error_code = e.response['Error']['Code']
                    if error_code in ['ResourceNotFoundException', 'InvalidParameterException']:
                        # Group might not exist yet or user already in group, that's okay
                        pass
                    else:
                        raise
        
        response_data['UserPasswords'] = json.dumps(user_passwords)
        send_response(event, context, 'SUCCESS', response_data)
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        send_response(event, context, 'FAILED', response_data)

