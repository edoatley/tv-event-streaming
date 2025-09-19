const loginView = (() => {
    function render(appContainer) {
        const html = `
            <div class="row justify-content-center">
                <div class="col-md-6">
                    <div class="card text-center">
                        <div class="card-header">
                            <h4>Sign In Required</h4>
                        </div>
                        <div class="card-body">
                            <p>Please log in to access the UK TV Guide.</p>
                            <button id="loginActionBtn" class="btn btn-primary">
                                <i class="fas fa-sign-in-alt me-1"></i>Sign In
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        appContainer.innerHTML = html;

        document.getElementById('loginActionBtn').addEventListener('click', auth.handleLogin);
    }

    return { render };
})();
