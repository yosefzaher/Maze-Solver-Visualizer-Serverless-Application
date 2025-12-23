#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r) 
set -o pipefail

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

get_function_arn()
{
    # $1 is the Function Name

    local lambda_name=$1
    local lambda_arn

    # Get The ARN of The Function 
    lambda_arn=$(aws lambda list-functions \
                     --output json \
                     --query "Functions[?FunctionName == '$lambda_name'].FunctionArn" \
                     --output text)

    if [ "$lambda_arn" == "" ]; then

        # Exist if The Function is not Exist.
        err "Lambda Function With Name $lambda_name is Not Exist"
        exit 1
    
    fi

    # Function is Exist, echo This ARN 
    log "Function with Name $lambda_name is Exist ,and the ARN is $lambda_arn"
    echo "$lambda_arn"

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

add_api_lambda_integration()
{
    # $1 is the API Id ,$2 is the Lambda Name

    local api_id=$1
    local lambda_name=$2
    local lambda_arn
    local api_integration_check
    local integration_id

    lambda_arn=$(get_function_arn "$lambda_name")

    api_integration_check=$(aws apigatewayv2 get-integrations \
                            --api-id "$api_id" \
                            --query "Items[?IntegrationUri == '$lambda_arn']" \
                            --output json)

    integration_id=$(echo "$api_integration_check" | grep -oP '(?<="IntegrationId": ")[^"]*' || true)

    if [ "$integration_id" == "" ] || [ "$integration_id" == "None" ]; then

        log "The Integration is not Exist ,Creating New Integration..."

        integration_id=$(aws apigatewayv2 create-integration \
                         --api-id "$api_id" \
                         --integration-type AWS_PROXY \
                         --integration-uri "$lambda_arn" \
                         --payload-format-version "2.0" \
                         --query "IntegrationId" \
                         --output text)
        
        if [ "$integration_id" == "" ] || [ "$integration_id" == "None" ]; then

            err "Error in Creating The Integration Between API ID : $api_id and Lambda : $lambda_name"
            exit 1

        fi

        log "Integration Between API ID : $api_id and Lambda : $lambda_name Successfully Created." 
        echo "$integration_id"

    else
    
        log "Integration is Already Exist with Lmabda that has ARN : $lambda_arn"
        echo "$integration_id"
    
    fi 

}

add_api_lambada_permission_safe()
{
    # $1 is the Name of Lambda Function ,$2 Source ARN

    local lambda_name=$1
    local source_arn=$2
    # local lambda_source_arn
    local lambda_policy_result
    local perform_add_permission
    local statement_id
    local principal

    lambda_policy_result=$(aws lambda get-policy --function-name "$lambda_name" 2>/dev/null || true)

    if [ "$lambda_policy_result" == "" ] || [ "$lambda_policy_result" == "None" ] ; then

        log "There is No Permission for this Lambda, Creating New Permission...."
        perform_add_permission=true

    else
        # lambda_source_arn=$(echo "$lambda_policy_result" | jq -r '.Policy | fromjson' | grep -oP '(?<="AWS:SourceArn": ")[^"]*')

        if echo "$lambda_policy_result" | grep -Fq "$source_arn"; then

            log "Permission ALREADY exists for this API. Skipping."
            perform_add_permission=false

        else

            log "Policy exists but for a different source. Adding new permission..."
            perform_add_permission=true

        fi

    fi

    if [ "$perform_add_permission" == "true" ]; then

        statement_id="AllowApiGatewayInvoke-$(date -u +'%Y-%m-%d-%H-%M-%S')-$RANDOM"
        principal="apigateway.amazonaws.com"

        adding_permission=$(aws lambda add-permission \
                            --function-name "$lambda_name" \
                            --statement-id "$statement_id" \
                            --action lambda:InvokeFunction \
                            --principal "$principal" \
                            --source-arn "$source_arn" \
                            --query "Statement")

        if [ "$adding_permission" == "" ] || [ "$adding_permission" == "None" ]; then

            err "Error in Creating the Permission."
            exit 1 

        fi

        log "Permission Added Successfully." 

    fi
    
}


attach_route_with_lambda()
{
    # $1: API ID ,$2: Route Key (ex: "POST /solve/bfs") ,$3: Integration ID

    local api_id=$1
    local route_key=$2
    local integration_id=$3
    local route_id
    local target="integrations/$integration_id"
    local update_route_result

    # Check if Route Exists
    route_id=$(aws apigatewayv2 get-routes \
               --api-id "$api_id" \
               --query "Items[?RouteKey == '$route_key'].RouteId" \
               --output text)  

    if [ "$route_id" == "" ] || [ "$route_id" == "None" ]; then
        
        log "Route '$route_key' does not exist. Creating it..."

        # Create Route with Target directly
        route_id=$(aws apigatewayv2 create-route \
            --api-id "$api_id" \
            --route-key "$route_key" \
            --target "$target" \
            --query "RouteId" \
            --output text)

        if [ "$route_id" == "" ] || [ "$route_id" == "None" ]; then

            err "Failed to create route: $route_key"
            exit 1
        
        fi

        log "Route '$route_key' created and linked to Integration: $integration_id"

    else
        # 2. If Route Exists, Update the Target
        log "Route '$route_key' exists. Updating target..."
        
        update_route_result=$(aws apigatewayv2 update-route \
                              --api-id "$api_id" \
                              --route-id "$route_id" \
                              --target "$target" \
                              --output json | grep -oP '(?<="Target": ")[^"]*' || true)

        if [ "$update_route_result" == "" ]; then
            
            err "Error in Updating Route."
            exit 1 
        
        fi

        log "Route updated successfully with Target : $update_route_result"
    fi    

}

create_default_stage()
{
    # $1 is API ID

    local api_id=$1

    stage_check=$(aws apigatewayv2 get-stages --api-id "$api_id" \
                  --query "Items[?StageName=='\$default'].StageName" \
                  --output text)
    
    if [ "$stage_check" == "" ] || [ "$stage_check" == "None" ]; then

        log "Creating default stage with Auto-Deploy..."
        
        create_stage_result=$(aws apigatewayv2 create-stage \
                              --api-id "$api_id" \
                              --stage-name "\$default" \
                              --auto-deploy \
                              --query "StageName" \
                              --output text)
        
        if [ "$create_stage_result" == "" ] || [ "$create_stage_result" == "None" ]; then
        
            err "Error in Creating Stage."
            exit 1

        fi

        log "Stage '\$default' created successfully."

    else
        
        log "Stage '\$default' already exists."

    fi

}

configure_cors()
{
    # $1 is the API ID

    local api_id=$1
    local update_api_check
    local current_cors_config

    current_cors_config=$(aws apigatewayv2 get-api \
                          --api-id "$api_id" \
                          --query "CorsConfiguration" \
                          --output json)

    if [ "$current_cors_config" != "null" ] && echo "$current_cors_config" | grep -Fq "*" ; then
        
        log "CORS is ALREADY configured properly. Skipping Update."

    else

        cat > cors_config.json <<EOF
{
"AllowOrigins": ["*"],
"AllowHeaders": ["Content-Type", "Authorization"],
"AllowMethods": ["POST", "GET", "OPTIONS"],
"MaxAge": 300
}
EOF

        update_api_check=$(aws apigatewayv2 update-api --api-id "$api_id" \
                        --cors-configuration file://cors_config.json \
                        --query "ApiId" \
                        --output text)
        
        rm cors_config.json
        
        if [ "$update_api_check" == "" ] || [ "$update_api_check" == "None" ]; then

            err "Error in Configuring CORS."
            exit 1 

        fi

        log "Successfully Configurung CORS."

    fi
    
}


API_NAME="test-http-api"
ROUTES_KEYS=("POST /solve/bfs" "POST /solve/dfs" "POST /solve/astar")
TARGET_API_ID=$(create_api "$API_NAME")
create_default_stage "$TARGET_API_ID"
configure_cors "$TARGET_API_ID"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REGION=$(aws configure get region || echo "us-east-1")

declare -A ROUTE_MAP
ROUTE_MAP["POST /solve/bfs"]="bfs-function"
ROUTE_MAP["POST /solve/dfs"]="dfs-function"
ROUTE_MAP["POST /solve/astar"]="astar-function"

for route_key in "${ROUTES_KEYS[@]}"; do

    create_route "$TARGET_API_ID" "$route_key"

done


log "Creating Routes ,All Done !"

for route_key in "${!ROUTE_MAP[@]}"; do
    
    LAMBDA_NAME="${ROUTE_MAP[$route_key]}"
    
    log "Processing: $route_key -> Lambda: $LAMBDA_NAME"
    
    INTEGRATION_ID=$(add_api_lambda_integration "$TARGET_API_ID" "$LAMBDA_NAME")
    
    attach_route_with_lambda "$TARGET_API_ID" "$route_key" "$INTEGRATION_ID"
    
    ROUTE_PATH_ONLY="${route_key#* }"

    CURRENT_SOURCE_ARN="arn:aws:execute-api:$REGION:$ACCOUNT_ID:$TARGET_API_ID/*/*$ROUTE_PATH_ONLY" 
    
    add_api_lambada_permission_safe "$LAMBDA_NAME" "$CURRENT_SOURCE_ARN"

done

log "All Done! Your API is ready."
