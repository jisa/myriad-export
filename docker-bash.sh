#!/bin/bash

docker run --rm -it -v "${PWD}":/mnt/myriad --entrypoint bash myriad-export
