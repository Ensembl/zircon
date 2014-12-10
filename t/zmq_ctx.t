#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;

plan tests => 7;

my $module = 'Zircon::Context::ZMQ::Ctx';
use_ok($module);

my $c1 = new_ok($module);
my $c2 = new_ok($module);
is($c1, $c2, 'singleton');

ok($module->exists, 'singleton extant');
undef $c1;
ok($module->exists, 'singleton still extant');
undef $c2;
ok(not($module->exists), 'singleton destroyed');

done_testing;
