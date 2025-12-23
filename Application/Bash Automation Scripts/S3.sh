#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e 


# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r)
set -o pipefail

BUCKET_NAME="maze-solver-s3-bucket"
REGION="us-east-1"
INDEX_DOCUMENT="index.html"

declare -A OBJECTS_MAP
OBJECTS_MAP["index.html"]="/mnt/d/Cloud Architectures Design/Serveless Project/Application/index.html"
OBJECTS_MAP["script.js"]="/mnt/d/Cloud Architectures Design/Serveless Project/Application/script.js"


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


### Write A Function To Create Bucket
create_bucket()
{
    # $1 is the Name of the Bucket ,$2 is The Region 

    local bucket_name=$1
    local region=$2
    local create_bucket_check
    local create_bucket_result

    create_bucket_check=$(aws s3api list-buckets \
    --query "Buckets[?Name == '$bucket_name'].Name" \
    --output text)

    if [ "$create_bucket_check" == "" ] || [ "$create_bucket_check" == "None" ]; then

        log "Creating New S3 Bucket with Name $bucket_name....."
        
        create_bucket_result=$(aws s3api create-bucket \
                                   --bucket "$bucket_name" \
                                   --region "$region" \
                                   --query "Location" \
                                   --output text)

        if [ "$create_bucket_result" == "" ] || [ "$create_bucket_result" == "None" ]; then

            err "Error in Creating S3 Bucket with Name : $bucket_name"
            exit 1

        fi

        log "S3 Bucket with Name : $bucket_name is Successfully Created."
    
    else

        log "S3 Bucket with Name $bucket_name is Already Exist."

    fi

}


### Write A Function To Upload Objects in A Bucket
upload_object_S3()
{
    # $1 is the Name of the Bucket ,$2 is the Key of the Object ,$3 is the Path of the Object in LocalPC

    local bucket_name=$1
    local object_key=$2
    local object_path=$3
    local put_object_result
    local content_type

    if [[ "$object_path" == *.html ]]; then

        content_type="text/html"
    
    elif [[ "$object_path" == *.css ]]; then
    
        content_type="text/css"
    
    elif [[ "$object_path" == *.js ]]; then
    
        content_type="application/javascript"
    
    elif [[ "$object_path" == *.json ]]; then
    
        content_type="application/json"
    
    elif [[ "$object_path" == *.png ]]; then
    
        content_type="image/png"
    
    else

        content_type="application/octet-stream"    
    
    fi

    log "Uploading/Updating Object $object_key to $bucket_name..."

    aws s3api put-object --bucket "$bucket_name" \
        --key "$object_key" \
        --body "$object_path" \
        --content-type "$content_type" \
        --output json > /dev/null

    put_object_result="$?"    

    if [ $put_object_result -eq 0 ]; then
    
        log "Object $object_key Successfully Uploaded."
    
    else
    
        err "Error in Uploading Object $object_key"
        exit 1
    
    fi

}

### Write A Function That Enable Static Web Hosting in A Specific Bucket 
enable_static_web_hosting()
{
    # $1 is the Bucket Name, $2 Index Document
    local bucket_name=$1
    local index_document=$2
    local region
    local policy_status
    local web_check
    local delete_public_access_check

    log "Configuring Static Website for Bucket: $bucket_name"

    # 1. Disable All Public Access (Block Public Access)
    aws s3api delete-public-access-block --bucket "$bucket_name" > /dev/null 2>&1
    
    delete_public_access_check="$?"

    if [ $delete_public_access_check -eq 0 ]; then
        log "Public Access Block removed successfully."
    else
        err "Error in Deleting Public Access Block."
        exit 1
    fi

    # 2. Attach Bucket Policy (Public Read)
    cat > policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${bucket_name}/*"
        }
    ]
}
EOF

    aws s3api put-bucket-policy --bucket "$bucket_name" --policy file://policy.json > /dev/null 2>&1
    
    policy_status="$?"
    rm policy.json

    if [ $policy_status -eq 0 ]; then
        log "Bucket Policy attached successfully (Public Read)."
    else
        err "Error in attaching Bucket Policy."
        exit 1
    fi

    # 3. Configure Static Website Hosting using s3api (الأهم)
    cat > website.json <<EOF
{
    "IndexDocument": {
        "Suffix": "$index_document"
    },
    "ErrorDocument": {
        "Key": "error.html"
    }
}
EOF

    aws s3api put-bucket-website \
        --bucket "$bucket_name" \
        --website-configuration file://website.json > /dev/null 2>&1

    web_check="$?"
    rm website.json

    if [ $web_check -eq 0 ]; then
        log "Successfully Enabled S3 Static Website Hosting for $bucket_name"
        
        # 4. Configure CORS 
        cat > cors.json <<EOF
{
    "CORSRules": [
        {
            "AllowedOrigins": ["*"],
            "AllowedMethods": ["GET"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF
        
        aws s3api put-bucket-cors --bucket "$bucket_name" --cors-configuration file://cors.json > /dev/null 2>&1
        rm cors.json
        
        # 5. Get region
        region=$(aws configure get region 2>/dev/null || echo "$REGION")
        
        # 6. Show website URL - There are two possible formats
        log "Your Website URL: http://${bucket_name}.s3-website-${region}.amazonaws.com"
        log "Alternative URL: https://${bucket_name}.s3.amazonaws.com/${index_document}"
        
    else
        err "Error in Enabling S3 Static Website Hosting."
        exit 1
    fi
}

create_bucket "$BUCKET_NAME" "$REGION"

for object_key in "${!OBJECTS_MAP[@]}" ;do

    OBJECT_PATH="${OBJECTS_MAP[$object_key]}"
    upload_object_S3 "$BUCKET_NAME" "$object_key" "$OBJECT_PATH"

done

log "All Objects Successfully Uploaded"

enable_static_web_hosting "$BUCKET_NAME" "$INDEX_DOCUMENT"
