#!/bin/bash
set -e
source `dirname "$0"`/rc_functions.sh

# Define help function
function help () {
    echo "deploy.sh - Deploy updated service in ECS."
    echo
    echo "Usage:"
    echo "ecs-deployer/bin/deploy.sh [-h] [-v] [-d] [-e env-name] -t docker-tag"
    echo
    echo "Options:"
    echo "-h: Displays this information."
    echo "-v: Verbose mode on."
    echo "-d: Dry run.  AWS commands will not be executed."
    echo "-t: Docker tag to deploy. Required."
    echo "-e: Deployment environment."
    echo
    echo "Examples:"
    echo
    echo "# Automatically determine the target environment from the"
    echo "# branch and deploy the \"latest\" tag."
    echo "ecs-deployer/bin/deploy.sh -t latest"
    echo
    echo "# Dry run with verbose output for the 1.3.4 tag."
    echo "ecs-deployer/bin/deploy.sh -t 1.3.4 -v -d"
    rc_help
    exit 1;
}

# Parse arguments into variables.
while getopts ":hvdt:e:" opt; do
    case $opt in
    h) help ;;
    v) verbose=1 ;;
    d) dryrun=1 ;;
    t) tag=$OPTARG ;;
    e) environment=$OPTARG ;;
    \?) echo "Invalid option: -$OPTARG" >&2 && help ;;
    esac
done
[ -z "$tag" ] && echo "tag is a required argument" && help

# Exit if this was triggered by a pull request.
if [ "$TRAVIS_PULL_REQUEST" == "true" ] || [ -z "CHANGE_ID" ]; then
    echo "Skipping deploy because it's a pull request"
    exit 0
fi

# If the environment wasn't passed, determine it from the branch.
if [ -z "${environment}" ]; then
    # If using Jenkins
    [ ! -z "$BRANCH_NAME" ] && branch=$BRANCH_NAME
    # If using Travis
    [ ! -z "$TRAVIS_BRANCH" ] && branch=$TRAVIS_BRANCH
    [ -z "${branch}" ] && echo "Unable to determine branch." && exit 1
    # Deploy to staging if this is on the master branch.
    [ ${branch} == "master" ] && environment=staging
    [ ${branch} == "integration" ] && environment=integration
fi
[ -z "environment" ] && echo "Could not determine deployment environment." && exit 1

# Load all the settings from the rc files.
load_rc
[ ! -z "$verbose" ] && echo `( set -o posix ; set )`

# Install the AWS CLI if it is not present.
if ! [ -x "$(command -v aws)" ]; then
    [ ! -z "$verbose" ] && echo "Installing AWS CLI"
    pip install --user awscli
    export PATH=$PATH:$HOME/.local/bin
fi

# Before we actually do anything, let's make sure there is a service to update.  We will also capture the target group ARN to use later.
describe_service_cmd="aws --region ${region} ecs describe-services --services "${name}-${environment}" --cluster ${cluster}"
[ ! -z "$verbose" ] && echo "running command: $describe_service_cmd"
target_group_arn=`${describe_service_cmd} | grep "targetGroupArn" | cut -d "\"" -f 4 | sed -e 's/"//g' | sed -e 's/,//g' | xargs`
[ -z ${target_group_arn} ] && echo "The service that you are trying to update does not exist. \
Before the deployer can automatically update your service, you first create it with the provision.sh script." && exit 1
# Before we actually do anything, let's make sure there is a service to update.
# We will also capture the target group ARN to use later.
service_cmd="aws --region ${region} ecs describe-services --services "${name}-${environment}" --cluster ${cluster}"
[ ! -z "$verbose" ] && echo "running command: $service_cmd"
target_group_arn=`${service_cmd} | grep "targetGroupArn" | cut -d "\"" -f 4 | sed -e 's/"//g' -e 's/,//g' | xargs`
if [ -z ${target_group_arn} ]; then
    echo "The service that you are trying to update does not exist."
    echo "Before the script can automatically update your service,"
    echo "you must first create it with the provision.sh script."
    exit 1
fi
[ ! -z "$verbose" ] && echo "target group: $target_group_arn"

# We also need to see what listener rule forwards traffic to this target group so we can modify the rule if necessary.
describe_roles_cmd="aws --region ${region} elbv2 describe-rules --listener-arn ${listener_arn}"
[ ! -z "$verbose" ] && echo "running command: $describe_roles_cmd"
rule_arn=`${describe_roles_cmd} | jq ".Rules | to_entries[] | .value | select(.Actions[0].TargetGroupArn == \"${target_group_arn}\") | .RuleArn" | sed -e 's/"//g'`
[ -z "$rule_arn" ] && echo "Could not find the rule to modify in your target configuration.  Did you delete the load balancer rule?" && exit 1
[ ! -z "$verbose" ] && echo "rule: $rule_arn"

