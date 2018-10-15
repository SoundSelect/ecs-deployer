#!/usr/bin/env bash

rc_help() {
    echo $1
    echo
    echo "This script requires a .deployrc configuration file. This"
    echo "file should be placed in the directory which the script is"
    echo "run. This is typically the root of your project beside your"
    echo ".travis.yml or Jenkinsfile."
    echo "You may also specify environment-specific parameters in"
    echo "their own .deployrc.env_name files. For example you can"
    echo "create a .deployrc.prod and its values will override the"
    echo "main one when deploying to a environment named prod."
    echo
    echo "It is important note that the name, region, and cluster can"
    echo "not be changed once the service is created."
    echo
    echo "The following parameters must be contained either in the"
    echo ".deployrc file or the environment-specific rc file:"
    echo
    echo "name=my-service"
    echo "region=us-west-2"
    echo "cluster=arn:aws:ecs:us-west-2:123456789012:cluster/my-cluster"
    echo "repo=123456789012.dkr.ecr.us-west-2.amazonaws.com/my-service"
    echo "subnets=subnet-4cfd6c2a,subnet-53a6101b"
    echo "security_groups=sg-6ba62416"
    echo "iam_role=arn:aws:iam::123456789012:role/ecsTaskExecutionRole"
    echo "vpc_id=vpc-6b8ac90d"
    echo "listener_rule=\"Field=host-header,Values=myservice.mydomain.com\""
    echo "listener_rule_priority=10"
    echo "listener_arn=arn:aws:elasticloadbalancing:us-west-2:309159580642:listener/app/int-rbcm/cbb0779036bb392e/fa1d65163f86dc2e"
    echo
    echo "The following parameters are optional and will default to these values:"
    echo
    echo "cpu=1024"
    echo "memory=2048"
    echo "port=8080"
    echo "task_count=2"
    echo "lb_health_start_period=300"
    echo "lb_health_path=/"
    echo "container_health_command=\"true\""
    echo "container_health_interval=10"
    echo "container_health_timeout=5"
    echo "container_health_retries=5"
    echo "container_health_start_period=90"
    echo "dockerfile_path=\".\""
    echo
    echo "You may also set env vars by prefixing the var name with env_"
    echo "env_SPRING_PROFILES_ACTIVE=production"
    echo "env_deploy_time=\`date\`"
}

load_rc () {
    # Display rc file info and exit if neither a .depllyrc or rc file for the selected environment is found.
    [ ! -f $PWD/.deployrc ] && [ ! -f $PWD/.deployrc.${environment} ] && rc_help "unable to find rc files" && exit 2

    # Run the .deployrc and then overwrite it with the environment-specific one (if exists)
    [ -f $PWD/.deployrc ] && source ${PWD}/.deployrc
    [ -f $PWD/.deployrc.${environment} ] && source ${PWD}/.deployrc.${environment}

    # exit if we're missing a required setting.
    [ -z "$name" ] && rc_help "missing name in .deployrc" && exit 2
    [ -z "$repo" ] && rc_help "missing repo in .deployrc" && exit 2
    [ -z "$region" ] && rc_help "missing region in .deployrc" && exit 2
    [ -z "$cluster" ] && rc_help "missing cluster in .deployrc" && exit 2
    [ -z "${listener_arn}" ] && rc_help "missing listener_arn in .deployrc" && exit 2
    [ -z "${listener_rule}" ] && rc_help "missing listener_rule in .deployrc" && exit 2
    [ -z "${listener_rule_priority}" ] && rc_help "missing listener_rule_priority in .deployrc" && exit 2
    [ -z "${vpc_id}" ] && rc_help "missing vpc_id in .deployrc" && exit 2
    [ -z "$subnets" ] && rc_help "missing subnets in .deployrc" && exit 2
    [ -z "$security_groups" ] && rc_help "missing security_groups in .deployrc" && exit 2
    [ -z "$iam_role" ] && rc_help "missing iam_role in .deployrc" && exit 2

    # Set defaults
    [ -z "$cpu" ] && cpu=1024
    [ -z "$memory" ] && memory=2048
    [ -z "$port" ] && port=8080
    [ -z "$task_count" ] && task_count=2
    [ -z "$lb_health_path" ] && lb_health_path="/"
    [ -z "$lb_health_grace_period" ] && lb_health_grace_period=300
    [ -z "$container_health_command" ] && container_health_command="true"
    [ -z "$container_health_interval" ] && container_health_interval=10
    [ -z "$container_health_timeout" ] && container_health_timeout=5
    [ -z "$container_health_retries" ] && container_health_retries=5
    [ -z "$container_health_start_period" ] && container_health_start_period=90
    [ -z "$dockerfile_path" ] && dockerfile_path="."
    true

}
