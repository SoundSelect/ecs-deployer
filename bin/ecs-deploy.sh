#!/usr/bin/env bash
set -e

source `dirname "$0"`/rcutils.sh

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

# Load all the variables from the rc files.
load_rc

# Install the AWS CLI if it is not present.
if ! [ -x "$(command -v aws)" ]; then
    pip install --user awscli
    export PATH=$PATH:$HOME/.local/bin
fi

# Build and push the docker image if we are on integration or master branch
if [ ${BRANCH} == "master" ]  || [ ${BRANCH} == "integration" ]; then
    eval $(aws ecr get-login --no-include-email --region ${REGION})
    docker build -t ${IMAGE_NAME} .
    echo "Built docker image for version $IMAGE_VERSION"
    echo "Pushing ${NAME}"':latest'
    docker tag ${NAME}:latest ${REPO}':latest'
    docker push ${REPO}':latest'
    echo "Pushing ${NAME}"':'"$IMAGE_VERSION"
    docker tag ${NAME}:latest ${REPO}':'${IMAGE_VERSION}
    docker push ${REPO}':'${IMAGE_VERSION}
    echo "Pushed ${NAME}"':'"$IMAGE_VERSION"
fi

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
