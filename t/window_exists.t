#! /usr/bin/env perl
use strict;
use warnings;

use lib "t/lib";
use TestShared qw( have_display do_subtests mkwidg try_err );

use Test::More;
use Try::Tiny;
use Tk;

use Zircon::Tk::WindowExists;


sub main {
    have_display();
    do_subtests(qw( clean_exit_tt tied_handles_tt ));
    return 0;
}

main();


sub clean_exit_tt {
    my $M = mkwidg();

    # Check for exit code
    my $we = Zircon::Tk::WindowExists->new;
    my $gone_id;
    {
        my $gone = $M->Frame->pack;
        $gone_id = $gone->id;
        $gone->destroy;
    }
    is($we->query( $gone_id ), 0, 'see absence of gone-frame');
    my $exit = $we->tidy;
    is(sprintf('0x%X', $exit), '0x100', 'child exit code: Xlib exit');

    # Check for clean exit
    $we = Zircon::Tk::WindowExists->new;
    is($we->query( $M->id ), 1, 'see our MainWindow');
    close $we->out; # emulate the parent closing
    sleep 1; # bodge delay, giving child time to see EOF
    $exit = $we->tidy; # sends SIGINT to be sure
    is(sprintf('0x%X', $exit), '0x0', 'child exit code: EOF');

    return;
}

sub tied_handles_tt {
    plan tests => 2;
    my $M = mkwidg();
    my $winid = $M->id;

    my $dut = Zircon::Tk::WindowExists->new; # device under test
    my $got = try_err { $dut->query($winid) };
    is($got, 1, 'child process sees our window');

    return;
}
