#!/bin/sh
export US_ROOT=/tmp/us-test
export US_ENABLE_DOWNLOAD=0
export US_ENABLE_DELETE=0
export US_SINGLE=0
export US_SECRET_FILE=./upload-service-secret
mkdir -p $US_ROOT
`dirname $0`/us.pl daemon --listen='http://*:9873'
