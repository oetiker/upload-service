#!/bin/bash

. `dirname $0`/sdbs.inc

for module in \
    Mojolicious \
    Mojo::Server::FastCGI \
; do
    perlmodule $module
done

# end