# Parse ENV_VARS into JSON
env_vars_parsed=`( set -o posix ; set ) | \
grep -e 'env_' | \
sed -e 's/^env_//g' -e 's/^/{\\\"name\\\":\\\"/g' -e 's/=/\\\",\\\"value\\\":\\\"/g' -e 's/$/\\\"}/g' | \
paste -sd "," -`
env_vars_parsed="[$env_vars_parsed]"

# If this isn't a dry run do all the real work.
if  [ -z ${dryrun} ]; then

    # Build and push the docker image if we are on integration or master branch.
    if [ ${branch} == "master" ]  || [ ${branch} == "integration" ]; then
        # This is how we login to ECR.  The script returns a set of env vars that are set by evaluating the response.
        eval $(aws ecr get-login --no-include-email --region ${region})
        docker build -t ${name} .
        echo "Built docker image for tag $tag"
        echo "Pushing ${name}"':latest'
        docker tag ${name}:latest ${repo}':latest'
        docker push ${repo}':latest'
        echo "Pushing ${name}"':'"$tag"
        docker tag ${name}:latest ${repo}':'${tag}
        docker push ${repo}':'${tag}
        echo "Pushed ${name}"':'"$tag"
    fi

    modify_target_cmd="aws --region ${region} elbv2 modify-target-group \
    --target-group-arn ${target_group_arn} \
    --health-check-port ${port} \
    --health-check-path ${lb_health_path}"
    [ ! -z "$verbose" ] && echo "running command: $modify_target_cmd"
    eval ${modify_target_cmd}

    modify_rule_cmd="aws --region ${region} elbv2 modify-rule \
    --rule-arn ${rule_arn} \
    --conditions ${listener_rule}"
    [ ! -z "$verbose" ] && echo "running command: $modify_rule_cmd"
    eval ${modify_rule_cmd}

    register_task_cmd="aws --region ${region} ecs register-task-definition \
    --family ${name}-${environment} \
    --task-role-arn ${iam_role} \
    --execution-role-arn ${iam_role} \
    --network-mode awsvpc \
    --requires-compatibilities "EC2" \
    --cpu ${cpu} \
    --memory ${memory} \
    --container-definitions \
    \"[\
        {\
          \\\"logConfiguration\\\": {\
            \\\"logDriver\\\": \\\"awslogs\\\",\
            \\\"options\\\": {\
              \\\"awslogs-group\\\": \\\"/ecs/${name}-${environment}\\\",\
              \\\"awslogs-region\\\": \\\"${region}\\\",\
              \\\"awslogs-stream-prefix\\\": \\\"ecs\\\"\
            }\
          },\
          \\\"portMappings\\\": [\
            {\
              \\\"hostPort\\\": $port,\
              \\\"protocol\\\": \\\"tcp\\\",\
              \\\"containerPort\\\": $port\
            }\
          ],\
          \\\"cpu\\\": ${cpu},\
          \\\"environment\\\": ${env_vars_parsed},\
          \\\"memoryReservation\\\": ${memory},\
          \\\"image\\\": \\\"${repo}:${tag}\\\",\
          \\\"healthCheck\\\": {\
              \\\"command\\\": [\\\"CMD-SHELL\\\", \\\"$container_health_command\\\"],\
              \\\"interval\\\": $container_health_interval,\
              \\\"timeout\\\": $container_health_timeout,\
              \\\"retries\\\": $container_health_retries,\
              \\\"startPeriod\\\": $container_health_start_period\
          },\
          \\\"essential\\\": true,\
          \\\"name\\\": \\\"${name}-${environment}\\\"\
        }\
    ]\""

    [ ! -z "$verbose" ] && echo "running command: $register_task_cmd"
    eval ${register_task_cmd} | tee new-task.json

    [ ! -z "$verbose" ] && echo "new task:" && cat new-task.json

    task_arn=`grep taskDefinitionArn new-task.json | cut -d "\"" -f 4 | sed -e 's/"//g' -e 's/,//g' | xargs`
    [ ! -z "$verbose" ] && echo "extracted arn:" && echo ${task_arn}

    update_service_cmd="aws --region ${region} ecs update-service --service "${name}-${environment}" \
    --cluster ${cluster} \
    --task-definition ${task_arn} \
    --desired-count ${task_count} \
    --health-check-grace-period-seconds ${lb_health_grace_period} \
    --network-configuration \
    \"awsvpcConfiguration={subnets=[$subnets],securityGroups=[$security_groups],assignPublicIp=DISABLED}\" \
    --deployment-configuration maximumPercent=200,minimumHealthyPercent=100 \
    --force-new-deployment"
    [ ! -z "$verbose" ] && echo "running command: $update_service_cmd"
    eval ${update_service_cmd}

fi
