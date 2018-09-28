# ECS Automation for CI/CD
## Provisioning
Create ECS service and related resources in AWS.
#### Usage:

    ecs-deployer/bin/provision.sh [-h] -e env-name
    
#### Options:
* -h: Displays this information.
* -e: Target environment. Required.

## Deployment
Deploy updated service in ECS.
#### Usage:

    ecs-deployer/bin/deploy.sh [-h] [-v] [-d] [-e env-name] -t docker-tag

#### Options::
* -h: Displays this information.
* -v: Verbose mode on.
* -d: Dry run.  AWS commands will not be executed.
* -t: Docker tag to deploy. Required.
* -e: Deployment environment.

#### Examples:

    # Automatically determine the target environment from the branch and deploy the "latest" tag.
    ecs-deployer/bin/deploy.sh -t latest

    # Dry run with verbose output for the 1.3.4 tag.
    ecs-deployer/bin/deploy.sh -t 1.3.4 -v -d

## Configuration
This script requires a .deployrc configuration file. This file should be placed in the directory which the script is run. This is typically the root of your project beside your .travis.yml or Jenkinsfile.
You may also specify environment-specific parameters in their own .deployrc.env_name files.  For example you can create a .deployrc.prod and its values will override the main one when deploying to a environment named prod.

It is important note that the name, region, and cluster can not be changed once the service is created.

The following parameters must be contained either in the .deployrc file or the environment-specific rc file:

    name=my-service
    region=us-west-2
    cluster=arn:aws:ecs:us-west-2:123456789012:cluster/my-cluster
    repo=123456789012.dkr.ecr.us-west-2.amazonaws.com/my-service
    subnets=subnet-4cfd6c2a,subnet-53a6101b
    security_groups=sg-6ba62416
    iam_role=arn:aws:iam::123456789012:role/ecsTaskExecutionRole
    vpc_id=vpc-6b8ac90d
    listener_rule="Field=host-header,Values=myservice.mydomain.com"
    listener_rule_priority=10
    listener_arn=arn:aws:elasticloadbalancing:us-west-2:309159580642:listener/app/int-rbcm/cbb0779036bb392e/fa1d65163f86dc2e

The following parameters are optional and will default to these values:

    cpu=1024
    memory=2048
    port=8080
    task_count=2
    lb_health_start_period=120
    lb_health_path=/
    container_health_command="true"
    container_health_interval=10
    container_health_timeout=5
    container_health_retries=5
    container_health_start_period=90

You may also set env vars by prefixing the var name with env_

    env_SPRING_PROFILES_ACTIVE=production
    env_deploy_time=`date`
