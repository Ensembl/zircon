#! /usr/bin/env perl
use strict;
use warnings;

use lib "t/lib";
use TestShared qw( have_display init_zircon_conn );

use Test::More;
use Try::Tiny;
use Tk;

use Zircon::Tk::Context;
use Zircon::Connection;


sub main {
    have_display();

    plan tests => 6;
    predestroy_tt();
    postdestroy_tt();

    return 0;
}

main();

sub try_err(&) {
    my ($code) = @_;
    return try { goto &$code } catch {"ERR:$_"};
}


sub predestroy_tt {
    # make a window which is already destroyed
    my $M = MainWindow->new;
    my $make_it_live = $M->id;
    $M->destroy;

    # Zircon can't use it
    my $got = try_err { init_zircon_conn($M, qw( me_local me_remote )) };

    like($got, qr{^ERR:Attempt to construct with invalid widget},
         "Z:T:Context->new with destroyed widget");
}


sub postdestroy_tt {
    my $M = MainWindow->new;
    my $make_it_live = $M->id;

    my $handler = try_err { init_zircon_conn($M, qw( me_local me_remote )) };
    is(ref($handler), 'ConnHandler', 'postdestroy_tt: init');
    my $sel = $handler->zconn->selection('local');

    $M->destroy;
    my $want = sub {
        my ($what) = @_;
        return qr{^ERR:Attempt to .*$what.* with destroyed widget at };
    };

    my $do_fail = sub { fail('timeout happened') };
    my $got = try_err { $handler->zconn->timeout(100, $do_fail) };
    like($got, $want->('timeout'), 'timeout after destroy');

    my $old_own = $sel->owns;
    $got = try_err { $sel->owns(0); $sel->own(); };
    like($got, $want->('own'), 'own after destroy');
    $sel->owns($old_own);

    $got = try_err { $handler->zconn->send('message'); 'done' };
    like($got, $want->('clear|own'), 'send after destroy');

    $got = try_err { $handler->zconn->reset; 'done' };
    is($got, 'done', 'reset should still work');
}
