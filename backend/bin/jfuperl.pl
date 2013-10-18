#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../thirdparty/lib/perl5";
use lib "$FindBin::Bin/../lib";
# use lib qw() # PERL5LIB
use Mojolicious::Commands;
use JfuPerl;

our $VERSION = "0";

# Start commands
Mojolicious::Commands->start_app('JfuPerl');
