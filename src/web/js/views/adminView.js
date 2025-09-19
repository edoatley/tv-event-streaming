const adminView = (() => {
    function getHtml() {
        return `
            <div class="admin-panel">
                <h2 class="mb-4">Administrator Panel</h2>
                <div class="row">
                    <div class="col-md-6">
                        <div class="card mb-4">
                            <div class="card-header">Data Management</div>
                            <div class="card-body">
                                <div class="mb-3">
                                    <button id="refreshReferenceDataBtn" class="btn btn-secondary">Refresh Reference Data</button>
                                    <div id="refreshReferenceDataStatus" class="status-display mt-2"></div>
                                </div>
                                <div class="mb-3">
                                    <button id="refreshTitleDataBtn" class="btn btn-secondary">Refresh Title Data</button>
                                    <div id="refreshTitleDataStatus" class="status-display mt-2"></div>
                                </div>
                                <div>
                                    <button id="triggerEnrichmentBtn" class="btn btn-secondary">Trigger Enrichment</button>
                                    <div id="triggerEnrichmentStatus" class="status-display mt-2"></div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="card">
                            <div class="card-header">System Status</div>
                            <div class="card-body">
                                <button id="generateSummaryBtn" class="btn btn-info">Get DynamoDB Summary</button>
                                <div id="dynamoDbSummaryOutput" class="mt-3"></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    function render(appContainer) {
        appContainer.innerHTML = getHtml();
        attachEventListeners();
    }

    function attachEventListeners() {
        document.getElementById('refreshReferenceDataBtn').addEventListener('click', handleRefreshReferenceData);
        document.getElementById('refreshTitleDataBtn').addEventListener('click', handleRefreshTitleData);
        document.getElementById('triggerEnrichmentBtn').addEventListener('click', handleTriggerEnrichment);
        document.getElementById('generateSummaryBtn').addEventListener('click', handleGenerateSummary);
    }

    async function handleRefreshReferenceData() {
        const statusEl = document.getElementById('refreshReferenceDataStatus');
        statusEl.textContent = 'Refreshing...';
        try {
            const response = await api.refreshReferenceData();
            statusEl.textContent = response.message || 'Success';
        } catch (error) {
            statusEl.textContent = `Error: ${error.message}`;
        }
    }

    async function handleRefreshTitleData() {
        const statusEl = document.getElementById('refreshTitleDataStatus');
        statusEl.textContent = 'Refreshing...';
        try {
            const response = await api.refreshTitleData();
            statusEl.textContent = response.message || 'Success';
        } catch (error) {
            statusEl.textContent = `Error: ${error.message}`;
        }
    }

    async function handleTriggerEnrichment() {
        const statusEl = document.getElementById('triggerEnrichmentStatus');
        statusEl.textContent = 'Triggering...';
        try {
            const response = await api.triggerEnrichment();
            statusEl.textContent = response.message || 'Success';
        } catch (error) {
            statusEl.textContent = `Error: ${error.message}`;
        }
    }

    async function handleGenerateSummary() {
        const outputEl = document.getElementById('dynamoDbSummaryOutput');
        outputEl.textContent = 'Generating...';
        try {
            const summary = await api.getDynamoDbSummary();
            let summaryHtml = '<ul>';
            summary.tables.forEach(table => {
                summaryHtml += `<li><strong>${table.name}</strong>: Items: ${table.item_count}, Size: ${table.size_bytes} bytes</li>`;
            });
            summaryHtml += '</ul>';
            outputEl.innerHTML = summaryHtml;
        } catch (error) {
            outputEl.textContent = `Error: ${error.message}`;
        }
    }

    return { render };
})();
