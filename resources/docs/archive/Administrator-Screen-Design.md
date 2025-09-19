# Administrator Screen Design Document

This document outlines the design for the administrator screen, covering UI, API, security, and integration aspects.

## 1. Admin Screen UI Design

The admin screen is designed for clarity and ease of use, providing distinct sections for administrative tasks.

### 1.1. Header
*   **Application Title:** "TV Guide Admin Panel"
*   **User Login Status:** Display "Logged in as: [Username]"
*   **Logout Button**

### 1.2. Main Content Area
This area will be divided into logical sections for different administrative tasks.

#### 1.2.1. Data Management Section
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

#### 1.2.2. System Status Section
*   **DynamoDB Data Summary:**
    *   Display of key metrics (e.g., table sizes, item counts).
    *   Button: "Generate Full Summary" (This will trigger a detailed report, potentially by executing a backend function that mimics `dynamodb_inspector.sh`).
    *   Display Area: For the summary output.

## 2. Admin API Design

The admin API will be a RESTful API, likely exposed via API Gateway and integrated with a new Lambda function.

### 2.1. Endpoints

*   **Trigger Reference Data Refresh**
    *   **HTTP Method:** `POST`
    *   **Path:** `/admin/reference/refresh`
    *   **Request Body:** (Optional) Empty.
    *   **Response:**
        *   `202 Accepted`: Indicates the refresh process has been initiated.
        *   **Response Body:** `{ "message": "Reference data refresh initiated.", "job_id": "..." }`
        *   `400 Bad Request`
        *   `500 Internal Server Error`

*   **Trigger Title Data Refresh**
    *   **HTTP Method:** `POST`
    *   **Path:** `/admin/titles/refresh`
    *   **Request Body:** (Optional) Empty.
    *   **Response:**
        *   `202 Accepted`: Indicates the refresh process has been initiated.
        *   **Response Body:** `{ "message": "Title data refresh initiated.", "job_id": "..." }`
        *   `400 Bad Request`
        *   `500 Internal Server Error`

*   **Trigger Title Enrichment**
    *   **HTTP Method:** `POST`
    *   **Path:** `/admin/titles/enrich`
    *   **Request Body:** (Optional) Empty.
    *   **Response:**
        *   `202 Accepted`: Indicates the enrichment process has been initiated.
        *   **Response Body:** `{ "message": "Title enrichment process initiated.", "job_id": "..." }`
        *   `400 Bad Request`
        *   `500 Internal Server Error`

*   **Get DynamoDB Data Summary**
    *   **HTTP Method:** `GET`
    *   **Path:** `/admin/dynamodb/summary`
    *   **Request Body:** None.
    *   **Response:**
        *   `200 OK`:
        *   **Response Body:** A JSON object containing summary statistics. Example:
            ```json
            {
              "tables": [
                {
                  "name": "SourcesTable",
                  "item_count": 100,
                  "size_bytes": 102400
                },
                {
                  "name": "TitlesTable",
                  "item_count": 5000,
                  "size_bytes": 5120000
                }
              ],
              "message": "DynamoDB data summary retrieved successfully."
            }
            ```
        *   `500 Internal Server Error`

## 3. DynamoDB Data Summary Implementation Plan

The admin Lambda function will query DynamoDB to gather table metadata.
*   **Identify Tables:** Table names will be identified from the CloudFormation template (`uktv-event-streaming-app.yaml`).
*   **Query Metadata:** Use Boto3 to get item count and size for each table.
*   **Permissions:** The Lambda's IAM role requires `dynamodb:ListTables` and `dynamodb:DescribeTable` permissions.

## 4. Security Admin Implementation Plan

*   **User Management:** Use AWS IAM Identity Center to create a "Security Admin" group and assign users.
*   **Authentication:** Implement federated login via IAM Identity Center for the admin screen.
*   **Authorization:** Use API Gateway authorizers to validate user credentials and permissions for admin API endpoints.
*   **Frontend Protection:** Implement client-side checks to restrict access to admin UI elements.

## 5. New Admin Lambda Function Scope and Responsibilities

*   **Language/Runtime:** Python.
*   **Dependencies:** Boto3.
*   **Triggers:** API Gateway.
*   **Responsibilities:**
    *   Handle API requests.
    *   Orchestrate data operations (triggering other Lambdas, querying DynamoDB).
    *   Work with API Gateway authorizers for security.
    *   Logging and error handling.
*   **IAM Permissions:** `lambda:InvokeFunction`, `dynamodb:ListTables`, `dynamodb:DescribeTable`, CloudWatch Logs permissions.

## 6. Admin UI Integration Plan

*   **API Configuration:** Store the admin API Gateway base URL in a configuration file.
*   **Authentication Token:** Obtain and include tokens in `Authorization` headers for API requests.
*   **Making API Calls:** Use JavaScript (e.g., `fetch` API) for `POST` requests (refresh/trigger) and `GET` requests (summary).
*   **User Feedback:** Provide clear messages for success, ongoing operations, and errors.
*   **Frontend Protection:** Ensure admin-specific UI elements are only visible/interactive for authenticated "Security Admins".

## 7. Testing plan

*   **Testing user:** Create a new user `TestAdminUser` in Cloudformation like the current TestUser (test.user@example.com), use the email `admin.user@example.com`
*   **Unit Tests:** - create simple unit tests using pytest to validate the admin API lambda function.
*   **Integration Tests:** use a script like [remote_web_api_tests.sh](../../scripts/remote_web_api_tests.sh) to test the deployed API via API Gateway