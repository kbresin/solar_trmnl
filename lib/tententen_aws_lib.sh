#!/bin/bash

: "${ALERT_PROFILE:=sns_alert}"
ALERT_SNS=arn:aws:sns:us-west-2:933687197333:tententen-sysalerts
WARN_SNS=arn:aws:sns:us-west-2:933687197333:tententen-syswarnings
PRIMARY_REGION=us-west-2

function sns_warn() {
	aws sns publish --profile "$ALERT_PROFILE" --region "$PRIMARY_REGION" --topic-arn "$WARN_SNS" --message "$1" >/dev/null
}

function sns_alert() {
	aws sns publish --profile "$ALERT_PROFILE" --region "$PRIMARY_REGION" --topic-arn "$ALERT_SNS" --message "$1" >/dev/null
}
