#!/usr/bin/env bash
set -e
source `dirname "$0"`/rc_functions.sh

# Define help function
function help () {
    echo "provision.sh - Create ECS service and related resources in AWS."
    echo "Usage:"
    echo "ecs-deployer/bin/provision.sh [-h] -e env-name"
    echo "Options:"
    echo "-h: Displays this information."
    echo "-e: Target environment. Required."
    rc_help
    exit 1;
}

# Parse arguments into variables.
while getopts ":he:" opt; do
  case $opt in
    h)
      help
      ;;
    e)
      environment=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2 && help
      ;;
  esac
done
[ -z "$environment" ] && echo "environment is a required argument" && help

load_rc

echo "Creating target group..."
aws elbv2 create-target-group \
--name ${name} \
--protocol http \
--port ${port} \
--vpc-id ${vpc_id} \
--health-check-path ${lb_health_path} \
--target-type "ip" > target-group.json

target_group_arn=`grep TargetGroupArn target-group.json | cut -d "\"" -f 4 | sed -e 's/"//g' | sed -e 's/,//g' | xargs`
echo "Created target group: $target_group_arn"

aws elbv2 modify-target-group-attributes \
--target-group-arn ${target_group_arn} \
--attributes Key=deregistration_delay.timeout_seconds,Value=30

echo "Creating listener rule..."
aws elbv2 create-rule \
--listener-arn ${listener_arn} \
--conditions ${listener_rule} \
--priority ${listener_rule_priority} \
--actions Type=forward,TargetGroupArn=${target_group_arn}

echo "Creating log group..."
aws logs create-log-group --log-group-name /ecs/${name}

echo "Creating ECS service..."
aws ecs create-service \
--cluster ${cluster} \
--service-name ${name} \
--task-definition ${name} \
--load-balancers targetGroupArn=${target_group_arn},containerName=${name},containerPort=${port} \
--desired-count ${task_count} \
--launch-type EC2 \
--network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$security_groups],assignPublicIp=DISABLED}" \
--scheduling-strategy REPLICA
