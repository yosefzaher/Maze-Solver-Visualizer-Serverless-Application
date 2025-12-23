#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e 

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r)
set -o pipefail

ROLE_NAME="lambda-maze-role"

LAMBDA_NAMES=("bfs-function" "dfs-function" "astar-function")
LAMBDA_ZIP_PATHS=("fileb://../Lambda Functions/zip_files/bfs_function.zip" \
                  "fileb://../Lambda Functions/zip_files/dfs_function.zip" \
                  "fileb://../Lambda Functions/zip_files/astar_function.zip")
LAMBDA_FILE_NAMES=("bfs_lambda" "dfs_lambda" "astar_lambda")

LAMBDA_FUNCTION_NAME="lambda_handler"
LAMBDA_RUNTIME="python3.14"

LAMBDA_LAYER_ZIP_PATH="fileb://../AWS Lambda Layer/python.zip"
LAMBDA_LAYER_NAME="maze-helper-functions-layer"
LAMBDA_LAYER_DESCRIPTION="A Layer with the Helper Shared Library for Lambda Functions"
LAMBDA_LAYER_ARCHITECTURE="x86_64"


err()
{
    # $1 is the Error Message
    echo "[ERROR] $1" >&2
}

log()
{
    # $1 is the Log Message
    echo "[INFO] $1" >&2
}

get_role_arn()
{
    # $1 is the Role Name

    local role_name=$1

    iam_role_arn=$(aws iam list-roles \
                       --query "Roles[?RoleName == '$role_name'].Arn" \
                       --output text)

    if [ "$iam_role_arn" == "" ] || [ "$iam_role_arn" == "None" ]; then
    
        err "Error in Getting The Lambda Role ARN."
        exit 1
    
    fi

    log "Lambda Role ARN is : $iam_role_arn"

    echo "$iam_role_arn"

}

create_lambda_function()
{
    # $1 is Lambda Function Name ,$2 IAM Role ARN ,$3 File Name of Lambda Function 
    # $4 Lambda Handler Name ,$5 Lambda Function RunTime ,$6 Path of ZIP File of the Function  

    local lambda_name=$1
    local role_arn=$2
    local lambda_file_name=$3
    local lambda_function_name=$4
    local lambda_runtime=$5
    local lambda_zip_path=$6
    local lambda_function_check
    local creating_function_result
    local lambda_function_arn
   
    lambda_function_check=$(aws lambda list-functions \
                            --output json \
                            --query "Functions[?FunctionName == '$lambda_name'].FunctionArn" \
                            --output text)

    if [ "$lambda_function_check" == "" ] || [ "$lambda_function_check" == "None" ]; then

        log "Creating the Lambda Function with Name : $lambda_name...."
        

        creating_function_result=$(aws lambda create-function --function-name "$lambda_name" \
                                --runtime "$lambda_runtime" \
                                --role "$role_arn" \
                                --handler "$lambda_file_name"."$lambda_function_name" \
                                --zip-file "$lambda_zip_path")
        
        lambda_function_arn=$(echo "$creating_function_result" | grep -oP '(?<="FunctionArn": ")[^"]*' || true)
        
        if [ "$lambda_function_arn" == "" ]; then
        
            err "Error in Creating Lambda Function"
            exit 1
        
        fi

        log "Lambda Function Successfully Created with ARN : $lambda_function_arn"
        echo "$lambda_function_arn"

    else

        lambda_function_arn=$lambda_function_check
        log "Lambda Function Already Exist with ARN : $lambda_function_arn"
        echo "$lambda_function_arn"

    fi

}

