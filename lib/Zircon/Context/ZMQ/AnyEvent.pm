
package Zircon::Context::ZMQ::AnyEvent;

use strict;
use warnings;

use Carp qw( croak cluck );
use Scalar::Util qw( weaken refaddr );

use AnyEvent;

use base 'Zircon::Context::ZMQ';

# timeouts

sub timeout {
    my ($self, $interval_ms, $callback) = @_;

    my $timeout_handle = AnyEvent->timer(
        after => ($interval_ms / 1000),
        cb    => $callback,
        );
    $self->zircon_trace('configured (%d millisec)', $interval_ms);
    return $timeout_handle;
}

# WARNING: null, but caller must undefine the handle to cancel the timer!
#
sub cancel_timeout {
    my ($self, $handle) = @_;
    return;
}

# filevent callback plumbing

sub register_recv_fh {
    my ($self, $fh) = @_;
    $self->recv_fh($fh);
    return;
}

sub connect_recv_callback {
    my ($self) = @_;
    my $io = AnyEvent->io(
        fh   => $self->recv_fh,
        poll => "r",
        cb   => sub { return $self->_server_callback; },
        );
    return $self->ae_io($io);
}

sub disconnect_recv_callback {
    my ($self) = @_;
    return $self->ae_io(undef);
}

# attributes

sub ae_io {
    my ($self, @args) = @_;
    ($self->{'ae_io'}) = @args if @args;
    my $ae_io = $self->{'ae_io'};
    return $ae_io;
}

sub DESTROY {
    my ($self) = @_;
    $self->zircon_trace;
    $self->SUPER::DESTROY;
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
