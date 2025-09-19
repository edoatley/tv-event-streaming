window.appConfig = {
    Auth: {
        userPoolId: "eu-west-2_QKJf7VD74",
        userPoolClientId: "35bfrtilh7u82u1s6678e3sipv",
        region: "eu-west-2",
        oauth: {
            domain: "uktv-guide-4b1a1500-917f-11f0-ae90-0a677997a123.auth.eu-west-2.amazoncognito.com",
            scope: ['openid', 'email', 'profile'],
            redirectSignIn: "", // Not used in this flow, but good to have
            redirectSignOut: "", // Not used in this flow
            responseType: 'token'
        }
    },
    ApiEndpoint: "https://9pu1jw5gac.execute-api.eu-west-2.amazonaws.com/Prod",
    AdminApiEndpoint: "https://xaphfzgz94.execute-api.eu-west-2.amazonaws.com/Prod"
};