create_lambda_layer()
{
    # $1 is the Name of Lambda Layer ,$2 is Description fro Lambda Layer ,$3 is Path for Lambda Layer ZIP File
    # $4 Lambda Layer RunTime ,$5 is Lambda Layer Architecture (ARM ,X86_68 ,etc...)

    local lambda_layer_name=$1
    local lambda_layer_description=$2
    local lambda_layer_zip_path=$3
    local lambda_runtime=$4
    local lambda_layer_architecture=$5
    local lambda_layer_check
    local lambda_layer_creation_result
    local lambda_layer_arn

    lambda_layer_check=$(aws lambda list-layers \
                         --output json \
                         --query "Layers[?LayerName == '$lambda_layer_name'].LayerArn" \
                         --output text)                   

    if [ "$lambda_layer_check" == "" ] || [ "$lambda_layer_check" == "None" ]; then
        
        log "Creating Lambda Layer..."
        
        lambda_layer_creation_result=$(aws lambda publish-layer-version --layer-name "$lambda_layer_name" \
                                           --description "$lambda_layer_description" \
                                           --zip-file "$lambda_layer_zip_path" \
                                           --compatible-runtimes "$lambda_runtime" \
                                           --compatible-architectures "$lambda_layer_architecture")

        lambda_layer_arn=$(echo "$lambda_layer_creation_result" | grep -oP '(?<="LayerArn": ")[^"]*' || true) 

        if [ "$lambda_layer_arn" == "" ]; then
            
            err "Error in Creating Lambda Layer"
            exit 1
        
        fi

        log "Lambda Layer with ARN : $lambda_layer_arn Created Successfully"
        echo "$lambda_layer_arn" 

    else
        
        lambda_layer_arn=$lambda_layer_check
        log "Lambda Layer with ARN : $lambda_layer_arn Already Exist"
        echo "$lambda_layer_arn"

    fi

}

get_latest_layer_version() 
{
    # $1 is Lambda Function Layer Name

    local layer_name=$1
    
    aws lambda list-layer-versions --layer-name "$layer_name" \
        --query "LayerVersions[0].LayerVersionArn" \
        --output text
}

add_layer_to_function()
{
    local lambda_name=$1
    local lambda_layer_arn=$2
    local lambda_function_status
    local lambda_function_layer_check

    lambda_function_status=$(aws lambda get-function-configuration \
                             --function-name "$lambda_name" \
                             --output json)
    
    lambda_function_lastupdate_status=$(echo "$lambda_function_status" | grep -oP '(?<="LastUpdateStatus": ")[^"]*' || true)

    if [ "$lambda_function_lastupdate_status" == "InProgress" ]; then

        log "Waits for the function's LastUpdateStatus to be Successful (e.g., after updating function code)"
        aws lambda wait function-updated --function-name "$lambda_name"
    
    fi

    lambda_function_layer_check=$(aws lambda get-function-configuration \
                                  --function-name "$lambda_name" \
                                  --query "Layers[?Arn == '$lambda_layer_arn'].Arn" \
                                  --output text)
    
    if [ "$lambda_function_layer_check" == "None" ] || [ "$lambda_function_layer_check" == "" ]; then

        log "Attaching layer to $lambda_name..."

        layer_attachment_check=$(aws lambda update-function-configuration --function-name "$lambda_name" \
                                 --layers "$lambda_layer_arn" \
                                 --query "Layers[?Arn == '$lambda_layer_arn'].Arn" \
                                 --output text) 
        
        if [ "$layer_attachment_check" == "" ] || [ "$layer_attachment_check" == "None" ]; then
            
            err "Error in Layer Attachment."
            exit 1
        
        fi

        log "Layer Attached Successfully."

    else 
        
        log "Layer is ALREADY attached to the function. Skipping update."

    fi

}

create_lambda_layer "$LAMBDA_LAYER_NAME" "$LAMBDA_LAYER_DESCRIPTION" "$LAMBDA_LAYER_ZIP_PATH" \
                    "$LAMBDA_RUNTIME" "$LAMBDA_LAYER_ARCHITECTURE"

LAMBDA_LAYER_ARN=$(get_latest_layer_version "$LAMBDA_LAYER_NAME")

ROLE_ARN=$(get_role_arn "$ROLE_NAME")

for i in "${!LAMBDA_NAMES[@]}"; do
    
    create_lambda_function "${LAMBDA_NAMES[$i]}" "$ROLE_ARN" "${LAMBDA_FILE_NAMES[$i]}" "$LAMBDA_FUNCTION_NAME" \
                        "$LAMBDA_RUNTIME" "${LAMBDA_ZIP_PATHS[$i]}"

    add_layer_to_function "${LAMBDA_NAMES[$i]}" "$LAMBDA_LAYER_ARN"

done

