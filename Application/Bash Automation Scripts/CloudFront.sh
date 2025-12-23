#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e 

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r)
set -o pipefail

BUCKET_NAME="maze-solver-s3-bucket"
REGION="us-east-1"
DEFAULT_ROOT_OBJECT="index.html"

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

update_s3_policy_for_oac() 
{
    # $1 is the Bucket Name ,$2 is the Cloud Distribution ARN

    local bucket_name=$1
    local distribution_arn=$2
    
    log "Updating S3 Bucket Policy to allow CloudFront OAC..."

    cat > oac_policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${bucket_name}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "$distribution_arn"
                }
            }
        }
    ]
}
EOF

    aws s3api put-bucket-policy --bucket "$bucket_name" --policy file://oac_policy.json
    rm oac_policy.json
    log "S3 Policy Updated Secured via OAC."
}

create_oac() 
{
    local oac_name
    local oac_id

    log "Creating Origin Access Control (OAC)..."
    
    oac_name="maze-solver-oac-$(date +%s)"

    oac_id=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config Name="$oac_name",Description="OAC for Maze Solver",SigningProtocol="sigv4",SigningBehavior="always",OriginAccessControlOriginType="s3" \
        --query "OriginAccessControl.Id" \
        --output text)

    echo "$oac_id"
}

create_cloudfront_dist_S3()
{
    # $1: Bucket Name ,$2: Region ,$3: Default Root Object

    local bucket_name=$1
    local region=$2
    local default_root_object=$3
    
    local origin_domain="${bucket_name}.s3.${region}.amazonaws.com"
    
    local cloud_front_domain_name
    local existing_dist_check
    local distribution_id
    local distribution_domain
    local dist_config_json
    local oac_id
    local dist_result
    local distribution_arn

    oac_id=$(create_oac)
    log "Using OAC ID: $oac_id"

    log "Checking for existing distribution with Origin: $origin_domain"

    existing_dist_check=$(aws cloudfront list-distributions \
                          --query "DistributionList.Items[?Origins.Items[0].DomainName=='$origin_domain'].{Id:Id, DomainName:DomainName} | [0]" \
                          --output json)

    if [ "$existing_dist_check" != "null" ] && [ "$existing_dist_check" != "" ]; then
    
        distribution_id=$(echo "$existing_dist_check" | grep -oP '(?<="Id": ")[^"]*' || true)
        distribution_domain=$(echo "$existing_dist_check" | grep -oP '(?<="DomainName": ")[^"]*' || true)

        log "Distribution ALREADY Exists with ID: $distribution_id | Domain: $distribution_domain"

    else

        log "Creating New CloudFront Distribution..."
        dist_config_json=$(cat <<EOF
{
    "CallerReference": "$(date +%s)",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-REST-Origin",
                "DomainName": "$origin_domain",
                "OriginAccessControlId": "$oac_id",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "DefaultRootObject": "$default_root_object",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-REST-Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": { "Forward": "none" },
            "Headers": { "Quantity": 0 }
        },
        "MinTTL": 0
    },
    "CacheBehaviors": { "Quantity": 0 },
    "Enabled": true,
    "Comment": "Distribution with OAC"
}
EOF
)
        dist_result=$(aws cloudfront create-distribution \
                                  --distribution-config "$dist_config_json" \
                                  --query "Distribution.{DomainName:DomainName, Id:Id, ARN:ARN}" \
                                  --output json) 

        if [ "$dist_result" == "" ] || [ "$dist_result" == "null" ]; then
        
            err "Error in Creating Cloud Front Distribution"
            exit 1
        
        fi

        cloud_front_domain_name=$(echo "$dist_result" | grep -oP '(?<="DomainName": ")[^"]*')
        distribution_id=$(echo "$dist_result" | grep -oP '(?<="Id": ")[^"]*')
        distribution_arn=$(echo "$dist_result" | grep -oP '(?<="ARN": ")[^"]*')        

        log "CloudFront Distribution Successfully Created with Domain Name: $cloud_front_domain_name"

        update_s3_policy_for_oac "$bucket_name" "$distribution_arn"

    fi
}


create_cloudfront_dist_S3 "$BUCKET_NAME" "$REGION" "$DEFAULT_ROOT_OBJECT"

