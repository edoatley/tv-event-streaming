const mainView = (() => {
    let sources = [];
    let genres = [];

    function getHtml() {
        // Conditionally add the Admin tab if the user is an admin
        const adminTabHtml = auth.isAdmin()
            ? `<li class="nav-item"><a class="nav-link" href="#/admin" data-page="admin">Admin</a></li>`
            : '';

        return `
            <!-- Main Navigation -->
            <ul class="nav nav-pills mb-3" id="main-nav-tabs">
                <li class="nav-item">
                    <a class="nav-link" href="#/main/titles" data-page="titles">Titles</a>
                </li>
                <li class="nav-item">
                    <a class="nav-link" href="#/main/preferences" data-page="preferences">Preferences</a>
                </li>
                ${adminTabHtml}
            </ul>

            <!-- Page Content -->
            <div id="page-content"></div>
        `;
    }

    function getTitlesPageHtml() {
        return `
            <ul class="nav nav-tabs mb-4" id="contentTabs" role="tablist">
                <li class="nav-item" role="presentation">
                    <button class="nav-link active" id="titles-tab" data-bs-toggle="tab" data-bs-target="#titles" type="button" role="tab">
                        <i class="fas fa-list me-1"></i>All Titles
                    </button>
                </li>
                <li class="nav-item" role="presentation">
                    <button class="nav-link" id="recommendations-tab" data-bs-toggle="tab" data-bs-target="#recommendations" type="button" role="tab">
                        <i class="fas fa-star me-1"></i>Recommendations
                    </button>
                </li>
            </ul>
            <div class="tab-content" id="contentTabContent">
                <div class="tab-pane fade show active" id="titles" role="tabpanel">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <h4>Available Titles</h4>
                        <div class="spinner-border spinner-border-sm d-none" id="titlesLoading"></div>
                    </div>
                    <div id="titlesContainer" class="row"></div>
                </div>
                <div class="tab-pane fade" id="recommendations" role="tabpanel">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <h4>New Recommendations</h4>
                        <div class="spinner-border spinner-border-sm d-none" id="recommendationsLoading"></div>
                    </div>
                    <div id="recommendationsContainer" class="row"></div>
                </div>
            </div>
        `;
    }

    function getPreferencesPageHtml() {
        return `
            <div class="preferences-section">
                <h4><i class="fas fa-cog me-2"></i>Your Preferences</h4>
                <div class="row">
                    <div class="col-md-6">
                        <h6>Streaming Sources</h6>
                        <div class="mb-3"><strong>Selected:</strong><div id="selectedSourcesList"></div></div>
                        <hr>
                        <div class="mb-3"><strong>Available to add:</strong><div id="availableSourcesList"></div></div>
                    </div>
                    <div class="col-md-6">
                        <h6>Genres</h6>
                        <div class="mb-3"><strong>Selected:</strong><div id="selectedGenresList"></div></div>
                        <hr>
                        <div class="mb-3"><strong>Available to add:</strong><div id="availableGenresList"></div></div>
                    </div>
                </div>
                <button id="updatePreferencesBtn" class="btn btn-primary"><i class="fas fa-save me-1"></i>Update Preferences</button>
            </div>
        `;
    }

    async function render(appContainer, page) {
        appContainer.innerHTML = getHtml();
        const pageContent = document.getElementById('page-content');

        await Promise.all([loadSources(), loadGenres()]);

        attachNavListeners(pageContent);
        showPage(page, pageContent);
    }
    
    function showPage(page, container) {
        document.querySelectorAll('#main-nav-tabs .nav-link').forEach(link => link.classList.remove('active'));
        const linkToShow = document.querySelector(`#main-nav-tabs .nav-link[data-page='${page}']`);
        if(linkToShow) linkToShow.classList.add('active');

        if (page === 'titles') {
            container.innerHTML = getTitlesPageHtml();
            loadTitles();
            loadRecommendations();
        } else if (page === 'preferences') {
            container.innerHTML = getPreferencesPageHtml();
            loadUserPreferences();
        } else if (page === 'admin') {
            // The router will handle rendering the admin view, so we can leave this empty
            // or show a loading indicator.
            container.innerHTML = `<h4>Loading Admin...</h4>`;
        }
    }

    function attachNavListeners(pageContainer) {
        document.getElementById('main-nav-tabs').addEventListener('click', (e) => {
            if (e.target.tagName === 'A') {
                e.preventDefault();
                const page = e.target.getAttribute('data-page');
                if (page === 'admin') {
                    window.location.hash = '#/admin';
                } else {
                    window.location.hash = `#/main/${page}`;
                }
            }
        });
    }

    async function loadSources() {
        sources = await api.getSources();
    }

    async function loadGenres() {
        genres = await api.getGenres();
    }

    async function loadUserPreferences() {
        const preferences = await api.getUserPreferences();
        renderPreferencesUI(preferences);
        document.getElementById('updatePreferencesBtn').addEventListener('click', updatePreferences);
    }

    async function updatePreferences() {
        const selectedSources = Array.from(document.querySelectorAll('input[name="source"]:checked')).map(cb => cb.value);
        const selectedGenres = Array.from(document.querySelectorAll('input[name="genre"]:checked')).map(cb => cb.value);

        try {
            await api.updatePreferences({ sources: selectedSources, genres: selectedGenres });
            alert('Preferences updated successfully!');
            await loadUserPreferences();
        } catch (error) {
            alert(`Error updating preferences: ${error.message}`);
        }
    }

    async function loadTitles() {
        document.getElementById('titlesLoading').classList.remove('d-none');
        const titles = await api.getTitles();
        renderTitlesUI(titles, 'titlesContainer');
        document.getElementById('titlesLoading').classList.add('d-none');
    }

    async function loadRecommendations() {
        document.getElementById('recommendationsLoading').classList.remove('d-none');
        const recommendations = await api.getRecommendations();
        renderTitlesUI(recommendations, 'recommendationsContainer');
        document.getElementById('recommendationsLoading').classList.add('d-none');
    }

    function renderPreferencesUI(userPreferences) {
        const renderList = (items, selectedIds, selectedContainerId, availableContainerId, type) => {
            let selectedHtml = '';
            let availableHtml = '';
            items.forEach(item => {
                const isSelected = selectedIds.includes(item.id.toString());
                const checkboxHtml = `
                    <div class="form-check">
                        <input class="form-check-input" type="checkbox" name="${type}" value="${item.id}" id="${type}_${item.id}" ${isSelected ? 'checked' : ''}>
                        <label class="form-check-label" for="${type}_${item.id}">${item.name}</label>
                    </div>`;
                if (isSelected) selectedHtml += checkboxHtml; else availableHtml += checkboxHtml;
            });
            document.getElementById(selectedContainerId).innerHTML = selectedHtml || `<p class="text-muted small">No ${type}s selected.</p>`;
            document.getElementById(availableContainerId).innerHTML = availableHtml || `<p class="text-muted small">All available ${type}s are selected.</p>`;
        };
        renderList(sources, userPreferences.sources || [], 'selectedSourcesList', 'availableSourcesList', 'source');
        renderList(genres, userPreferences.genres || [], 'selectedGenresList', 'availableGenresList', 'genre');
    }

    function renderTitlesUI(titles, containerId) {
        const container = document.getElementById(containerId);
        if (!titles || titles.length === 0) {
            container.innerHTML = '<div class="col-12"><p class="text-muted">No titles found.</p></div>';
            return;
        }
        container.innerHTML = titles.map(title => `
            <div class="col-md-4 col-lg-3 mb-4">
                <div class="card title-card h-100" onclick='mainView.showTitleDetails(${JSON.stringify(title).replace(/'/g, "&apos;")})'>
                    <div class="position-relative">
                        <img src="${title.poster || 'https://via.placeholder.com/300x450?text=No+Image'}" class="card-img-top title-image" alt="${title.title}" onerror="this.src='https://via.placeholder.com/300x450?text=No+Image'">
                        ${title.user_rating > 0 ? `<div class="rating-badge">${title.user_rating}/10</div>` : ''}
                    </div>
                    <div class="card-body"><h6 class="card-title">${title.title}</h6></div>
                </div>
            </div>`).join('');
    }

    function showTitleDetails(title) {
        document.getElementById('titleModalTitle').textContent = title.title;
        document.getElementById('titleModalImage').src = title.poster || 'https://via.placeholder.com/300x450?text=No+Image';
        document.getElementById('titleModalPlot').textContent = title.plot_overview || 'No description available';
        document.getElementById('titleModalRating').textContent = title.user_rating > 0 ? `${title.user_rating}/10` : 'Not rated';
        const sourceNames = (title.source_ids || []).map(id => sources.find(s => s.id.toString() === id.toString())?.name || 'Unknown').join(', ');
        const genreNames = (title.genre_ids || []).map(id => genres.find(g => g.id.toString() === id.toString())?.name || 'Unknown').join(', ');
        document.getElementById('titleModalSources').textContent = sourceNames;
        document.getElementById('titleModalGenres').textContent = genreNames;
        const modal = new bootstrap.Modal(document.getElementById('titleModal'));
        modal.show();
    }

    return { render, showTitleDetails };
})();
