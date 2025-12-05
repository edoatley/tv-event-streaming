import {
  CognitoIdentityProviderClient,
  InitiateAuthCommand,
  AuthFlowType,
  ChallengeNameType,
  RespondToAuthChallengeCommand,
} from '@aws-sdk/client-cognito-identity-provider';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Load environment variables
dotenv.config({ path: path.resolve(__dirname, '../.env') });

const region = process.env.AWS_REGION || 'eu-west-2';
const profile = process.env.AWS_PROFILE || 'streaming';

/**
 * Creates a Cognito client with credentials from AWS profile
 */
function createCognitoClient(): CognitoIdentityProviderClient {
  const clientConfig: any = {
    region,
  };

  // If AWS_PROFILE is set, credentials will be loaded from the profile
  // Otherwise, use default credential chain
  if (profile && profile !== 'default') {
    // Note: AWS SDK v3 doesn't directly support profiles in the client config
    // Credentials should be loaded via AWS SDK credential providers
    // The profile will be used by the default credential provider chain
  }

  return new CognitoIdentityProviderClient(clientConfig);
}

/**
 * Authenticates a user with Cognito and returns the ID token
 */
export async function authenticateUser(
  username: string,
  password: string,
  clientId: string
): Promise<string> {
  const client = createCognitoClient();

  // Trim whitespace from username and password to prevent authentication failures
  const trimmedUsername = username.trim();
  const trimmedPassword = password.trim();
  const trimmedClientId = clientId.trim();

  try {
    // Initiate authentication
    const initiateAuthCommand = new InitiateAuthCommand({
      AuthFlow: AuthFlowType.USER_PASSWORD_AUTH,
      ClientId: trimmedClientId,
      AuthParameters: {
        USERNAME: trimmedUsername,
        PASSWORD: trimmedPassword,
      },
    });

    let response = await client.send(initiateAuthCommand);

    // Handle NEW_PASSWORD_REQUIRED challenge if user needs to set a new password
    if (response.ChallengeName === ChallengeNameType.NEW_PASSWORD_REQUIRED) {
      // For test users, we assume passwords are already set
      // If this challenge appears, it means the password needs to be changed
      throw new Error(
        'NEW_PASSWORD_REQUIRED challenge encountered. Please ensure the test user password is set correctly.'
      );
    }

    // Check if we got tokens directly
    if (response.AuthenticationResult?.IdToken) {
      return response.AuthenticationResult.IdToken;
    }

    // If there's a challenge, we need to respond to it
    if (response.ChallengeName) {
      throw new Error(
        `Unexpected challenge: ${response.ChallengeName}. Authentication flow may need additional handling.`
      );
    }

    throw new Error('Authentication failed: No ID token received');
  } catch (error: any) {
    if (error.name === 'NotAuthorizedException') {
      throw new Error(
        `Authentication failed: Invalid username or password for user ${trimmedUsername}`
      );
    }
    if (error.name === 'UserNotConfirmedException') {
      throw new Error(
        `User ${trimmedUsername} is not confirmed. Please confirm the user in Cognito.`
      );
    }
    throw error;
  }
}

/**
 * Gets the ID token for a user using programmatic authentication
 */
export async function getIdToken(
  email: string,
  password: string
): Promise<string> {
  const clientId =
    process.env.TEST_SCRIPT_USER_POOL_CLIENT_ID ||
    process.env.COGNITO_CLIENT_ID ||
    '';

  if (!clientId) {
    throw new Error(
      'TEST_SCRIPT_USER_POOL_CLIENT_ID or COGNITO_CLIENT_ID environment variable is required'
    );
  }

  return await authenticateUser(email, password, clientId);
}

