#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Try::Tiny;
use Tk;
use POSIX ":sys_wait_h";

use Zircon::Tk::Context;
use Zircon::Protocol;

use lib "t/lib";
use TestShared qw( have_display init_zircon_conn do_subtests );

our $WINDOW_ID_RE = qr{^0x[0-9a-f]{4,10}$};


sub main {
    have_display();
    do_subtests(qw( zirpro_tt ));
    return;
}

our @kids;
sub test_zap { # a test abort button
    my ($why) = @_;

    foreach my $w (Tk::MainWindow->Existing) {
        fail("$why: zapping $w\n");
    }

    if (@kids) {
        fail("$why: zapping pids @kids");
        kill 'INT', @kids;
    }

    fail("$why: zapping self");
    kill 'INT', $$;

    return;
}

main();


sub init_zircon_proto {
    my ($server) = @_;

    my $M = MainWindow->new;
    $M->withdraw;
    my $make_it_live = $M->id;

    my $name = $0;
    $name =~ s{.*/}{};

    my $sel_id = join _ => $name, int(rand(1e6));
    $M->title($sel_id);

    my $context = Zircon::Tk::Context->new(-widget => $M);
    my $proto = Zircon::Protocol->new
      (-app_id => $name,
       -context => $context,
       -selection_id => $sel_id,
       -server => $server);

    return ($M, $proto);
}


# Start zircon_protocol_test,
# wait for handshake,
# send it a shutdown,
# see it is gone.
sub zirpro_tt {
    plan tests => 10;

    my $server = MockServer->new;
    my ($M, $proto) = init_zircon_proto($server);

    my @cmd = ('bin/zircon_protocol_test',
               -remote_selection => $proto->connection->local_selection_id);
    my $pid = open my $fh, '-|', @cmd;
    isnt(0, $pid, "Pipe from @cmd") or diag "Failed: $!";
    return unless $pid;
    push @kids, $pid;

    my $timeout = $M->after(5000, [ \&main::test_zap, 'safety timeout' ]);
    $M->waitVariable($server);

    is(scalar @$server, 1, 'one event logged by Server')
      or diag explain $server;
    like($server->[0], qr{^handshake: id}, 'handshake happened');

    like($proto->xid_local,  $WINDOW_ID_RE, 'have local XWin');
    like($proto->xid_remote, $WINDOW_ID_RE, 'have remote XWin');

    # XXX: grubby workaround: $server is told of request before request-ack
    $M->waitVariable(\$proto->connection->{'state'}) # PRIVATE!
      if $proto->connection->state eq 'server_reply';

    is($proto->connection->state, 'inactive', 'connection cycle is finished');

    # XXX: workaround for "Server ACKed our request without reading it", connection out of sync
    wait_ms($M, 500);

    my $flag = 'begin';
    $proto->send_shutdown_clean(sub { $flag='going' });
    $M->waitVariable(\$flag);
    is($flag, 'going', 'shutdown sent');

    # give the child time to acknowledge & quit
    my ($i, $gone_pid, $gone_err) = (10);
    while ($i && !$gone_pid) {
        wait_ms($M, 100);

        $gone_pid = waitpid(-1, WNOHANG);
        $gone_err = $?;
    }
    is($pid, $gone_pid, 'child is gone');
    is(0, $gone_err, 'child returned 0');

    try { $timeout->cancel };

    is((kill 'INT', $pid) || $!, 'No such process', 'kill? already gone');

    return ();
}

sub wait_ms {
    my ($widg, $delay) = @_;
    my $flag = 'waiting';
    $widg->after($delay, sub { $flag = 'waited' });
    $widg->waitVariable(\$flag);
    diag "waited $delay ms";
    return;
}


package MockServer;
use base qw( Zircon::Protocol::Server );

sub new {
    my $self = [];
    return bless $self, __PACKAGE__;
}

sub zircon_server_log {
    my ($self, $message) = @_;
    push @$self, $message;
    return;
}
