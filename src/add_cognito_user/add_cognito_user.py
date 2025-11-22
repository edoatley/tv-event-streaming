import boto3
import json
import secrets
import string
import cfnresponse
import traceback

def generate_password():
    """Generate a random password that meets Cognito requirements"""
    length = 16
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    password = ''.join(secrets.choice(alphabet) for _ in range(length))
    if not any(c.isupper() for c in password):
        password = password[:-1] + secrets.choice(string.ascii_uppercase)
    if not any(c.islower() for c in password):
        password = password[:-1] + secrets.choice(string.ascii_lowercase)
    if not any(c.isdigit() for c in password):
        password = password[:-1] + secrets.choice(string.digits)
    return password

def lambda_handler(event, context):
    # Initialize response data
    response_data = {}
    # Get RequestType safely; default to '' if missing
    request_type = event.get('RequestType', '')

    try:
        # --- Move initialization INSIDE the try block ---
        cognito_client = boto3.client('cognito-idp')
        
        # Safely get properties
        props = event.get('ResourceProperties', {})
        user_pool_id = props.get('UserPoolId')
        
        if not user_pool_id:
            raise ValueError("UserPoolId missing from ResourceProperties")

        # Handle both list and string inputs
        usernames_raw = props.get('UserNames', [])
        admin_usernames_raw = props.get('AdminUserNames', [])
        
        # Helper to parse comma-separated strings or lists
        def parse_list(raw_input):
            if isinstance(raw_input, str):
                return [u.strip() for u in raw_input.split(',') if u.strip()]
            elif isinstance(raw_input, list):
                return raw_input
            return [raw_input] if raw_input else []

        usernames = parse_list(usernames_raw)
        admin_usernames = parse_list(admin_usernames_raw)
        
        # --- Handle DELETE ---
        if request_type == 'Delete':
            for username in usernames:
                try:
                    cognito_client.admin_delete_user(
                        UserPoolId=user_pool_id,
                        Username=username
                    )
                except cognito_client.exceptions.UserNotFoundException:
                    pass
                except Exception as e:
                    # Log error but continue so we don't fail the whole batch
                    print(f"Warning: Failed to delete user {username}: {e}")
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
            return
        
        # --- Handle CREATE / UPDATE ---
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
                # User exists, update password
                cognito_client.admin_set_user_password(
                    UserPoolId=user_pool_id,
                    Username=username,
                    Password=password,
                    Permanent=True
                )
            except cognito_client.exceptions.UserNotFoundException:
                # Create new user
                cognito_client.admin_create_user(
                    UserPoolId=user_pool_id,
                    Username=username,
                    UserAttributes=[
                        {'Name': 'email', 'Value': username},
                        {'Name': 'email_verified', 'Value': 'true'}
                    ],
                    MessageAction='SUPPRESS'
                )
                cognito_client.admin_set_user_password(
                    UserPoolId=user_pool_id,
                    Username=username,
                    Password=password,
                    Permanent=True
                )
            
            # Add to admin group if needed
            if username in admin_usernames:
                try:
                    cognito_client.admin_add_user_to_group(
                        UserPoolId=user_pool_id,
                        Username=username,
                        GroupName='SecurityAdmins'
                    )
                except (cognito_client.exceptions.ResourceNotFoundException, 
                        cognito_client.exceptions.InvalidParameterException):
                    pass
        
        response_data['UserPasswords'] = json.dumps(user_passwords)
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
        
    except Exception as e:
        print(f"Error: {str(e)}")
        traceback.print_exc()
        
        # --- CRITICAL FIX: Return SUCCESS on DELETE failure ---
        # This prevents the CloudFormation stack from getting stuck in DELETE_FAILED
        if request_type == 'Delete':
            print("Sending SUCCESS to CloudFormation to ensure clean stack deletion.")
            cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
        else:
            cfnresponse.send(event, context, cfnresponse.FAILED, response_data)