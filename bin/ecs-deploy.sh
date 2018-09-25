#!/usr/bin/env bash
set -e

rc_help() {
    echo $1
    echo
    echo "This script requires a .deployrc configuration file. This file should be placed in the directory which the script is run. This is typically the root of your project beside your .travis.yml or Jenkinsfile."
    echo "You may also specify environment-specific parameters in their own .deployrc.env_name files.  For example you can create a .deployrc.prod and its values will override the main one when deploying to a environment named prod."
    echo
    echo "The following parameters must be contained either in the .deployrc file or the environment-specific rc file:"
    echo
    echo "NAME=my-service"
    echo "REGION=us-west-2"
    echo "CLUSTER=arn:aws:ecs:us-west-2:123456789012:cluster/my-cluster"
    echo "REPO=123456789012.dkr.ecr.us-west-2.amazonaws.com/my-service"
    echo "SUBNETS=subnet-4cfd6c2a,subnet-53a6101b"
    echo "SECURITY_GROUPS=sg-6ba62416"
    echo "IAM_ROLE=arn:aws:iam::123456789012:role/ecsTaskExecutionRole"
    echo
    echo "The following parameters are optional and will default to these values:"
    echo
    echo "CPU=1024"
    echo "MEMORY=2048"
    echo "PORT=8080"
    echo "LB_HEALTH_START_PERIOD=120"
    echo "LB_HEALTH_PATH=/"
    echo "CONTAINER_HEALTH_COMMAND=\"true\""
    echo "CONTAINER_HEALTH_INTERVAL=10"
    echo "CONTAINER_HEALTH_TIMEOUT=5"
    echo "CONTAINER_HEALTH_RETRIES=5"
    echo "CONTAINER_HEALTH_START_PERIOD=90"
    echo
    echo "You may also set env vars by prefixing the var name with ENV_"
    echo "ENV_ENVIRONMENT=production"
    echo "ENV_DEPLOY_TIME=\`date\`"
}

