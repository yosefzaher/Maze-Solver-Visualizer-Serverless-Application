#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r)
set -o pipefail

ROLE_NAME="lambda-maze-role"
LAMBDA_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
TRUST_POLICY_PATH="file://trust_policy.json"

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

create_role()
{
    # $1 is the IAM Role Name ,$2 is the Trust Policy JSON File Abslute Path  

    local iam_role_name=$1
    local trust_policy_path=$2
    local iam_role_arn
    local lambda_iam_role_result
    local lambda_role_arn

    # Check if the Role Exist or Not
    iam_role_arn=$(aws iam list-roles --output json \
                --query "Roles[?RoleName == '$iam_role_name'].Arn" \
                --output text)

    if [ "$iam_role_arn" == "" ]; then
        
        # Create a New Role if it is not Exist
        log "Creating New IAM Role."

        cat > trust_policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

        lambda_iam_role_result=$(aws iam create-role --role-name "$iam_role_name" \
                                --assume-role-policy-document "$trust_policy_path" \
                                --output json)

        lambda_role_arn=$(echo "$lambda_iam_role_result" | grep -oP '(?<="Arn": ")[^"]*' || true)

        if [ "$lambda_role_arn" == "" ]; then

            # Error in Creating New Role
            err "Error in Creating IAM Role."
            exit 1

        fi

        # Role Successfully Created
        log "IAM Role Successfully Created."
        echo "$lambda_role_arn"
        
        # Cleanup Files
        rm trust_policy.json
        
        # Wait for IAM to Propagate the Role
        sleep 10

    else

        # Role is Already Exit
        log "IAM Role Already Exist."
        lambda_role_arn=$iam_role_arn
        echo "$lambda_role_arn"

    fi

}

attach_policy()
{
    # $1 is the Policy ARN ,$2 is the Role Name

    local policy_arn=$1
    local role_name=$2
    local policy_check 

    # Check if Policy is Attached or Not
    policy_check=$(aws iam list-attached-role-policies \
                   --role-name "$role_name" \
                   --output json \
                   --query "AttachedPolicies[?PolicyArn == '$policy_arn'].PolicyArn" \
                   --output text) 
    
    if [ "$policy_check" == "" ]; then
        
        # Attach Policy if it is Not Attached 
        log "Attaching The Policy..."
        aws iam attach-role-policy \
        --policy-arn "$policy_arn" \
        --role-name "$role_name" 
        log "Policy with ARN : $policy_arn is Attached Successfully."

    else

        # Policy is Already Attached 
        log "Policy with ARN : $policy_arn is Already Attached."

    fi   

}


create_role "$ROLE_NAME" "$TRUST_POLICY_PATH"

attach_policy "$LAMBDA_POLICY_ARN" "$ROLE_NAME"

log "All Done !"


