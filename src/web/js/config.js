// This file is a template. It will be replaced by a build script with actual values from the CloudFormation stack outputs.
window.appConfig = {
    Auth: {
        userPoolId: "__USER_POOL_ID__",
        userPoolClientId: "__USER_POOL_CLIENT_ID__",
        region: "eu-west-2",
        oauth: {
            domain: "__COGNITO_DOMAIN__",
            scope: ['openid', 'email', 'profile'],
            redirectSignIn: "__REDIRECT_URI__",
            redirectSignOut: "__REDIRECT_URI__",
            responseType: 'token'
        }
    },
    ApiEndpoint: "__API_ENDPOINT__",
    AdminApiEndpoint: "__ADMIN_API_ENDPOINT__"
};
