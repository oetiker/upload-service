#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;  
use lib "$FindBin::Bin/../thirdparty/lib/perl5";
use lib "$FindBin::Bin/../lib";
# use lib qw() # PERL5LIB
use Mojolicious::Commands;
use UploadService;

$ENV{MOJO_MAX_MEMORY_SIZE} = 1024*1024*128;

our $VERSION = "0";

# Start commands
Mojolicious::Commands->start_app('UploadService');
