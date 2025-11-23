import boto3
import json
import secrets
import string
import traceback
import urllib.request
import urllib.error

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

def send_cfn_response(event, context, status, response_data=None):
    """
    Send a response to CloudFormation custom resource.
    This is a custom implementation that properly handles bytes encoding for Python 3.12.
    """
    if response_data is None:
        response_data = {}
    
    response_body = json.dumps({
        'Status': status,
        'Reason': f'See CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': event.get('PhysicalResourceId', context.log_stream_name),
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': response_data
    })
    
    response_url = event['ResponseURL']
    print(f"[DEBUG] Sending response to: {response_url}")
    print(f"[DEBUG] Response status: {status}")
    print(f"[DEBUG] Response data: {response_data}")
    
    try:
        # Encode the response body as bytes for Python 3.12 compatibility
        response_body_bytes = response_body.encode('utf-8')
        req = urllib.request.Request(response_url, data=response_body_bytes, method='PUT')
        req.add_header('Content-Type', '')
        req.add_header('Content-Length', str(len(response_body_bytes)))
        
        with urllib.request.urlopen(req) as response:
            print(f"[DEBUG] Response sent successfully. Status code: {response.getcode()}")
            return True
    except urllib.error.HTTPError as e:
        print(f"[ERROR] HTTP error sending response: {e.code} - {e.reason}")
        print(f"[ERROR] Response body: {e.read().decode('utf-8')}")
        return False
    except Exception as e:
        print(f"[ERROR] Error sending response: {str(e)}")
        traceback.print_exc()
        return False

