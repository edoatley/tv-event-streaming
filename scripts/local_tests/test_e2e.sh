#!/bin/bash
################################################################
# Specialist integration test for UserPrefsTitleIngestionFunction
#
# This test performs the following steps:
# 1. Setup: Creates dummy user preference items in DynamoDB.
# 2. Execute: Invokes the Lambda function via 'sam local invoke'.
# 3. Verify: Polls the Kinesis stream to find the published
#    records and validates their content.
# 4. Teardown: Cleans up the dummy data from DynamoDB.
################################################################
DEBUG=true
# Exit on error, treat unset variables as an error
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#SCRIPT_DIR=${0:a:h}
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../../.." && pwd)

# Source the helper functions for colored output
# shellcheck source=test_helpers.sh
source "${SCRIPT_DIR}/test_helpers.sh"

# --- LocalStack & AWS Configuration ---
PROFILE_NAME="streaming"
ENDPOINT_URL="http://localhost:4566"
TABLE_NAME="UKTVProgrammesLocal"
STREAM_NAME="ProgrammeDataStreamLocal"
DOCKER_NETWORK="event-streaming-app_podman"

# --- Test Data ---
KINESIS_RECORDS_JSON="" # Global variable to hold the records for the consumer
TEST_USER_ID="test-user-for-ingestion-123"
# Define preferences. Note the overlapping genre '4' to test aggregation.
declare -a PREFERENCES=("source:203" "source:349" "genre:4" "genre:6")

# --- Helper Functions ---
# Sets up the prerequisite data in DynamoDB
setup_preferences() {
    print_info "Setting up prerequisite user preferences in DynamoDB..."
    for pref_sk in "${PREFERENCES[@]}"; do
        print_info "  - Adding preference: ${pref_sk}"
        aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
            dynamodb put-item \
            --table-name "${TABLE_NAME}" \
            --item "{\"PK\": {\"S\": \"userpref:${TEST_USER_ID}\"}, \"SK\": {\"S\": \"${pref_sk}\"}}"
    done
    print_success "✅ Setup complete."
}

