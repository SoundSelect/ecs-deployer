#!/usr/bin/env bash

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
    echo "LISTENER_RULE=\"Field=host-header,Values=myservice.mydomain.com\""
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

load_rc () {
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
    [ -z "${LISTENER_RULE}" ] && rc_help "missing LISTENER_RULE in .deployrc" && exit 2
    #[ -z "$SUBNETS" ] && rc_help "missing SUBNETS in .deployrc" && exit 2
    #[ -z "$SECURITY_GROUPS" ] && rc_help "missing SECURITY_GROUPS in .deployrc" && exit 2
    #[ -z "$IAM_ROLE" ] && rc_help "missing IAM_ROLE in .deployrc" && exit 2

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
}

docker_push () {
    IMAGE_VERSION=$1
    eval $(aws ecr get-login --no-include-email --region ${REGION})
    # Build and push
    docker build -t ${IMAGE_NAME} .
    echo "Built docker image for version $IMAGE_VERSION"
    echo "Pushing ${NAME}"':latest'
    docker tag ${NAME}:latest ${REPO}':latest'
    docker push ${REPO}':latest'
    echo "Pushing ${NAME}"':'"$IMAGE_VERSION"
    docker tag ${NAME}:latest ${REPO}':'${IMAGE_VERSION}
    docker push ${REPO}':'${IMAGE_VERSION}
    echo "Pushed ${NAME}"':'"$IMAGE_VERSION"
}
