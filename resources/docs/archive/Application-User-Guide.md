# Application User Guide

This document provides a guide for both end-users and administrators of the Event Streaming application.

## System Architecture

The application is built on a serverless, event-driven architecture using AWS services. The following diagram illustrates the main components and data flows:

```mermaid
graph TD
    subgraph "User Interaction"
        direction LR
        User(fa:fa-user User) --> APIGW[/\"API Gateway\"/]
        APIGW -- Authorizes with --> Cognito[/\"Cognito User Pool\"/]
        APIGW -- Invokes --> UserPrefsLambda[fa:fa-lambda UserPreferencesFunction]
    end

    subgraph "Scheduled Ingestion"
        direction TB
        EventBridge(fa:fa-clock EventBridge Rule)
        EventBridge -- Triggers --> RefDataLambda[fa:fa-lambda PeriodicReferenceFunction]
        EventBridge -- Triggers --> TitleIngestionLambda[fa:fa-lambda UserPrefsTitleIngestionFunction]
    end

    subgraph "Event-Driven Processing"
        direction TB
        KinesisStream(fa:fa-stream Kinesis Data Stream) -- Invokes --> TitleConsumerLambda[fa:fa-lambda TitleRecommendationsConsumerFunction]
        TitleConsumerLambda -- Writes to --> DynamoDB(fa:fa-database DynamoDB Table)
        DynamoDB -- Creates Event --> DynamoDBStream(fa:fa-bolt DynamoDB Stream)
        DynamoDBStream -- Invokes --> TitleEnrichmentLambda[fa:fa-lambda TitleEnrichmentFunction]
    end

    subgraph "Shared AWS Services"
        direction TB
        SecretsManager(fa:fa-key Secrets Manager)
    end

    subgraph "External Services"
        WatchModeAPI[/\"api.watchmode.com\"/]
    end

    %% --- Data & Event Flows ---
    UserPrefsLambda -- Reads/Writes User Prefs --> DynamoDB

    RefDataLambda -- Gets API Key --> SecretsManager
    RefDataLambda -- Fetches Sources/Genres --> WatchModeAPI
    RefDataLambda -- Writes Reference Data --> DynamoDB

    TitleIngestionLambda -- Gets API Key --> SecretsManager
    TitleIngestionLambda -- Reads All User Prefs --> DynamoDB
    TitleIngestionLambda -- Fetches Titles --> WatchModeAPI
    TitleIngestionLambda -- Publishes Events --> KinesisStream

    TitleEnrichmentLambda -- Gets API Key --> SecretsManager
    TitleEnrichmentLambda -- Fetches Details --> WatchModeAPI
    TitleEnrichmentLambda -- Updates Title Record --> DynamoDB
```

## End-User Guide

This guide explains how to use the main features of the TV Guide web application.

### Authentication

To access the application, you must first log in. The application uses AWS Cognito for secure authentication. A test user is available with the email `test.user@example.com`.

### Managing Your Preferences

After logging in, you can personalize your content by setting your preferences for streaming sources and genres.

*   The application will display your currently selected preferences.
*   You can update your choices at any time using the checkboxes provided and clicking "Update Preferences".
*   Your preferences are saved and will be used to filter the titles shown to you.

### Browsing Titles

The application presents titles in two main views accessible via tabs:

*   **All Titles Tab:** This tab displays all available TV shows and movies that match your selected preferences.
*   **Recommendations Tab:** This tab shows a curated list of new, high-rated titles (with a user rating greater than 7) that match your preferences.

Each title is displayed on a card showing its image, rating, and a brief description. You can click on any card to view more detailed information.

## Administrator Guide

This guide is for administrators responsible for managing the application's backend processes. Access to the admin panel is restricted to authorized users.

### Admin Panel Overview

The administrator panel provides a centralized interface for triggering data management tasks and monitoring system status.

**Header:**
*   **Application Title:** "TV Guide Admin Panel"
*   **User Login Status:** Displays the currently logged-in admin user.
*   **Logout Button:** Ends the admin session.

**Main Content Area:**
The main area is divided into two key sections: Data Management and System Status.

#### Data Management
This section allows administrators to manually trigger the application's data processing workflows. Each action has a button to initiate the process and a status display to show progress ("In Progress", "Completed", or "Error").

*   **Refresh Reference Data:** Initiates a process to fetch the latest reference data (e.g., streaming sources, genres) from the external WatchMode API and store it in DynamoDB.
*   **Refresh Title Data:** Triggers the ingestion of title data based on all users' preferences.
*   **Trigger Enrichment for Unenriched Titles:** Starts a process to fetch detailed information (e.g., plot summary, poster image) for titles that have not yet been enriched.

#### System Status
*   **DynamoDB Data Summary:** This feature provides a summary of data stored in DynamoDB, including table sizes and item counts. Clicking "Generate Full Summary" will trigger a function to generate and display a detailed report.
