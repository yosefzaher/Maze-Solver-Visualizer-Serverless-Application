#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e 

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r)
set -o pipefail

BUCKET_NAME="maze-solver-s3-bucket"
REGION="us-east-1"
PUBLIC_DOMAIN_NAME="zaher.online"
SUB_DOMAIN="www"


log()
{
   # $1 is The Log or Info Statement
    echo "[INFO] $1" >&2
}

err()
{
    # $1 is The Log or Info Statement
    echo "[Error] $1" >&2
}

get_cloud_front_domain_name()
{
    # $1 is the Bucket Name that Cloud Front Point to ,$2 is the Region of Bucket

    local bucket_name=$1
    local region=$2
    local origin_domain
    local cloud_front_domain_name

    origin_domain="${bucket_name}.s3.${region}.amazonaws.com"

    cloud_front_domain_name=$(aws cloudfront list-distributions \
                                  --query "DistributionList.Items[?Origins.Items[0].DomainName=='$origin_domain'].DomainName | [0]" \
                                  --output text)

    if [ "$cloud_front_domain_name" == "" ] || [ "$cloud_front_domain_name" == "None" ]; then

        err "Erron in Finding the CloudFront Domain Name."
        exit 1

    fi

    log "Finding the CloudFront Domain Name : $cloud_front_domain_name"
    echo "$cloud_front_domain_name"

}

create_hosted_zone()
{
    # $1 is the Public Domain Name

    local public_domain_name=$1
    local time
    local hosted_zone_check
    local hosted_zone_id

    time=$(date -u +"%Y-%m-%d-%H-%M-%S")

    hosted_zone_check=$(aws route53 list-hosted-zones --query "HostedZones[?Name == '$public_domain_name.']" | grep -oP '(?<="Id": ")[^"]*' || true)

    if [ "$hosted_zone_check" == "" ] || [ "$hosted_zone_check" == "None" ]; then

        hosted_zone_id=$(aws route53 create-hosted-zone --name "$public_domain_name" \
                             --caller-reference "$time" \
                             --query HostedZone | grep -oP '(?<="Id": ")[^"]*'  || true)

        if [ "$hosted_zone_id" == "" ] || [ "$hosted_zone_id" == "None" ]; then
        
            err "Error in Creating Public Hosted Zone."
            exit 1
        
        fi

        log "Public Hosted Zone Created Successfully with id : $hosted_zone_id"

    else 

        hosted_zone_id=$hosted_zone_check
        log "Public Hosted Zone is Already Exist With id : $hosted_zone_id" 
    
    fi

    echo "$hosted_zone_id"
        
}


create_cloudfront_alias_record()
{
    # $1: SubDomain (e.g., 'www' or 'app')
    # $2: CloudFront Domain (e.g., d123.cloudfront.net)
    # $3: Public Hosted Zone Domain (e.g., example.com)
    # $4: Hosted Zone ID (Optional if you want to pass it directly for speed)

    local sub_domain=$1
    local cf_domain=$2
    local public_domain_name=$3
    local hosted_zone_id=$4
    local full_sub_domain="$sub_domain.$public_domain_name"
    local change_batch_json
    local CLOUDFRONT_HOSTED_ZONE_ID
    local check_record
    
    # CloudFront Magic Hosted Zone ID
    CLOUDFRONT_HOSTED_ZONE_ID="Z2FDTNDATAQYW2"

    log "Preparing to create Alias Record for $full_sub_domain pointing to $cf_domain..."

    # Get Hosted Zone ID if not provided
    if [ -z "$hosted_zone_id" ]; then
       
        hosted_zone_id=$(aws route53 list-hosted-zones \
            --query "HostedZones[?Name == '${public_domain_name}.'].Id" \
            --output text)
    
    fi

    if [ -z "$hosted_zone_id" ] || [ "$hosted_zone_id" == "None" ]; then
    
        err "Hosted Zone not found for $public_domain_name"
        exit 1
    
    fi

    # Check if Record Exists
    check_record=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --query "ResourceRecordSets[?Name == '${full_sub_domain}.']" \
        --output text)

    if [ "$check_record" != "" ] && [ "$check_record" != "None" ]; then
        
        log "DNS Record for $full_sub_domain already exists. Skipping."
    
    else

        # Create the Change Batch JSON (The Alias Structure)
        change_batch_json=$(cat << EOF
{
"Comment": "Creating Alias record for CloudFront",
"Changes": [
    {
    "Action": "CREATE",
    "ResourceRecordSet": {
        "Name": "$full_sub_domain",
        "Type": "A",
        "AliasTarget": {
        "HostedZoneId": "$CLOUDFRONT_HOSTED_ZONE_ID",
        "DNSName": "$cf_domain",
        "EvaluateTargetHealth": false
        }
    }
    }
]
}
EOF
)

        # Execute Change
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$hosted_zone_id" \
            --change-batch "$change_batch_json" > /dev/null

        execute_check="$?"    

        if [ $execute_check -eq 0 ]; then
            
            log "DNS Alias Record Created Successfully: $full_sub_domain -> $cf_domain"
        
        else
        
            err "Failed to create DNS Record."
            exit 1
        
        fi

    
    fi

}

HOSTED_ZONE_ID=$(create_hosted_zone "$PUBLIC_DOMAIN_NAME")
CLOUD_FRONT_DOMAIN=$(get_cloud_front_domain_name "$BUCKET_NAME" "$REGION")
create_cloudfront_alias_record "$SUB_DOMAIN" "$CLOUD_FRONT_DOMAIN" "$PUBLIC_DOMAIN_NAME" "$HOSTED_ZONE_ID"


