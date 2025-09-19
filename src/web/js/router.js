const router = (() => {
    const appContainer = document.getElementById('app');

    function handleRouteChange() {
        const hash = window.location.hash || '#/';
        const [path, subpath] = hash.substring(2).split('/');

        if (!auth.isAuthenticated()) {
            loginView.render(appContainer);
            return;
        }

        switch (path) {
            case 'admin':
                if (auth.isAdmin()) {
                    adminView.render(appContainer);
                } else {
                    window.location.hash = '#/'; // Redirect to home if not admin
                }
                break;
            case 'main':
                mainView.render(appContainer, subpath || 'titles');
                break;
            default:
                window.location.hash = '#/main/titles';
                break;
        }
    }

    function init() {
        window.addEventListener('hashchange', handleRouteChange);
        handleRouteChange(); // Initial route handling
    }

    return { init };
})();
