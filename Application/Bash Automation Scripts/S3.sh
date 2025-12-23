#!/bin/bash

aws s3api create-bucket --bucket test-zaher-s3-bucket --region us-east-1

aws s3 ls

aws s3api put-object --bucket test-zaher-s3-bucket --key images/zaher.jpg --body "/mnt/c/Users/Dell/OneDrive/Desktop/zaher.jpg"

aws s3api delete-public-access-block --bucket test-zaher-s3-bucket

aws s3api put-bucket-policy --bucket test-zaher-s3-bucket --policy file://Allow_Specific_Domain_policy.json
