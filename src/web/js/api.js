const api = (() => {
    async function makeRequest(endpoint, path, method = 'GET', body = null) {
        try {
            const headers = {
                'Content-Type': 'application/json'
            };

            const token = auth.getToken();
            if (token) {
                headers['Authorization'] = token;
            }

            const options = { method, headers };
            if (body) {
                options.body = JSON.stringify(body);
            }

            const response = await fetch(`${endpoint}${path}`, options);

            const contentType = response.headers.get("content-type");
            const isJson = contentType && contentType.indexOf("application/json") !== -1;

            if (!response.ok) {
                let errorBody = { message: `API request failed with status ${response.status}` };
                if (isJson) {
                    try {
                        errorBody = await response.json();
                    } catch (e) { /* Ignore if body isn't valid JSON */ }
                }
                const error = new Error(errorBody.error || errorBody.message || `API request failed with status ${response.status}`);
                error.response = response;
                throw error;
            }

            if (response.status === 204) { // No Content
                return;
            }

            if (isJson) {
                return await response.json();
            } else {
                return await response.text();
            }
        } catch (error) {
            console.error(`Error in API request to ${path}:`, error);
            throw error;
        }
    }

    // Main App API Calls
    const mainApi = (path, method, body) => makeRequest(window.appConfig.ApiEndpoint, path, method, body);
    const getSources = () => mainApi('/sources');
    const getGenres = () => mainApi('/genres');
    const getUserPreferences = () => mainApi('/preferences');
    const updatePreferences = (prefs) => mainApi('/preferences', 'PUT', prefs);
    const getTitles = () => mainApi('/titles');
    const getRecommendations = () => mainApi('/recommendations');

    // Admin API Calls
    const adminApi = (path, method, body) => makeRequest(window.appConfig.AdminApiEndpoint, path, method, body);
    const refreshReferenceData = () => adminApi('/admin/reference/refresh', 'POST');
    const refreshTitleData = () => adminApi('/admin/titles/refresh', 'POST');
    const triggerEnrichment = () => adminApi('/admin/titles/enrich', 'POST');
    const getDynamoDbSummary = () => adminApi('/admin/dynamodb/summary');

    return {
        getSources,
        getGenres,
        getUserPreferences,
        updatePreferences,
        getTitles,
        getRecommendations,
        refreshReferenceData,
        refreshTitleData,
        triggerEnrichment,
        getDynamoDbSummary
    };
})();
