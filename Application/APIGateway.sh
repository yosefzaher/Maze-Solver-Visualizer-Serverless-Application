#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r) 
set -o pipefail

API_NAME="test-http-api"
ROUTES_KEYS=("POST /solve/bfs" "POST /solve/dfs" "POST /solve/astar")

log()
{
    # $1 is the Log Message 
    echo "[INFO] $1" >&2
}

err()
{
    # $1 is the Error Message
    echo "[ERROR] $1" >&2
}

get_api_id()
{
    # $1 API Name you Want to get it's ID
    local api_name="$1"
    aws apigatewayv2 get-apis --output json --query "Items[?Name == '$api_name']" | grep -oP '(?<="ApiId": ")[^"]*' || true
}

create_api()
{
    # $1 is the Name of API 

    local api_name="$1" 
    local api_check
    local api_creation_result
    local api_id
    
    # Check The API if Already Exist
    api_check=$(get_api_id "$api_name")


    if [ "$api_check" == "" ]; then

        log "Creating API..."

        # Create The API if it is doesn't Exist
        api_creation_result=$(aws apigatewayv2 create-api --name "$api_name" \
        --protocol-type HTTP \
        --output json)

        api_id=$(echo "$api_creation_result" | grep -oP '(?<="ApiId": ")[^"]*')

        # Check if the API is Created Successfully or Not
        if [ "$api_id" == "" ]; then

            # Error in Creating the API
            err "Error in Creating API."
            exit 1

        fi

        # API is Successfully Created
        log "API Created Successfully."
        echo "$api_id"

    else 

        # API is Already Exist
        log "$api_name API is Exist." 
        api_id=$api_check
        echo "$api_id"
    fi
}

create_route()
{
    # $1 is the ID of API you Create the Route in ,$2 is the Route Key (ex: POST /solve/dfs,etc..)

    local api_id="$1"
    local route_key="$2"
    local api_routes_check
    local route_key_check
    local route_key_id

    # Check if Route is Exist Already or Not
    api_routes_check=$(aws apigatewayv2 get-routes --api-id "$api_id" \
        --output json \
        --query "Items[?RouteKey == '$route_key']")

    route_key_check=$(echo "$api_routes_check" | grep -oP '(?<="RouteId": ")[^"]*' || true)

    if [ "$route_key_check" == "" ]; then

        # Create the Route if it is Not Exist
        route_key_id=$(aws apigatewayv2 create-route --api-id "$api_id" \
                        --route-key "$route_key" \
                        | grep -oP '(?<="RouteId": ")[^"]*')


        if [ "$route_key_id" == "" ]; then
            
            # Error in Creating the Route
            err "Error in Creating Route $route_key"
            exit 1

        fi

        # The Route Successfully Created
        log "Route $route_key is Created Successfully."

    else 
        # The Route is Already Exist
        log "Route $route_key is Already Exist."
        route_key_id=$route_key_check

    fi
}

TARGET_API_ID=$(create_api "$API_NAME")

for route_key in "${ROUTES_KEYS[@]}"; do

    create_route "$TARGET_API_ID" "$route_key"

done

log "All Done !"
