#! /usr/bin/env perl
use strict;
use warnings;

use lib "t/lib";
use TestShared qw( do_subtests try_err );

use File::Temp 'tempdir';
use Test::More;


sub main {
    do_subtests(qw( xprop_fail_tt ));
    return 0;
}

main();


sub xprop_fail_tt {
    plan tests => 3;

    my $tempdir = tempdir('we_nx.XXXXXX', TMPDIR => 1, CLEANUP => 1);
    local $ENV{PATH} = $tempdir; # contains no exes

    my $mod_fn = 'Zircon/Tk/WindowExists.pm';
    is($INC{$mod_fn}, undef, 'Z:T:WE not yet loaded');
    my $got = try_err { require Zircon::Tk::WindowExists; 1 };
    like($got, qr{^ERR:Could not find xprop}, 'Compiling Z:T:WE');

    my $fn = "$tempdir/xprop";
    my $fh;
    ((open $fh, '>', $fn) &&
     close $fh &&
     chmod 0755, $fn)
      or die "Failed to make stub xprop: $!";

    {
        delete $INC{$mod_fn}; # needed to permit re-require
        local $SIG{__WARN__} = sub {};
        # no warnings 'redefine'; # does not affect the compiling module scope
        require Zircon::Tk::WindowExists;
    }
    unlink $fn
      or die "Failed to remove duff xprop: $!";

    $got = try_err { Zircon::Tk::WindowExists->query('0x1234', 'FOO') };
    like($got, qr{^ERR:.* failed to exec },
         'Clear fail when xprop disappeared');

    return;
}