# Cleans up the data from DynamoDB
teardown_test_data() {
     print_info "Cleaning up all test data from DynamoDB..."

    for pref_sk in "${PREFERENCES[@]}"; do
        aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
            dynamodb delete-item \
            --table-name "${TABLE_NAME}" \
            --key "{\"PK\": {\"S\": \"userpref:${TEST_USER_ID}\"}, \"SK\": {\"S\": \"${pref_sk}\"}}"
    done

     # Clean up title and index records created by the consumer
     if [[ -n "${KINESIS_RECORDS_JSON}" ]]; then
         # Use jq to iterate over each record found in the Kinesis stream
         echo "${KINESIS_RECORDS_JSON}" | jq -c '.Records[]' | while read -r record; do
             local decoded_payload
             decoded_payload=$(echo "$record" | jq -r '.Data' | base64 --decode)
             local title_id source_ids genre_ids
             title_id=$(echo "$decoded_payload" | jq -r '.payload.id')
             source_ids=$(echo "$decoded_payload" | jq -r '.payload.source_ids[]')
             genre_ids=$(echo "$decoded_payload" | jq -r '.payload.genre_ids[]')

             # Delete the canonical record
             aws dynamodb delete-item --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
             --table-name "${TABLE_NAME}" --key "{\"PK\": {\"S\": \"title:${title_id}\"}, \"SK\": {\"S\": \"record\"}}" > /dev/null

             # Delete all associated index records
             for sid in $source_ids; do
                 for gid in $genre_ids; do
                     aws dynamodb delete-item --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
                     --table-name "${TABLE_NAME}" --key "{\"PK\": {\"S\": \"source:${sid}:genre:${gid}\"}, \"SK\": {\"S\": \"title:${title_id}\"}}" > /dev/null
                 done
             done
         done
     fi

    print_success "✅ Teardown complete."
}


 # Verifies that the consumer correctly wrote data to DynamoDB
 verify_dynamodb_output() {
     print_info "Verifying DynamoDB output from consumer..."

     # Extract data from the first Kinesis record to build our assertions
     local first_record_data decoded_payload
     first_record_data=$(echo "${KINESIS_RECORDS_JSON}" | jq -r '.Records[0].Data')
     decoded_payload=$(echo "${first_record_data}" | base64 --decode)

     local title_id source_id genre_id
     title_id=$(echo "${decoded_payload}" | jq -r '.payload.id')
     source_id=$(echo "${decoded_payload}" | jq -r '.payload.source_ids[0]')
     genre_id=$(echo "${decoded_payload}" | jq -r '.payload.genre_ids[0]')

     # DEBUG: if DEBUG flag set scan the whole table and print the results with one item per line
     if [ "${DEBUG:-false}" = true ]; then
        aws dynamodb scan --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" --table-name "${TABLE_NAME}" --output json | jq -c '.Items[]'
     fi

     # 1. Verify the canonical record was created
     print_info "  - Checking for canonical title record..."
     local canonical_item
     canonical_item=$(aws dynamodb get-item --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" --table-name "${TABLE_NAME}" --key "{\"PK\": {\"S\": \"title:${title_id}\"}, \"SK\": {\"S\": \"record\"}}")

     if [ "${DEBUG:-false}" = true ]; then
         echo "${canonical_item}" | jq
     fi

     if [[ -z "${canonical_item}" || $(echo "${canonical_item}" | jq 'has("Item") | not') == "true" ]]; then
         print_error "❌ VERIFICATION FAILED: Canonical record for title ID ${title_id} not found."
         exit 1
     fi
     print_success "    - Canonical record found."

     # 2. Verify an inverted index record was created
     print_info "  - Checking for inverted index record..."
     local index_item
     if [ "${DEBUG:-false}" = true ]; then
       echo aws dynamodb get-item \
                     --profile "${PROFILE_NAME}" \
                     --endpoint-url "${ENDPOINT_URL}" \
                     --table-name "${TABLE_NAME}" \
                     --key "{\"PK\": {\"S\": \"source:${source_id}:genre:${genre_id}\"}, \"SK\": {\"S\": \"title:${title_id}\"}}"
     fi
     index_item=$(aws dynamodb get-item --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" --table-name "${TABLE_NAME}" --key "{\"PK\": {\"S\": \"source:${source_id}:genre:${genre_id}\"}, \"SK\": {\"S\": \"title:${title_id}\"}}")

     if [ "${DEBUG:-false}" = true ]; then
         echo "${index_item}" | jq
     fi

     if [[ -z "${index_item}" || $(echo "${index_item}" | jq 'has("Item") | not') == "true" ]]; then
         print_error "❌ VERIFICATION FAILED: Index record for source ${source_id} and genre ${genre_id} not found."
         exit 1
     fi

     print_success "    - Index record found."
 }

# Invokes the Lambda function
invoke_ingestion_lambda() {
    print_info "Invoking UserPrefsTitleIngestionFunction..."
    # We must be in the project root for sam to find the templates and build artifacts
    cd "${PROJECT_ROOT}"
    output_text=$(sam local invoke "UserPrefsTitleIngestionApp/UserPrefsTitleIngestionFunction" \
      --event "events/userprefs_title_ingestion.json" \
      --env-vars "env/userprefs_title_ingestion.json" \
      --docker-network "${DOCKER_NETWORK}" \
      < /dev/null 2>&1) || true
     exit_code=$?

     # Check for a non-zero exit code OR the string [ERROR] in the output
     if [[ $exit_code -ne 0 ]] || echo "${output_text}" | grep -q "\[ERROR\]"; then
         print_error "❌ FAILED: Invocation of UserPrefsTitleIngestionFunction failed."
         echo "${output_text}"
         exit 1
     fi

     if [ "${DEBUG:-false}" = true ]; then
         echo "${output_text}"
     fi

    print_success "✅ Lambda invoked."
}

# Polls Kinesis and verifies the output
verify_kinesis_output() {
    print_info "Verifying output on Kinesis stream '${STREAM_NAME}'..."

    # 1. Get the Shard ID
    local shard_id
    shard_id=$(aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
        kinesis describe-stream --stream-name "${STREAM_NAME}" | jq -r '.StreamDescription.Shards[0].ShardId')

    # 2. Get a shard iterator to start reading from the stream
    local shard_iterator
    shard_iterator=$(aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
        kinesis get-shard-iterator --stream-name "${STREAM_NAME}" --shard-id "${shard_id}" --shard-iterator-type TRIM_HORIZON | jq -r '.ShardIterator')

    # 3. Poll for records, as the process is asynchronous
    local records_json=""
    for i in {1..5}; do
        # Pass the current iterator to get-records
        records_json=$(aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
            kinesis get-records --shard-iterator "${shard_iterator}")

        # Update the iterator for the NEXT loop iteration
        shard_iterator=$(echo "${records_json}" | jq -r '.NextShardIterator')

         if [[ $(echo "${records_json}" | jq '.Records | length') -gt 0 ]]; then
             print_success "✅ Records found on Kinesis stream."
             KINESIS_RECORDS_JSON="${records_json}" # Store the result for the consumer
             break
         fi
        print_info "No records found yet, sleeping for 2 seconds... (Attempt $i/5)"
        sleep 2
    done

    if [[ -z "${records_json}" || $(echo "${records_json}" | jq '.Records | length') -eq 0 ]]; then
        print_error "❌ VERIFICATION FAILED: No records were found on the Kinesis stream after polling."
        exit 1
    fi

    # 4. Decode and validate the first record
    print_info "Validating the content of the first record..."
    local first_record_data
    first_record_data=$(echo "${KINESIS_RECORDS_JSON}" | jq -r '.Records[0].Data')

    local decoded_payload
    decoded_payload=$(echo "${first_record_data}" | base64 --decode)

    # Check that the publishing component is correct
    if echo "${decoded_payload}" | jq -e '.header.publishingComponent == "UserPrefsTitleIngestionFunction"' >/dev/null; then
        print_success "  - Header validation passed."
    else
        print_error "❌ VERIFICATION FAILED: Header 'publishingComponent' is incorrect."
        echo "Expected: UserPrefsTitleIngestionFunction"
        echo "Got: $(echo "${decoded_payload}" | jq '.header.publishingComponent')"
        exit 1
    fi

    # Check that the payload has the expected structure
    if echo "${decoded_payload}" | jq -e '.payload | has("id") and has("title")' >/dev/null; then
        print_success "  - Payload structure validation passed."
    else
        print_error "❌ VERIFICATION FAILED: Payload is missing 'id' or 'title' keys."
        echo "Payload received: ${decoded_payload}"
        exit 1
    fi
}


 # Invokes the consumer Lambda with the live data from Kinesis
 invoke_consumer_lambda() {
     print_info "Invoking TitleRecommendationsConsumerFunction with live Kinesis data..."

      # Create a temporary file for the event using mktemp for safety
      local event_file
      event_file=$(mktemp)

      # Transform the 'get-records' output into a valid Kinesis Lambda event format.
      # The 'aws kinesis get-records' command returns a different structure than what a
      # Lambda trigger provides. We use jq to build the expected structure.
      local transformed_event
      transformed_event=$(echo "${KINESIS_RECORDS_JSON}" | jq '{
          "Records": [
              .Records[] | { "kinesis": { "data": .Data, "partitionKey": .PartitionKey } }
          ]
      }')
      echo "${transformed_event}" > "${event_file}"

      # We must be in the project root for sam to find the templates and build artifacts
      cd "${PROJECT_ROOT}"

      local output_text
      local exit_code
      output_text=$(sam local invoke "TitleRecommendationsConsumerApp/TitleRecommendationsConsumerFunction" \
        --event "${event_file}" \
        --env-vars "env/title_recommendations_consumer.json" \
        --docker-network "${DOCKER_NETWORK}" \
        < /dev/null 2>&1) || true
      exit_code=$?

      # Clean up the temporary file
      rm "${event_file}"

      if [[ $exit_code -ne 0 ]] || echo "${output_text}" | grep -q "\[ERROR\]"; then
          print_error "❌ FAILED: Invocation of TitleRecommendationsConsumerFunction failed."
          echo "${output_text}"
          exit 1
      fi

      if [ "${DEBUG:-false}" = true ]; then
          echo "${output_text}"
      fi
      print_success "✅ Consumer Lambda invoked successfully."
}

# --- Main Execution ---
trap teardown_test_data EXIT # Use a trap to ensure teardown runs even if the script fails

print_info "===== START: Integration Test for UserPrefsTitleIngestionFunction ====="

print_info "--> STEP 1: Setting up test data..."
setup_preferences

print_info "--> STEP 2: Invoking the Lambda function..."
invoke_ingestion_lambda

print_info "--> STEP 3: Verifying the Kinesis output..."
verify_kinesis_output

print_info "--> STEP 4: Invoking the consumer with live data..."
invoke_consumer_lambda

print_info "--> STEP 5: Verifying the final DynamoDB state..."
verify_dynamodb_output

print_success "===== ✅ Integration Test Passed! ====="
