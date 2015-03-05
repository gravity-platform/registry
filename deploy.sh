#!/bin/env bash

CF_MONGODB_TYPE="default"

if [[ -f `pwd`/deploy.local.sh ]]; then
    . `pwd`/deploy.local.sh
fi

if [[ ! $APP_NAME ]]; then
    read -p "Enter app name: " APP_NAME
fi
if [[ ! $CF_API ]]; then
    read -p "Enter cloudfoundry API endpoint: " CF_API
fi
if [[ ! $CF_DOMAIN ]]; then
    read -p "Enter cloudfoundry DOMAIN: " CF_DOMAIN
fi
if [[ ! $CF_ORG ]]; then
    read -p "Enter cloudfoundry ORG: " CF_ORG
fi
if [[ ! $CF_USER ]]; then
    read -p "Enter cloudfoundry username: " CF_USER
fi
if [[ ! $CF_PASS ]]; then
    read -s -p "Enter cloudfoundry password: " CF_PASS
fi

ECHO_CMD=`which echo`

# suffix from $1 for app name
SUFFIX=${1:-""}
APP_NAME="${APP_NAME}${SUFFIX}"

# check autodeploy
if [[ $CF_AUTODEPLOY -eq true ]]; then
    echo "Autodeploying"
    if [[ $TRAVIS_PULL_REQUEST -eq true ]]; then
        echo "Aborting, pull-request detected"
        exit 0;
    fi
    if [[ $TRAVIS_BRANCH == 'master' ]]; then
        echo "Deploying prod to ${APP_NAME}"
    elif [[ $TRAVIS_BRANCH == 'develop' ]]; then
        APP_NAME="${APP_NAME}-${TRAVIS_BRANCH}"
        echo "Deploying test to ${APP_NAME}"
    else
        echo 'Not deploying due to wrong branch'
        exit 0;
    fi
fi

cf api $CF_API
# call behind pipe to ensure that cf login is not interactive
echo '' | cf login -u $CF_USER -p $( $ECHO_CMD -n $CF_PASS) -o $CF_ORG
if [[ $? -ne 0 ]]; then
    echo "Auth failed"
    echo "Exited with non-zero exit code"
    exit 1;
fi

# create mongodb if it did not exist
cf cs mongodb $CF_MONGODB_TYPE "${APP_NAME}${SUFFIX}-mongodb"

# push webinterface (does a green/blue deploy w/o rollback support)
cf app "${APP_NAME}-blue"
if [[ $? -eq 0 ]]; then
    DEPLOY_TARGET="${APP_NAME}-green"
    OLD_TARGET="${APP_NAME}-blue"
fi
cf app "${APP_NAME}-green"
if [[ $? -eq 0 ]]; then
    DEPLOY_TARGET="${APP_NAME}-blue"
    OLD_TARGET="${APP_NAME}-green"
fi

if [[ ! $DEPLOY_TARGET ]]; then
    echo "Initial Deploy, remember to set up the DB"
    DEPLOY_TARGET="${APP_NAME}-blue"
    OLD_TARGET="${APP_NAME}-green"
fi

echo "Deploying API to ${DEPLOY_TARGET}"
cf push $DEPLOY_TARGET
if [[ $? -ne 0 ]]; then
    echo "Push to ${DEPLOY_TARGET}failed"
    echo "Exited with non-zero exit code"
    exit 1;
fi
echo "Deploy to ${DEPLOY_TARGET} was successful, remapping routes"
cf map-route $DEPLOY_TARGET $CF_DOMAIN -n $APP_NAME
cf unmap-route $OLD_TARGET $CF_DOMAIN -n $APP_NAME
echo "Reaping ${OLD_TARGET}"
cf stop $OLD_TARGET
cf delete $OLD_TARGET -f
echo "So Long, and Thanks for All the Fish"
