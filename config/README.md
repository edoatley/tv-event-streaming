# Configuration Files

This directory contains configuration files used for deployment and user management.

## users.json

Defines the Cognito users that should be created during deployment.

### Structure

```json
{
  "users": [
    {
      "email": "user@example.com",
      "type": "standard"
    },
    {
      "email": "admin@example.com",
      "type": "admin"
    }
  ]
}
```

### User Types

- **standard**: Regular users with standard permissions
- **admin**: Administrative users who are added to the SecurityAdmins group

### Usage

This file is automatically read by:
- The GitHub Actions workflow during deployment
- The `create-cognito-users.sh` script (if no parameters provided)

### Modifying Users

To add, remove, or modify users:
1. Edit `config/users.json`
2. Commit and push the changes
3. The next deployment will create/update users accordingly

**Note**: Removing a user from this file will NOT delete them from Cognito. They will remain in the user pool but won't be recreated on subsequent deployments.






