#!/bin/sh

# login
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PASSWORD

# install dependencies for running Rake tasks
gem install --no-ri --no-doc bundler rake colorize dotenv

rake release:build_docker
rake release:push_docker
