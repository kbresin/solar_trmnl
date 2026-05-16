#!/bin/bash
source ~/.secrets/se.sh

if [[ -z "$S3_PROFILE" ]]; then
  echo "Error: S3_PROFILE is not set in ~/.secrets/se.sh" >&2
  exit 1
fi
if [[ -z "$S3_BUCKET" ]]; then
  echo "Error: S3_BUCKET is not set in ~/.secrets/se.sh" >&2
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: upload.sh <local-bmp-path> <s3-destination-filename>" >&2
  echo "  e.g. upload.sh /tmp/out.bmp output.bmp" >&2
  exit 1
fi

PATH=$PATH:/usr/local/bin
aws s3 cp --profile "${S3_PROFILE}" "$1" "s3://${S3_BUCKET}/public/CE243659F38BF956/$2"
