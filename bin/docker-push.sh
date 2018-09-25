#! /bin/bash
set -e

if [ $# -ne 3 ]; then
    echo "Push the docker image to the repo."
    echo
    echo "Usage: docker-push.sh <image name> <remote image url> <version>"
    exit 1
fi

IMAGE_NAME=$1
REMOTE_IMAGE_URL=$2
IMAGE_VERSION=$3

# Push only if it's not a pull request
if [ -z "$TRAVIS_PULL_REQUEST" ] || [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
# Push only if we're testing the master branch
if [ -z "$TRAVIS_BRANCH" ] || [ "$TRAVIS_BRANCH" == "master" ] || [ "$TRAVIS_BRANCH" == "integration" ]; then

if ! [ -x "$(command -v aws)" ]; then
    pip install --user awscli
    export PATH=$PATH:$HOME/.local/bin
fi

eval $(aws ecr get-login --no-include-email --region us-west-2)
# Build and push
docker build -t ${IMAGE_NAME} .
export IMAGE_VERSION=`egrep '^version = ' build.gradle.kts | sed -e 's/"//g' | cut -d "=" -f 2 | xargs`
echo "Built docker image for version $IMAGE_VERSION"
echo "Pushing $IMAGE_NAME"':latest'
docker tag ${IMAGE_NAME}:latest ${REMOTE_IMAGE_URL}':latest'
docker push ${REMOTE_IMAGE_URL}':latest'
echo "Pushing $IMAGE_NAME"':'"$IMAGE_VERSION"
docker tag ${IMAGE_NAME}:latest ${REMOTE_IMAGE_URL}':'${IMAGE_VERSION}
docker push ${REMOTE_IMAGE_URL}':'${IMAGE_VERSION}
echo "Pushed $IMAGE_NAME"':'"$IMAGE_VERSION"
else
echo "Skipping push because branch is not 'master' or 'integration"
fi
else
echo "Skipping push because it's a pull request"
fi
