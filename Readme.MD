# Event Streaming app

## Table of contents

<!-- TOC -->
* [Event Streaming app](#event-streaming-app)
  * [Table of contents](#table-of-contents)
  * [Current Status & Future Plan](#current-status--future-plan)
    * [Completed Milestones:](#completed-milestones)
    * [Next Steps & Enhancements:](#next-steps--enhancements)
  * [Target Architecture diagram](#target-architecture-diagram)
  * [Step 1 - Initial set up](#step-1---initial-set-up)
  * [Step 2 - Shared infrastructure set up](#step-2---shared-infrastructure-set-up)
  * [Step 3 - Periodic Ingestion Lambda (basic deployment)](#step-3---periodic-ingestion-lambda-basic-deployment)
  * [Step 4 - WatchMode initial integration](#step-4---watchmode-initial-integration)
    * [Sources](#sources)
    * [Genres](#genres)
  * [Step 5 - SAM Project cleanup](#step-5---sam-project-cleanup)
  * [Step 6 - Preferences API](#step-6---preferences-api)
  * [Step 7 - Call API to get some shows for all known genres and source](#step-7---call-api-to-get-some-shows-for-all-known-genres-and-source)
  * [Step 9 - read title data published to kinesis](#step-9---read-title-data-published-to-kinesis)
  * [Step 10 - publish title data to kinesis](#step-10---publish-title-data-to-kinesis)
    * [LocalStack setup](#localstack-setup)
    * [Specialist Test Script for Title Ingestion](#specialist-test-script-for-title-ingestion)
  * [Step 11 - store title data to DynamoDB](#step-11---store-title-data-to-dynamodb)
  * [Step 12 - enrich the stored title data in DynamoDB](#step-12---enrich-the-stored-title-data-in-dynamodb)
  * [Step 13 - deploy to AWS and run an E2E test (taking cost safeguards)](#step-13---deploy-to-aws-and-run-an-e2e-test-taking-cost-safeguards)
  * [Step 14 - add the EventBridge triggers](#step-14---add-the-eventbridge-triggers)
  * [Step 15 - single page web application hosted on S3](#step-15---single-page-web-application-hosted-on-s3)
    * [What's Been Added](#whats-been-added)
    * [Deployment Steps](#deployment-steps)
    * [Website Features](#website-features)
  * [Step 16 - Administrator screen](#step-16---administrator-screen)
    * [Admin Screen UI Design](#admin-screen-ui-design)
      * [Header](#header)
      * [Main Content Area](#main-content-area)
        * [Data Management Section](#data-management-section)
        * [System Status Section](#system-status-section)
    * [Admin API Design](#admin-api-design)
      * [Endpoints](#endpoints)
    * [DynamoDB Data Summary Implementation Plan](#dynamodb-data-summary-implementation-plan)
    * [Security Admin Implementation Plan](#security-admin-implementation-plan)
    * [New Admin Lambda Function Scope and Responsibilities](#new-admin-lambda-function-scope-and-responsibilities)
    * [Admin UI Integration Plan](#admin-ui-integration-plan)
    * [Testing plan](#testing-plan)
  * [Step 17 - Web UI tests and pipeline for deployment](#step-17---web-ui-tests-and-pipeline-for-deployment)
    * [In progress](#in-progress)
      * [Review Scripts](#review-scripts)
      * [Setup a Cloudformation pipeline in a secure way to deploy the application](#setup-a-cloudformation-pipeline-in-a-secure-way-to-deploy-the-application)
  * [Step 18 - schedule the API calls to get the shows and make it efficient](#step-18---schedule-the-api-calls-to-get-the-shows-and-make-it-efficient)
  * [Cleanup](#cleanup)
<!-- TOC -->

## Current Status & Future Plan
 
The project has made significant progress in establishing the backend data ingestion and API infrastructure. The current focus is on enhancing the user interface and administrative capabilities.

### Completed Milestones:
- [x] Store TV reference data: A Lambda function periodically fetches reference data (sources, genres) and stores it in DynamoDB.
- [x] User Preferences API: A RESTful API via API Gateway and Lambda manages user preferences (sources, genres).
- [x] Ingest TV and streaming data: A Lambda function periodically fetches TV schedules and streaming availability based on user preferences.
- [x] Store the program guide: Processed data is stored in a DynamoDB table, optimized for querying.
- [x] Process and enrich the data: Raw data is sent to Kinesis, consumed by a Lambda, cleaned, and enriched with additional information (e.g., ratings).
- [x] Real-time updates: DynamoDB Streams capture changes, triggering a Lambda for further processing (e.g., notifications).
- [x] Add Google IdP federation: Google Identity Provider federation is integrated.
- [x] Provide a single page web app user interface (a static website hosted on S3) and login with Google credentials.
- [x] Extend the web app to query API Gateway endpoints to display the TV offerings, update user preferences, etc.
- [x] Create Comprehensive User Guide.

### Next Steps & Enhancements:
- [ ] **Implement Admin Screen:** Develop an administrative interface within the web UI to trigger backend data ingestion processes manually.
- [ ] **Robust automated tests:** enhance the bespoke testing approach with a test pack that validates the deployed application.

## Target Architecture diagram

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

## Step 1 - Initial set up

To get started I wanted to log in securely from my laptop and so set up IAM Identity Center as described in more detail [here](../../../identity/IAM-Identity-Center.MD)

I then checked this works with:

```bash
aws sts get-caller-identity --profile streaming
{
"UserId": "AROA2SWQYMDM4VPUQEQLJ:edoatley",
"Account": "727361020121",
"Arn": "arn:aws:sts::727361020121:assumed-role/AWSReservedSSO_AdministratorAccess_2953d82af9279092/edoatley"
}
```

## Step 2 - Shared infrastructure set up

1. set up some shared infrastructure using this [CloudFormation template](resources/shared-infra.yaml)

2. Deployed the shared infrastructure with:

```bash
aws cloudformation deploy \
--template-file ./resources/shared-infra.yaml \
--stack-name uk-tv-guide-shared-infra \
--capabilities CAPABILITY_IAM \
--profile streaming
```

## Step 3 - Periodic Ingestion Lambda (basic deployment)

1. set up this [Periodic Ingestion CloudFormation template](cloudformation/userprefs-title-ingestion.yaml) to deploy the resources
   associated with our first function called **PeriodicUKTVDataIngestionFunction**

2. Built the app using sam:

```bash
sam build --template-file ./resources/userprefs-title-ingestion.yaml --profile streaming
```

3. Run a local test with a [test event](events/userprefs_title_ingestion.json) and [environment config](env/userprefs_title_ingestion.json):

```bash
sam local invoke PeriodicDataIngestionFunction \
  --template-file ./resources/userprefs-title-ingestion.yaml \
  --event ./events/userprefs_title_ingestion.json \
  --env-vars ./env/userprefs_title_ingestion.json \
  --profile streaming
```

4. Deploy the lambda

```bash
# First time need to define the config hence --guided
sam deploy --guided --profile streaming --capabilities CAPABILITY_NAMED_IAM
# Thereafter can reference the config file
sam deploy --profile streaming --capabilities CAPABILITY_NAMED_IAM
```

5. Test the deployed Lambda function

```bash
sam remote invoke PeriodicUKTVDataIngestionFunction \
  --event ./events/userprefs_title_ingestion.json \
  --profile streaming  
```

6. To save cost we can now undeploy it so we can work on the next steps

```bash
sam delete --profile streaming
```

## Step 4 - WatchMode initial integration

For this service to really work we need a source of TV information for which we will leverage [Watchmode](https://api.watchmode.com/)


This service offers a vast number of APIs but some of the ones of interest for us:

- `/v1/changes/new_titles/` - [Changes > New Titles] (https://api.watchmode.com/docs#new-titles)
- `/v1/title/{title_id}/details/` - [Title Details API](https://api.watchmode.com/docs#title-details)

### Sources

Watchmode has various static data such as sources of TV programmes (`/v1/sources/`). 

It seems like a good idea to create another lambda to save this data to dynamoDB to avoid extra calls. We will create this
lambda [here](/src/periodic_reference_data) and create a CFN template [here](cloudformation/periodic-reference.yaml)

We can pass a region of **GB** to `/v1/sources/` to get sources applicable in the UK. 

### Genres

Watchmode also has a set of genres (`/v1/genres/`). We will extend our lambda to store this data.

## Step 5 - SAM Project cleanup

At this point I hit a bit of an issue. I was having to specify template files in my sam commands to switch between the 
different serverless applications and when I built the reference data app it would delete any builds of the ingestion 
app etc.

I needed a way to have CloudFormation and SAM handle this leaving me to run commands like:

```bash
sam validate
sam build
sam deploy
```

To do this I made tome key changes:

1. Created a `samconfig.toml` that pointed to my new parent CloudFormation template for the validate/build/deploy commands
2. Took the Secret, Table, Stream, S3 bucket resources and added them to the parent CFN template [uktv-event-streaming-app.yaml](cloudformation/uktv-event-streaming-app.yaml)
3. Created `AWS::Serverless::Application` resource in teh parent that point to [periodic-ingestion.yaml](cloudformation/userprefs-title-ingestion.yaml) 
and [periodic-reference.yaml](./resources/periodic-reference.yaml].

With some tweaks the whole application is build on one SAM app but it is broken down into appropriate files to manage
which means when we add the next lambda it will be trivial.

The `samconfig.toml` looks something like this:

```toml
[default.build.parameters]
template_file = "resources/uktv-event-streaming-app.yaml"
cached = true
parallel = true
[default.validate.parameters]
template_file = "resources/uktv-event-streaming-app.yaml"
[default.local_invoke.parameters]
profile = "<PROFILE NAME>"
region = "eu-west-2"
[default.remote_invoke.parameters]
profile = "<PROFILE NAME>"
region = "eu-west-2"
[default.deploy.parameters]
stack_name = "uktv-event-streaming-app"
resolve_s3 = true
s3_prefix = "uktv-event-streaming-app"
region = "eu-west-2"
profile = "<PROFILE NAME>"
```

## Step 6 - Preferences API

This is very similar to the previous two lambdas in many ways except this time we need to have API Gateway fronting the 
lambda and ideally a pool of user personas we can use to test it out. 

The API is going to be defined in the following [OpenAPI specification](cloudformation/user-preferences-api.yaml). 
As you can see the endpoints provided are:

- `GET /preferences` - get the users preferences
- `PUT /preferences` - update the users preferences
- `GET /sources` - list the available sources
- `GET /genres` - list the available genres

In the [main CFN template](cloudformation/uktv-event-streaming-app.yaml) we have added:

- `AWS::Cognito::UserPool`
- `AWS::Cognito::UserPoolClient`
- `AWS::Cognito::UserPoolUser`

and we have created a Lambda to handle the API requests in [user_preferences/preferences.py](src/user_preferences/preferences.py)

## Step 7 - Call API to get some shows for all known genres and source

We now have user preferences for source and genre saved and we must retrieve the shows these provide. 

Reviewing the [Watchmode List Titles API](https://api.watchmode.com/docs#list-titles) seems a good fit to get started.

## Step 9 - read title data published to kinesis

We will create a new function `TitleRecommendationsConsumerFunction` that expects an event and will for now
just log it to the console. This function will live in its own nested stack defined in `resources/title-recommendations-consumer.yaml`
and its code in `src/title_recommendations_consumer/`.

## Step 10 - publish title data to kinesis

To make it clearer what the component doing this publishing is doing we will rename `PeriodicUKTVDataIngestionFunction`
to `PeriodicUKTitlesForUserPrefsFunction` and files named `periodic-ingestion*` to `userprefs-title-ingestion*`. The logic
for the newly named `PeriodicUKTitlesForUserPrefsFunction` will be:

1. Scan the DynamoDB table for all items with a PK starting with `userpref:`.
2. Aggregate all unique source and genre IDs from these preferences.
3. Call the WatchMode `/v1/list-titles` API with the aggregated IDs.
4. For each title returned, create a Kinesis record with the new data model.
5. Publish all records to the Kinesis stream in a batch.

### LocalStack setup

To avoid deploying all the services to AWS for testing, we will use LocalStack.

- A docker compose file defines the localstack services: [docker-compose.yaml](docker-compose.yaml)
- A script initializes the local resources: [local-test-setup.sh](scripts/local_tests/local_setup.sh).
- WatchMode API keys are stored in the LocalStack Secrets Manager.
- A script runs all local tests: [resources/local-test-execute-all.sh](./resources/local-test-execute-all.sh]

The local development workflow is as follows:

1. **Start LocalStack:** `docker compose up`.
2. **Initialize Resources:** `./resources/local-test-setup.sh`.
3. **Run Local Tests:** use [resources/local-test-execute-all.sh](./resources/local-test-execute-all.sh] to run all the tests.

### Specialist Test Script for Title Ingestion

A specialist script [test_e2e.sh](scripts/local_tests/test_e2e.sh) performs a full integration test of the `UserPrefsTitleIngestionFunction`.

## Step 11 - store title data to DynamoDB

The `TitleRecommendationsConsumerFunction` will:

1. Subscribe to Kinesis and read Title events.
2. Write a record to DynamoDB with PK `source:<source_id>:genre:<genre_id>` and SK `title:<title_id>`.
3. Write a canonical title record to DynamoDB with PK `title:<title_id>` and SK `record`.

## Step 12 - enrich the stored title data in DynamoDB

A new `TitleEnrichmentFunction` is triggered by a DynamoDB Stream on the `ProgrammesTable`.

1.  It processes `INSERT` events for canonical title records.
2.  For each new title, it calls the WatchMode `/v1/title/{title_id}/details/` API.
3.  It updates the title record in DynamoDB with the enriched data (e.g., `plot_overview`, `poster`).

## Step 13 - deploy to AWS and run an E2E test (taking cost safeguards)

We now have the majority of the event pipeline working. We now can deploy it to AWS for real and run a basic test. The steps are automated in [remote_deploy_and_smoke_test.sh](scripts/remote_tests/remote_deploy_and_smoke_test.sh).

## Step 14 - add the EventBridge triggers

EventBridge triggers are defined in CloudFormation to:

- Perform a daily call to `PeriodicReferenceFunction`.
- Perform a `UserPrefsTitleIngestionFunction` daily call.

## Step 15 - single page web application hosted on S3

This step adds a single page web application (SPA) that provides user authentication and displays TV titles and recommendations from DynamoDB.

### What's Been Added

- **CloudFormation Resources**: `S3 Bucket`, `WebsiteDeploymentFunction`, `WebApiApp` nested stack.
- **Website Files**: `index.html`, `error.html`, `app.js` are deployed to S3.
- **API Endpoints**: `/titles` and `/recommendations`.

### Deployment Steps

1.  **Deploy the CloudFormation Stack** using `sam deploy` or `aws cloudformation deploy`.
2.  **Update Website Configuration** by running the `update_website_config.sh` script to inject the correct Cognito and API Gateway endpoint values into `app.js`.
3.  **Access the Website** via the `WebsiteUrl` output from CloudFormation.

### Website Features

- **User Authentication**: Uses AWS Cognito. Test user: `test.user@example.com`.
- **User Preferences**: Display and update streaming source and genre preferences.
- **Content Display**: "All Titles" and "Recommendations" tabs with clickable title cards.
- **Responsive Design**: Bootstrap-based, mobile-friendly UI.

## Step 16 - Administrator screen

This section outlines the design for the administrator screen, covering UI, API, security, and integration aspects.

### Admin Screen UI Design

The admin screen is designed for clarity and ease of use, providing distinct sections for administrative tasks.

#### Header
*   **Application Title:** "TV Guide Admin Panel"
*   **User Login Status:** Display "Logged in as: [Username]"
*   **Logout Button**

#### Main Content Area
This area will be divided into logical sections for different administrative tasks.

##### Data Management Section
*   **Reference Data Refresh:**
    *   Button: "Refresh Reference Data"
    *   Status Display: Shows "In Progress", "Completed", or "Error" with timestamps.
    *   Logs/Details: A collapsible section for viewing execution logs or detailed status.
*   **Title Data Refresh:**
    *   Button: "Refresh Title Data"
    *   Status Display.
    *   Logs/Details.
*   **Title Enrichment:**
    *   Button: "Trigger Enrichment for Unenriched Titles"
    *   Status Display.
    *   Logs/Details.
    *   (Optional: Display a count of unenriched titles.)

##### System Status Section
*   **DynamoDB Data Summary:**
    *   Display of key metrics (e.g., table sizes, item counts).
    *   Button: "Generate Full Summary" (This will trigger a detailed report).
    *   Display Area: For the summary output.

### Admin API Design

The admin API will be a RESTful API, likely exposed via API Gateway and integrated with a new Lambda function.

#### Endpoints

*   **Trigger Reference Data Refresh**: `POST /admin/data/reference/refresh`
*   **Trigger Title Data Refresh**: `POST /admin/data/titles/refresh`
*   **Trigger Title Enrichment**: `POST /admin/data/titles/enrich`
*   **Get DynamoDB Data Summary**: `GET /admin/system/dynamodb/summary`

### DynamoDB Data Summary Implementation Plan

The admin Lambda function will query DynamoDB to gather table metadata.
*   **Identify Tables:** Table names will be identified from the CloudFormation template.
*   **Query Metadata:** Use Boto3 to get item count and size for each table.
*   **Permissions:** The Lambda's IAM role requires `dynamodb:ListTables` and `dynamodb:DescribeTable` permissions.

### Security Admin Implementation Plan

*   **User Management:** Use AWS IAM Identity Center to create a "Security Admin" group and assign users.
*   **Authentication:** Implement federated login via IAM Identity Center for the admin screen.
*   **Authorization:** Use API Gateway authorizers to validate user credentials and permissions.
*   **Frontend Protection:** Implement client-side checks to restrict access to admin UI elements.

### New Admin Lambda Function Scope and Responsibilities

*   **Language/Runtime:** Python.
*   **Triggers:** API Gateway.
*   **Responsibilities:**
    *   Handle API requests.
    *   Orchestrate data operations.
    *   Work with API Gateway authorizers for security.
*   **IAM Permissions:** `lambda:InvokeFunction`, `dynamodb:ListTables`, `dynamodb:DescribeTable`.

### Admin UI Integration Plan

*   **API Configuration:** Store the admin API Gateway base URL in a configuration file.
*   **Authentication Token:** Obtain and include tokens in `Authorization` headers for API requests.
*   **Making API Calls:** Use JavaScript (`fetch` API) for API calls.
*   **User Feedback:** Provide clear messages for success, ongoing operations, and errors.
*   **Frontend Protection:** Ensure admin-specific UI elements are only visible for authenticated "Security Admins".

### Testing plan

*   **Testing user:** Create a new user `TestAdminUser` in Cloudformation with the email `admin.user@example.com`.
*   **Unit Tests:** Create unit tests using pytest to validate the admin API lambda function.
*   **Integration Tests:** Use a script to test the deployed API via API Gateway.

## Step 17 - Web UI tests and pipeline for deployment

Now most stuff is working we will stabilise by:

1. Reviewing test scripts to validate they all work and rationalising
2. Adding A UI test suite
3. Reviewing security and ensuring it is robust
4. Define a deployment pipeline

### In progress

#### Review Scripts

| Script                                                                                  | Purpose | Working? | Fate |
|-----------------------------------------------------------------------------------------|---------|----------|------|
| [local_setup.sh](scripts/local_tests/local_setup.sh)                                    |         |          |      |
| [run_tests.sh](scripts/local_tests/run_tests.sh)                                        |         |          |      |
| [test_e2e.sh](scripts/local_tests/test_e2e.sh)                                          |         |          |      |
| [test_enrichment.sh](scripts/local_tests/test_enrichment.sh)                            |         |          |      |
| [test_helpers.sh](scripts/local_tests/test_helpers.sh)                                  |         |          |      |
| [account-level-cwlogs.sh](scripts/utils/account-level-cwlogs.sh)                        |         |          |      |
| [debug_preferences_endpoint.sh](scripts/remote_tests/debug_preferences_endpoint.sh)     |         |          |      |
| [dynamodb_inspector.sh](scripts/utils/dynamodb_inspector.sh)                            |         |          |      |
| [get_lambda_logs.sh](scripts/utils/get_lambda_logs.sh)                                  |         |          |      |
| [remote_deploy.sh](scripts/deploy/remote_deploy.sh)                                     |         |          |      |
| [remote_deploy_and_smoke_test.sh](scripts/remote_tests/remote_deploy_and_smoke_test.sh) |         |          |      |
| [remote_web_api_tests.sh](scripts/remote_tests/remote_web_api_tests.sh)                 |         |          |      |
| [run_admin_api_tests.sh](scripts/remote_tests/run_admin_api_tests.sh)                   |         |          |      |
| [set-cognito-password.sh](scripts/deploy/set-cognito-password.sh)                       |         |          |      |
| [teardown.sh](scripts/deploy/teardown.sh)                                               |         |          |      |
| [update_website_config.sh](scripts/deploy/update_website_config.sh)                     |         |          |      |

#### Setup a Cloudformation pipeline in a secure way to deploy the application


## Step 18 - schedule the API calls to get the shows and make it efficient

The current title ingestion process is inefficient. A more efficient approach would be to:
1.  Gather all unique **source and genre combinations** that users have explicitly selected.
2.  Make a single, paginated API call to WatchMode that can filter on these specific combinations.

## Cleanup
 
Delete the shared resources:
 
```bash
aws cloudformation delete-stack \
  --stack-name uk-tv-guide-shared-infra \
  --profile streaming
```
