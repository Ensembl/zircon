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

    plan tests => 2;
    predestroy_tt();
    postdestroy_tt();

    return 0;
}

main();


sub predestroy_tt {
    # make a window which is already destroyed
    my $M = MainWindow->new;
    my $make_it_live = $M->id;
    $M->destroy;

    # Zircon can't use it
    my $got = try { init_zircon_conn($M, qw( me_local me_remote )) }
      catch { "FAIL:$_" };

    like($got, qr{^FAIL:Attempt to construct with invalid widget},
         "Z:T:Context->new with destroyed widget");
}


sub postdestroy_tt {
    my $M = MainWindow->new;
    my $make_it_live = $M->id;

    my $handler = init_zircon_conn($M, qw( me_local me_remote ));
    is(ref($handler), 'ConnHandler', 'postdestroy_tt: init');

    $M->destroy;
    my $got = try { $handler->zconn->send('message'); 'done' } catch {"FAIL:$_"};
    like($got, qr{^FAIL:moo}, "send after destroy");
}
