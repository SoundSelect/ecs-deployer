#!/usr/bin/env bash
set -e

if [ $# -ne 7 ]; then
    echo "Create a service for a given environment."
    echo
    echo "Usage: create-service.sh <service name> <cluster name> <vpc id> <env name> <listener ARN> <dns host> <routing priority>"
    exit 1
fi

export NAME=$1
export CLUSTER_NAME=$2
export VPC=$3
export DEPLOYMENT_ENV=$4
export LISTENER_ARN=$5
export DNS=$6
export PRI=$7


echo "Creating target group..."
aws elbv2 create-target-group \
--name ${NAME} \
--protocol ${PROTO} \
--port ${PORT} \
--vpc-id ${VPC} \
--health-check-path ${LB_HEALTH_PATH} \
--target-type "ip" > target-group.json

ARN=`grep TargetGroupArn target-group.json | cut -d "\"" -f 4 | sed -e 's/"//g' | sed -e 's/,//g' | xargs`
echo "Created target group: $ARN"

aws elbv2 modify-target-group-attributes \
--target-group-arn ${ARN} \
--attributes Key=deregistration_delay.timeout_seconds,Value=30

echo "Creating listener rule..."
aws elbv2 create-rule \
--listener-arn ${LISTENER_ARN} \
--conditions Field=host-header,Values=${DNS} \
--priority ${PRI} \
--actions Type=forward,TargetGroupArn=${ARN}

echo "Creating log group..."
aws logs create-log-group --log-group-name /ecs/${NAME}

echo "Creating ECS service..."
aws ecs create-service \
--cluster ${CLUSTER} \
--service-name ${NAME} \
--task-definition ${NAME} \
--load-balancers targetGroupArn=${ARN},containerName=${NAME},containerPort=${PORT} \
--desired-count ${TASK_COUNT} \
--launch-type EC2 \
--network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
--scheduling-strategy REPLICA
