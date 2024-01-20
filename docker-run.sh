#!/bin/bash

docker run -v "${PWD}":/mnt/myriad --user $(id -u):$(id -g) myriad-export "$@"
