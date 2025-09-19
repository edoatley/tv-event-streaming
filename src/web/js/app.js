document.addEventListener('DOMContentLoaded', () => {
    const loginBtn = document.getElementById('loginBtn');
    const logoutBtn = document.getElementById('logoutBtn');
    const userGreeting = document.getElementById('user-greeting');
    const adminNav = document.getElementById('adminNav');

    function updateUI() {
        if (auth.isAuthenticated()) {
            const user = auth.getUser();
            // Display the user's email, which is more user-friendly than the UUID.
            userGreeting.textContent = `Welcome, ${user.email}`;
            userGreeting.style.display = 'block';
            loginBtn.style.display = 'none';
            logoutBtn.style.display = 'block';

            // Conditionally show the admin link based on the user's group membership.
            if (auth.isAdmin()) {
                adminNav.style.display = 'block';
            } else {
                adminNav.style.display = 'none';
            }

        } else {
            userGreeting.style.display = 'none';
            loginBtn.style.display = 'block';
            logoutBtn.style.display = 'none';
            adminNav.style.display = 'none';
        }
    }

    loginBtn.addEventListener('click', auth.handleLogin);
    logoutBtn.addEventListener('click', auth.handleLogout);

    // Initialize the auth module, which handles token processing
    auth.init();

    // Update the UI based on authentication status
    updateUI();

    // Initialize the router to handle the initial page load
    router.init();
});
