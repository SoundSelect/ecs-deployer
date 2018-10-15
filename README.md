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
    listener_arn=arn:aws:elasticloadbalancing:us-west-2:123456789012:listener/app/int-rbcm/cbb0779036bb392e/fa1d65163f86dc2e

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
    dockerfile_path="."
    log_retention_days=7

You may also set env vars by prefixing the var name with env_

    env_SPRING_PROFILES_ACTIVE=production
    env_deploy_time=`date`

## Travis and Jenkins Integration
The deploy script is aware of Travis and Jenkins ENV vars to give it clues on how to automatically deploy.
This is based off of the deployment schema that I use on all my other projects.

On my team, developers work in feature branches and merge to a branch called "integration" to integrate and test their
changes with the team. Integration commits/merges are automatically deployed to the integration environment.  Every
merge requires a version bump in the gradle build file (for Java/Kotlin projects) or the package.json (for node.js).
I use these versions to tag the docker images and then it's always easy to tell what is in any env, what feature train
it is on, etc.

A typical travis.yml looks like this:

    language: java
    sudo: required
    services:
      - docker
    before_cache:
      - rm -f  $HOME/.gradle/caches/modules-2/modules-2.lock
      - rm -fr $HOME/.gradle/caches/*/plugin-resolution/
    cache.directories:
      - $HOME/.gradle/caches/
      - $HOME/.gradle/wrapper/
    script:
      - ./gradlew build
    after_success:
      - git clone https://github.com/advantageous/ecs-deployer.git
      - ecs-deployer/bin/deploy.sh -t `egrep '^version = ' build.gradle.kts | sed -e 's/"//g' | cut -d "=" -f 2 | xargs`


When the feature is done and ready for QA, it is merged to the master branch. Merges to master are automatically
deployed ot the staging environment for QA.  When QA certifies the version that's deployed new tags are cut in docker
and git and they are deployed to production.

And Bob's your uncle.