# Display usage message if wrong arguments or first argument is "help"
if [ $# -gt 2 ] || [ $# -eq 0 ]  || [ $1 == "help" ]; then
    echo "Deploy updated service in ECS.  An argument for the environment is optional. If there is no environment supplied, the script will assign one based on the branch."
    echo
    echo "Usage: ecs-deploy.sh <version> [environment]"
    rc_help
    exit 1
fi

# Exit if this was triggered by a pull request.
if [ "$TRAVIS_PULL_REQUEST" == "true" ] || [ -z "CHANGE_ID" ]; then
    echo "Skipping deploy because it's a pull request"
    exit 0
fi

# Set variables from arguments
VERSION=$1
# Set the environment to the second argument or determine it from the branch.
if [ ! -z $2 ]; then
    ENVIRONMENT=$2
else
    # If using Jenkins
    [ ! -z "BRANCH_NAME" ] && BRANCH=$BRANCH_NAME
    # If using Travis
    [ ! -z "TRAVIS_BRANCH" ] && BRANCH=$TRAVIS_BRANCH

    [ -z "BRANCH" ] && echo "Unable to determine branch." && exit 1

    # Deploy to staging if this is on the master branch
    [ ${BRANCH} == "master" ] && ENVIRONMENT=staging
    [ ${BRANCH} == "integration" ] && ENVIRONMENT=integration
fi

[ -z "ENVIRONMENT" ] && echo "Could not determine deployment environment." && exit 1

# Display rc file info and exit if neither a .depllyrc or rc file for the selected environment is found.
[ ! -f $PWD/.deployrc ] && [ ! -f $PWD/.deployrc.${ENVIRONMENT} ] && rc_help && exit 2

# Run the .deployrc and then overwrite it with the environment-specific one (if exists)
[ -f $PWD/.deployrc ] && source ${PWD}/.deployrc
[ -f $PWD/.deployrc.${ENVIRONMENT} ] && source ${PWD}/.deployrc.${ENVIRONMENT}

# Exit if we're missing a required setting.
[ -z "$NAME" ] && rc_help "missing NAME in .deployrc" && exit 2
[ -z "$REPO" ] && rc_help "missing REPO in .deployrc" && exit 2
[ -z "$REGION" ] && rc_help "missing REGION in .deployrc" && exit 2
[ -z "$CLUSTER" ] && rc_help "missing CLUSTER in .deployrc" && exit 2
[ -z "$SUBNETS" ] && rc_help "missing SUBNETS in .deployrc" && exit 2
[ -z "$SECURITY_GROUPS" ] && rc_help "missing SECURITY_GROUPS in .deployrc" && exit 2
[ -z "$IAM_ROLE" ] && rc_help "missing IAM_ROLE in .deployrc" && exit 2

# Set defaults
[ -z "$CPU" ] && CPU=1024
[ -z "$MEMORY" ] && MEMORY=2048
[ -z "$PORT" ] && PORT=8080
[ -z "$LB_HEALTH_PATH" ] && LB_HEALTH_PATH="/"
[ -z "$LB_HEALTH_GRACE_PERIOD" ] && LB_HEALTH_GRACE_PERIOD=120
[ -z "$CONTAINER_HEALTH_COMMAND" ] && CONTAINER_HEALTH_COMMAND="true"
[ -z "$CONTAINER_HEALTH_INTERVAL" ] && CONTAINER_HEALTH_INTERVAL=10
[ -z "$CONTAINER_HEALTH_TIMEOUT" ] && CONTAINER_HEALTH_TIMEOUT=5
[ -z "$CONTAINER_HEALTH_RETRIES" ] && CONTAINER_HEALTH_RETRIES=5
[ -z "$CONTAINER_HEALTH_START_PERIOD" ] && CONTAINER_HEALTH_START_PERIOD=90

# Parse ENV_VARS into JSON
ENV_VARS_PARSED=`( set -o posix ; set ) | \
grep -e 'ENV_' | \
sed -e 's/^ENV_//g' | \
sed -e 's/^/{\"name\":\"/g' | \
sed -e 's/=/\",\"value\":\"/g' | \
sed -e 's/$/\"}/g' | \
paste -sd "," -`
ENV_VARS_PARSED="[$ENV_VARS_PARSED]"

CONTAINER_HEALTH_CHECK="{\
      \"command\": [\"CMD-SHELL\", \"$CONTAINER_HEALTH_COMMAND\"],\
      \"interval\": $CONTAINER_HEALTH_INTERVAL,\
      \"timeout\": $CONTAINER_HEALTH_TIMEOUT,\
      \"retries\": $CONTAINER_HEALTH_RETRIES,\
      \"startPeriod\": $CONTAINER_HEALTH_START_PERIOD\
    }"

CONTAINERS="[\
    {\
      \"logConfiguration\": {\
        \"logDriver\": \"awslogs\",\
        \"options\": {\
          \"awslogs-group\": \"/ecs/${NAME}-${ENVIRONMENT}\",\
          \"awslogs-region\": \"${REGION}\",\
          \"awslogs-stream-prefix\": \"ecs\"\
        }\
      },\
      \"portMappings\": [\
        {\
          \"hostPort\": $PORT,\
          \"protocol\": \"tcp\",\
          \"containerPort\": $PORT\
        }\
      ],\
      \"cpu\": \"${CPU}\",\
      \"environment\": ${ENV_VARS_PARSED},\
      \"memoryReservation\": \"${MEMORY}\",\
      \"image\": \"${REPO}:${VERSION}\",\
      \"healthCheck\": $CONTAINER_HEALTH_CHECK,\
      \"essential\": true,\
      \"name\": \"${NAME}-${ENVIRONMENT}\"\
    }\
  ]"

aws --region ${REGION} ecs register-task-definition \
--family ${NAME}-${ENVIRONMENT} \
--task-role-arn ${IAM_ROLE} \
--execution-role-arn ${IAM_ROLE} \
--network-mode awsvpc \
--requires-compatibilities "EC2" \
--cpu ${CPU} \
--memory ${MEMORY} \
--container-definitions ${CONTAINERS} | tee new-task.json

ARN=`grep taskDefinitionArn new-task.json | cut -d "\"" -f 4 | sed -e 's/"//g' | sed -e 's/,//g' | xargs`
aws --region ${REGION} ecs update-service --service "${NAME}-${ENVIRONMENT}" \
--cluster ${CLUSTER} \
--task-definition ${ARN} \
--health-check-grace-period-seconds ${LB_HEALTH_GRACE_PERIOD} \
--deployment-configuration maximumPercent=200,minimumHealthyPercent=100 \
--force-new-deployment
