const auth = (() => {
    let idToken = null;

    function parseJwt(token) {
        try {
            return JSON.parse(atob(token.split('.')[1]));
        } catch (e) {
            return null;
        }
    }

    function handleLogin() {
        const { Auth } = window.appConfig;
        const cognitoDomain = Auth.oauth.domain;
        const clientId = Auth.userPoolClientId;
        // This must exactly match one of the URLs configured in the Cognito User Pool client settings.
        const redirectUri = window.location.origin + '/index.html';
        const responseType = 'token';
        const scope = Auth.oauth.scope.join(' ');

        const url = `https://${cognitoDomain}/login?response_type=${responseType}&client_id=${clientId}&redirect_uri=${redirectUri}&scope=${scope}`;
        window.location.assign(url);
    }

    function handleLogout() {
        localStorage.removeItem('id_token');
        idToken = null;
        const { Auth } = window.appConfig;
        const cognitoDomain = Auth.oauth.domain;
        const clientId = Auth.userPoolClientId;
        // This must exactly match one of the URLs configured in the Cognito User Pool client settings.
        const redirectUri = window.location.origin + '/index.html';
        const logoutUrl = `https://${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${redirectUri}`;
        window.location.assign(logoutUrl);
    }

    function init() {
        const hash = window.location.hash.substring(1);
        const params = new URLSearchParams(hash);
        const tokenFromUrl = params.get('id_token');

        if (tokenFromUrl) {
            localStorage.setItem('id_token', tokenFromUrl);
            // Clean the token from the URL
            window.history.replaceState({}, document.title, window.location.pathname + window.location.search);
        }

        const storedToken = localStorage.getItem('id_token');
        if (storedToken) {
            const decodedToken = parseJwt(storedToken);
            if (decodedToken && decodedToken.exp * 1000 > Date.now()) {
                idToken = storedToken;
            } else {
                localStorage.removeItem('id_token');
            }
        }
    }

    function isAuthenticated() {
        return !!idToken;
    }

    function isAdmin() {
        if (!idToken) return false;
        const decodedToken = parseJwt(idToken);
        // Check if the user belongs to the 'SecurityAdmins' group
        return decodedToken && decodedToken['cognito:groups'] && decodedToken['cognito:groups'].includes('SecurityAdmins');
    }

    function getToken() {
        return idToken;
    }
    
    function getUser() {
        if (!idToken) return null;
        const decodedToken = parseJwt(idToken);
        return decodedToken ? { email: decodedToken.email, username: decodedToken['cognito:username'] } : null;
    }

    return {
        init,
        handleLogin,
        handleLogout,
        isAuthenticated,
        isAdmin,
        getToken,
        getUser
    };
})();
