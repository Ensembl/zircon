#! /usr/bin/env perl
use strict;
use warnings;

use AnyEvent::Impl::Perl;       # (try to) ensure pure-perl loop is used
use AnyEvent;

use Test::More;
use Try::Tiny;
use POSIX ":sys_wait_h";

use Zircon::Context::ZMQ::AnyEvent;
use Zircon::Protocol;

use lib "t/lib";
use TestShared qw( have_display do_subtests register_kid test_zap );

our $WINDOW_ID_RE = qr{^0x[0-9a-f]{4,10}$};


sub main {
    have_display();
    do_subtests(qw( zirpro_tt ));
    return;
}

main();
exit;

sub init_zircon_proto {
    my ($server) = @_;

    my $name = $0;
    $name =~ s{.*/}{};

    my $context = Zircon::Context::ZMQ::AnyEvent->new(-trace_prefix => "$name");
    my $proto = Zircon::Protocol->new
      (-app_id => $name,
       -app_tag => 'zircon_protocol_ae',
       -context => $context,
       -serialiser => 'JSON',
       -server => $server);

    return $proto;
}


# Start zircon_protocol_test,
# wait for handshake,
# send it a shutdown,
# see it is gone.
sub zirpro_tt {
    plan tests => 8;

    my $server_cv = AnyEvent->condvar;

    my $server = MockServer->new($server_cv);
    my $proto = init_zircon_proto($server);

    my @cmd = ('bin/zircon_protocol_test',
               -app_tag         => 'zircon_protocol_ae',
               -remote_endpoint => $proto->connection->local_endpoint,
               -serialiser      => 'JSON');
    my $pid = open my $fh, '-|', @cmd;
    isnt(0, $pid, "Pipe from @cmd") or diag "Failed: $!";
    return unless $pid;
    register_kid($pid);

    my $timeout = AnyEvent->timer(after => 5.000, cb => sub { test_zap('safety timeout') });
    $server_cv->recv;

    is(scalar @{$server->{_msg}}, 1, 'one event logged by Server')
      or diag explain $server;
    like($server->{_msg}->[0], qr{^handshake: id}, 'handshake happened');

    is($proto->connection->state, 'inactive', 'connection cycle is finished');

    # XXX: workaround for "Server ACKed our request without reading it", connection out of sync
    wait_ms(500);

    my $flag = 'begin';
    my $shutdown_cv = AnyEvent->condvar;
    $proto->send_shutdown_clean(sub { $flag='going'; $shutdown_cv->send('going'); });
    $shutdown_cv->recv;
    is($flag, 'going', 'shutdown sent');

    # give the child time to acknowledge & quit
    my ($i, $gone_pid, $gone_err) = (10);
    while (!$gone_pid) {
        wait_ms(100);

        $gone_pid = waitpid(-1, WNOHANG);
        $gone_err = $?;
    }
    is($pid, $gone_pid, 'child is gone');
    is(0, $gone_err, 'child returned 0');

    try { undef $timeout; };

    is((kill 'INT', $pid) || $!, 'No such process', 'kill? already gone');

    return ();
}

sub wait_ms {
    my ($delay) = @_;
    my $cv = AnyEvent->condvar;
    my $timeout = AnyEvent->timer(after => ($delay / 1000), cb => sub { $cv->send('waited') });
    $cv->recv;
    diag "waited $delay ms";
    return;
}


package MockServer;
use base qw( Zircon::Protocol::Server );

sub new {
    my ($pkg, $cv) = @_;
    my $self = { _cv => $cv, _msg => [] };
    return bless $self, $pkg;
}

sub zircon_server_log {
    my ($self, $message) = @_;
    push @{$self->{_msg}}, $message;
    $self->{_cv}->send($message);
    return;
}