def lambda_handler(event, context):
    # Initialize response data
    response_data = {}
    warnings = []
    response_sent = False
    
    # Get RequestType safely; default to '' if missing
    request_type = event.get('RequestType', '')
    
    # Calculate timeout threshold - send response 15 seconds before Lambda timeout
    initial_timeout = context.get_remaining_time_in_millis() / 1000
    timeout_threshold = 15  # seconds before timeout to send emergency response
    
    print(f"[DEBUG] Lambda invoked with RequestType: {request_type}")
    print(f"[DEBUG] Initial remaining time: {initial_timeout:.2f} seconds")
    print(f"[DEBUG] Will send emergency response if less than {timeout_threshold}s remaining")
    print(f"[DEBUG] Event keys: {list(event.keys())}")
    print(f"[DEBUG] Full event: {json.dumps(event, default=str)}")

    def check_timeout():
        """Check if we're approaching timeout and need to send response early"""
        remaining = context.get_remaining_time_in_millis() / 1000
        if remaining < timeout_threshold:
            print(f"[WARNING] Approaching timeout! Only {remaining:.2f}s remaining. Sending response now.")
            return True
        return False

    try:
        # --- Initialize Cognito client ---
        print("[DEBUG] Initializing Cognito client...")
        cognito_client = boto3.client('cognito-idp')
        print("[DEBUG] Cognito client initialized successfully")
        
        # Safely get properties
        props = event.get('ResourceProperties', {})
        print(f"[DEBUG] ResourceProperties keys: {list(props.keys())}")
        user_pool_id = props.get('UserPoolId')
        
        if not user_pool_id:
            error_msg = "UserPoolId missing from ResourceProperties"
            print(f"[ERROR] {error_msg}")
            warnings.append(error_msg)
            # Still return SUCCESS to allow stack to proceed
            response_data['Warnings'] = json.dumps(warnings)
            send_cfn_response(event, context, 'SUCCESS', response_data)
            return

        print(f"[DEBUG] UserPoolId: {user_pool_id}")

        # Handle both list and string inputs
        usernames_raw = props.get('UserNames', [])
        admin_usernames_raw = props.get('AdminUserNames', [])
        
        print(f"[DEBUG] Raw usernames input: {usernames_raw} (type: {type(usernames_raw)})")
        print(f"[DEBUG] Raw admin usernames input: {admin_usernames_raw} (type: {type(admin_usernames_raw)})")
        
        # Helper to parse comma-separated strings or lists
        def parse_list(raw_input):
            if isinstance(raw_input, str):
                return [u.strip() for u in raw_input.split(',') if u.strip()]
            elif isinstance(raw_input, list):
                return raw_input
            return [raw_input] if raw_input else []

        usernames = parse_list(usernames_raw)
        admin_usernames = parse_list(admin_usernames_raw)
        
        print(f"[DEBUG] Parsed usernames: {usernames}")
        print(f"[DEBUG] Parsed admin usernames: {admin_usernames}")
        
        # --- Handle DELETE ---
        if request_type == 'Delete':
            print("[DEBUG] Processing DELETE request")
            for username in usernames:
                if check_timeout():
                    # Send response early to prevent timeout
                    if warnings:
                        response_data['Warnings'] = json.dumps(warnings)
                    response_data['TimeoutWarning'] = "true"
                    response_data['Incomplete'] = "true"
                    send_cfn_response(event, context, 'SUCCESS', response_data)
                    response_sent = True
                    return
                
                print(f"[DEBUG] Attempting to delete user: {username}")
                try:
                    cognito_client.admin_delete_user(
                        UserPoolId=user_pool_id,
                        Username=username
                    )
                    print(f"[DEBUG] Successfully deleted user: {username}")
                except cognito_client.exceptions.UserNotFoundException:
                    print(f"[DEBUG] User not found (already deleted?): {username}")
                except Exception as e:
                    # Log error but continue so we don't fail the whole batch
                    warning_msg = f"Failed to delete user {username}: {str(e)}"
                    print(f"[WARNING] {warning_msg}")
                    warnings.append(warning_msg)
            
            if warnings:
                response_data['Warnings'] = json.dumps(warnings)
            print("[DEBUG] Sending SUCCESS response for DELETE")
            send_cfn_response(event, context, 'SUCCESS', response_data)
            response_sent = True
            return
        
        # --- Handle CREATE / UPDATE ---
        print("[DEBUG] Processing CREATE/UPDATE request")
        user_passwords = {}
        successful_users = []
        failed_users = []
        
        for username in usernames:
            # Check timeout before processing each user
            if check_timeout():
                # Send response early to prevent timeout
                if user_passwords:
                    response_data['UserPasswords'] = json.dumps(user_passwords)
                else:
                    response_data['UserPasswords'] = json.dumps({})
                response_data['Warnings'] = json.dumps(warnings + ["Operation incomplete due to timeout"])
                response_data['TimeoutWarning'] = "true"
                response_data['Incomplete'] = "true"
                send_cfn_response(event, context, 'SUCCESS', response_data)
                response_sent = True
                return
            
            print(f"[DEBUG] Processing user: {username}")
            try:
                password = generate_password()
                print(f"[DEBUG] Generated password for {username} (length: {len(password)})")
                
                try:
                    # Check if user exists
                    print(f"[DEBUG] Checking if user exists: {username}")
                    cognito_client.admin_get_user(
                        UserPoolId=user_pool_id,
                        Username=username
                    )
                    print(f"[DEBUG] User exists, updating password: {username}")
                    # User exists, update password
                    cognito_client.admin_set_user_password(
                        UserPoolId=user_pool_id,
                        Username=username,
                        Password=password,
                        Permanent=True
                    )
                    print(f"[DEBUG] Successfully updated password for existing user: {username}")
                except cognito_client.exceptions.UserNotFoundException:
                    # Create new user
                    print(f"[DEBUG] User does not exist, creating: {username}")
                    cognito_client.admin_create_user(
                        UserPoolId=user_pool_id,
                        Username=username,
                        UserAttributes=[
                            {'Name': 'email', 'Value': username},
                            {'Name': 'email_verified', 'Value': 'true'}
                        ],
                        MessageAction='SUPPRESS'
                    )
                    print(f"[DEBUG] Successfully created user: {username}")
                    cognito_client.admin_set_user_password(
                        UserPoolId=user_pool_id,
                        Username=username,
                        Password=password,
                        Permanent=True
                    )
                    print(f"[DEBUG] Successfully set password for new user: {username}")
                
                # Add to admin group if needed
                if username in admin_usernames:
                    print(f"[DEBUG] Adding {username} to SecurityAdmins group")
                    try:
                        cognito_client.admin_add_user_to_group(
                            UserPoolId=user_pool_id,
                            Username=username,
                            GroupName='SecurityAdmins'
                        )
                        print(f"[DEBUG] Successfully added {username} to SecurityAdmins group")
                    except cognito_client.exceptions.ResourceNotFoundException as e:
                        warning_msg = f"SecurityAdmins group not found when adding {username}: {str(e)}"
                        print(f"[WARNING] {warning_msg}")
                        warnings.append(warning_msg)
                    except cognito_client.exceptions.InvalidParameterException as e:
                        warning_msg = f"Invalid parameter when adding {username} to group: {str(e)}"
                        print(f"[WARNING] {warning_msg}")
                        warnings.append(warning_msg)
                    except Exception as e:
                        warning_msg = f"Unexpected error adding {username} to group: {str(e)}"
                        print(f"[WARNING] {warning_msg}")
                        warnings.append(warning_msg)
                
                # User processed successfully
                user_passwords[username] = password
                successful_users.append(username)
                print(f"[DEBUG] Successfully processed user: {username}")
                
            except Exception as e:
                # Catch any error for this specific user and continue with others
                error_msg = f"Failed to create/update user {username}: {str(e)}"
                print(f"[ERROR] {error_msg}")
                print(f"[DEBUG] Traceback for {username}:")
                traceback.print_exc()
                warnings.append(error_msg)
                failed_users.append(username)
                # Continue processing other users
        
        # Build response data
        print(f"[DEBUG] Summary - Successful: {len(successful_users)}, Failed: {len(failed_users)}")
        print(f"[DEBUG] Successful users: {successful_users}")
        print(f"[DEBUG] Failed users: {failed_users}")
        
        # Always set UserPasswords (even if empty) to prevent GetAtt failures
        if user_passwords:
            response_data['UserPasswords'] = json.dumps(user_passwords)
        else:
            warnings.append("No users were successfully created")
            response_data['UserPasswords'] = json.dumps({})
        
        # Always set Warnings (even if empty) to prevent GetAtt failures
        response_data['Warnings'] = json.dumps(warnings)
        if warnings:
            print(f"[WARNING] There were {len(warnings)} warnings during user creation")
        
        if failed_users:
            response_data['FailedUsers'] = json.dumps(failed_users)
            print(f"[WARNING] {len(failed_users)} user(s) failed to create: {failed_users}")
        
        # Always return SUCCESS to allow stack to proceed, even if some users failed
        print("[DEBUG] Sending SUCCESS response (stack will proceed despite any user creation failures)")
        send_cfn_response(event, context, 'SUCCESS', response_data)
        response_sent = True
        
    except Exception as e:
        error_msg = f"Critical error in Lambda handler: {str(e)}"
        print(f"[ERROR] {error_msg}")
        print("[DEBUG] Full traceback:")
        traceback.print_exc()
        
        warnings.append(error_msg)
        # Always ensure both UserPasswords and Warnings are set to prevent GetAtt failures
        if 'UserPasswords' not in response_data:
            response_data['UserPasswords'] = json.dumps({})
        response_data['Warnings'] = json.dumps(warnings)
        response_data['CriticalError'] = str(e)
        
        # Always return SUCCESS to prevent stack failure
        # Log the error but allow deployment to continue
        print("[WARNING] Returning SUCCESS despite error to allow stack deployment to proceed")
        print("[WARNING] Check CloudWatch logs and Warnings output for details")
        
        # Try to send response - if it fails, we've already logged the error
        send_cfn_response(event, context, 'SUCCESS', response_data)
        response_sent = True
    finally:
        # Ensure response is always sent, even if something goes wrong
        if not response_sent:
            print("[CRITICAL] Response not sent in normal flow! Sending emergency response in finally block")
            try:
                emergency_response = response_data.copy()
                if 'UserPasswords' not in emergency_response:
                    emergency_response['UserPasswords'] = json.dumps({})
                if 'Warnings' not in emergency_response:
                    emergency_response['Warnings'] = json.dumps(["Lambda handler exited without sending response"])
                emergency_response['EmergencyResponse'] = "true"
                send_cfn_response(event, context, 'SUCCESS', emergency_response)
                response_sent = True
            except Exception as final_error:
                print(f"[CRITICAL] Failed to send emergency response: {str(final_error)}")
                traceback.print_exc()