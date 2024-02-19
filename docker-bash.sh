#!/bin/bash

docker run --rm -it -v "${PWD}":/mnt/myriad -v /dev/bus/usb:/dev/bus/usb --entrypoint bash myriad-export
