#!/bin/bash

# Exit Immediately if Any Command Exists With Non-Zero Status
set -e 

# Exit if Any Command in a Pipes Fail (Important for aws ... | jq -r)
set -o pipefail

DOMAIN_NAME="zaher.online"
IDEMPOTENCY_TOKEN="yosefzaher2004csed"

CNAME_RECORD=()

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

request_ssl_certificate()
{
    # $1 is the Domain Name ,$2 is the Idempotency Token

    local domain_name=$1
    local idempotency_token=$2
    local ssl_certificate_check
    local ssl_certificate_arn

    ssl_certificate_check=$(aws acm list-certificates \
                              --query "CertificateSummaryList[?DomainName == '$domain_name'].CertificateArn" \
                              --output text)

    if [ "$ssl_certificate_check" == "" ] || [ "$ssl_certificate_check" == "None" ]; then
    
        log "Requesting New SSL Certificate for Domain Name $domain_name...."

        ssl_certificate_arn=$(aws acm request-certificate \
                                  --domain-name "$domain_name" \
                                  --validation-method DNS \
                                  --idempotency-token "$idempotency_token" \
                                  --query "CertificateArn" \
                                  --output text)  

        if [ "$ssl_certificate_arn" == "" ] || [ "$ssl_certificate_arn" == "None" ]; then
        
            err "Error in Requesting SSL Certificate."
            exit 1

        fi 

        log "SSL Certificate Requesting Successfully."
        log "SSL Certificate ARN : $ssl_certificate_arn"
        echo "$ssl_certificate_arn"

    else

        ssl_certificate_arn=$ssl_certificate_check
        log "SSL Certificate for Domain Name $domain_name Already Exists."
        log "SSL Certificate ARN : $ssl_certificate_arn"
        echo "$ssl_certificate_arn"
        
    fi

}

get_cname_dns()
{
    # $1 SSL Certificate ARN

    local ssl_certificate_arn=$1
    local cname_record_name
    local cname_record_value
    local retries=0

    while [ $retries -lt 10 ]; do

        cname_record_data=$(aws acm describe-certificate \
            --certificate-arn "$ssl_certificate_arn" \
            --query "Certificate.DomainValidationOptions[0].ResourceRecord" \
            --output json)

        if [ "$cname_record_data" != "null" ] && [ "$cname_record_data" != "" ]; then
    
            break
    
        fi

        log "Waiting for AWS to generate DNS records... (Attempt $((retries+1))/10)"
        sleep 3
        retries=$((retries+1))
    
    done

    if [ "$cname_record_data" != "" ] && [ "$cname_record_data" != "null" ]; then

        cname_record_name=$(echo "$cname_record_data" | grep -oP '(?<="Name": ")[^"]*' || true)
        cname_record_value=$(echo "$cname_record_data" | grep -oP '(?<="Value": ")[^"]*' || true)

        CNAME_RECORD[0]=$cname_record_name
        CNAME_RECORD[1]=$cname_record_value

        log "Successully Extracting CNAME Data: ${CNAME_RECORD[0]} -> ${CNAME_RECORD[1]}"

    else

        err "Error in Extracting CNAME Data."
        exit 1
    
    fi

}

certificate_validation_wait()
{
    # $1 SSL Certificate ARN

    local ssl_certificate_arn=$1

    log "Waiting for Certificate to be ISSUED....."
    aws acm wait certificate-validated --certificate-arn "$ssl_certificate_arn"
    log "Certificate ISSUED Successully."

}


SSL_CERTIFICATE_ARN=$(request_ssl_certificate "$DOMAIN_NAME" "$IDEMPOTENCY_TOKEN")

get_cname_dns "$SSL_CERTIFICATE_ARN"

certificate_validation_wait "$SSL_CERTIFICATE_ARN"