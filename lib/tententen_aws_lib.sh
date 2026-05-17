#!/bin/bash

ALERT_PROFILE="sns_alert"
ALERT_SNS=arn:aws:sns:us-west-2:933687197333:tententen-sysalerts
WARN_SNS=arn:aws:sns:us-west-2:933687197333:tententen-syswarnings
PRIMARY_REGION=us-west-2

AWSBIN=/usr/local/bin/aws

function sns_warn() {
        "$AWSBIN" sns publish --profile "$ALERT_PROFILE" --region "$PRIMARY_REGION" --topic-arn "$WARN_SNS" --message "$1" >/dev/null
}

function sns_alert() {
        "$AWSBIN" sns publish --profile "$ALERT_PROFILE" --region "$PRIMARY_REGION" --topic-arn "$ALERT_SNS" --message "$1" >/dev/null
}
