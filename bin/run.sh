#!/bin/sh
export US_ROOT=/scratch/oetiker/INBOX
export US_SINGLEUSER=1
export US_TAGMODE=1
export US_SECRET_FILE=./upload-service-secret
export MOJO_TMPDIR=$US_ROOT
mkdir -p $US_ROOT
`dirname $0`/us.pl prefork --listen='http://*:9873'
