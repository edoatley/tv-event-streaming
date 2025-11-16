import boto3
import json
import secrets
import string
import cfnresponse


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
                except cognito_client.exceptions.UserNotFoundException:
                    pass
            cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
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
            except cognito_client.exceptions.UserNotFoundException:
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
                except cognito_client.exceptions.ResourceNotFoundException:
                    # Group might not exist yet, that's okay
                    pass
                except cognito_client.exceptions.InvalidParameterException:
                    # User might already be in group, that's okay
                    pass
        
        response_data['UserPasswords'] = json.dumps(user_passwords)
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        cfnresponse.send(event, context, cfnresponse.FAILED, response_data)

