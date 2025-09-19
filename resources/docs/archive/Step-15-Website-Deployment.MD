# Step 15 - Single Page Web Application Hosted on S3

This step adds a single page web application (SPA) that provides user authentication and displays TV titles and recommendations from DynamoDB.

## What's Been Added

### 1. CloudFormation Resources

- **S3 Bucket**: `WebsiteBucket` for hosting the static website
- **Website Deployment Lambda**: `WebsiteDeploymentFunction` that automatically deploys website files during stack creation
- **Custom Resource**: `WebsiteDeployment` that triggers the Lambda function
- **Web API Lambda**: `WebApiApp` nested stack for serving data to the SPA

### 2. Website Files

The following files are automatically deployed to S3:
- `index.html` - Main application page
- `error.html` - Error page
- `app.js` - JavaScript application logic

### 3. API Endpoints

The Web API provides two authenticated endpoints:
- `/titles` - Get titles based on user preferences
- `/recommendations` - Get new recommendations (rating > 7)

## Deployment Steps

### 1. Deploy the CloudFormation Stack

```bash
# Deploy with SAM
sam build
sam deploy --guided

# Or deploy directly with CloudFormation
aws cloudformation deploy \
  --template-file resources/cloudformation/uktv-event-streaming-app.yaml \
  --stack-name uktv-event-streaming-app \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides "CreateDataStream=true" "WatchModeApiKey=${WATCHMODE_API_KEY}"
```

### 2. Update Website Configuration

After deployment, the website files are deployed with placeholder values. You need to update the JavaScript configuration with actual values:

```bash
# Make the script executable
chmod +x resources/scripts/update_website_config.sh

# Run the configuration update script
./resources/scripts/update_website_config.sh uktv-event-streaming-app <your-profile> <your-region>
```

This script will:
1. Get the actual CloudFormation output values
2. Create an updated `app.js` with the correct configuration
3. Upload it to the S3 bucket

### 3. Access the Website

The website URL will be available in the CloudFormation outputs as `WebsiteUrl`.

## Website Features

### User Authentication
- Uses AWS Cognito for user authentication
- Pre-created test user: `test.user@example.com`
- Login/logout functionality

### User Preferences
- Display current streaming source and genre preferences
- Update preferences through checkboxes
- Preferences are stored in DynamoDB

### Content Display
- **All Titles Tab**: Shows all titles matching user preferences
- **Recommendations Tab**: Shows high-rated titles (rating > 7)
- Title cards with images, ratings, and descriptions
- Click on titles to see detailed information

### Responsive Design
- Bootstrap-based UI
- Mobile-friendly responsive design
- Modern card-based layout

## Architecture

```
User Browser → S3 Website → Cognito Auth → API Gateway → Lambda Functions → DynamoDB
```

1. **S3 Website**: Hosts the static HTML, CSS, and JavaScript files
2. **Cognito**: Handles user authentication and provides JWT tokens
3. **API Gateway**: Routes requests to appropriate Lambda functions
4. **Lambda Functions**: 
   - `WebApiFunction`: Serves titles and recommendations
   - `UserPreferencesFunction`: Manages user preferences
5. **DynamoDB**: Stores user preferences and title data

## Configuration Values

The website needs these configuration values (automatically populated by the update script):

- `userPoolId`: Cognito User Pool ID
- `userPoolClientId`: Cognito User Pool Client ID
- `apiEndpoint`: Web API endpoint URL
- `preferencesApiEndpoint`: User Preferences API endpoint URL

## Testing

### 1. Test User Authentication
- Navigate to the website URL
- Click "Login" button
- Use the test user credentials

### 2. Test Preferences
- Set some streaming source and genre preferences
- Click "Update Preferences"

### 3. Test Content Display
- Switch between "All Titles" and "Recommendations" tabs
- Click on title cards to see detailed information

### 4. Test API Endpoints
- Check browser developer tools for API calls
- Verify authentication headers are being sent
- Check for any JavaScript errors

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Verify Cognito User Pool and Client IDs are correct
   - Check that the test user exists and is confirmed

2. **API Errors**
   - Verify API endpoint URLs are correct
   - Check that Lambda functions have proper IAM permissions
   - Verify DynamoDB table names and permissions

3. **Website Not Loading**
   - Check S3 bucket permissions
   - Verify website hosting is enabled
   - Check CloudFormation outputs for correct URLs

4. **CORS Issues**
   - API Gateway should handle CORS automatically
   - Check Lambda function response headers

### Debugging

1. **Check CloudFormation Outputs**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name uktv-event-streaming-app \
     --query 'Stacks[0].Outputs'
   ```

2. **Check S3 Bucket Contents**
   ```bash
   aws s3 ls s3://<bucket-name>/
   ```

3. **Check Lambda Function Logs**
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/WebApiFunction"
   ```

## Next Steps

After the website is working:

1. **Add Google IdP Federation** (Step 16)
2. **Implement Real-time Updates** using DynamoDB Streams
3. **Add Notifications** for favorite shows
4. **Enhance UI/UX** with additional features

## Cost Considerations

- **S3**: Minimal cost for static website hosting
- **Lambda**: Pay per request for API calls
- **API Gateway**: Pay per API call
- **Cognito**: Pay per monthly active user
- **DynamoDB**: Pay per request and storage

The website deployment is designed to be cost-effective for development and testing purposes.
