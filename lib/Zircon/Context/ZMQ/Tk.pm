
package Zircon::Context::ZMQ::Tk;

use strict;
use warnings;

use Carp qw( croak cluck );
use Scalar::Util qw( weaken refaddr );
use Tk;

use base 'Zircon::Context::ZMQ';

sub _init {
    my ($self, $args) = @_;
    $self->{'_waitVariable_hash'} = { };
    my $widget = $args->{'-widget'};
    defined $widget or die 'missing -widget argument';
    $self->{'widget'} = $widget;
    return $self->SUPER::_init($args);
}

sub close {
    my ($self) = @_;
    $self->zircon_trace;
    $self->SUPER::close;
    delete $self->{'widget'};
    return;
}

# timeouts

sub timeout {
    my ($self, @args) = @_;

    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to set timeout with destroyed widget";
    my $timeout_handle = $w->after(@args);
    $self->zircon_trace('configured (%d millisec)', $args[0]);
    return $timeout_handle;
}

sub cancel_timeout {
    my ($self, $handle) = @_;
    $handle->cancel;
    return;
}

# filevent callback plumbing

sub register_recv_fh {
    my ($self, $fh) = @_;
    open my $dup_fh, '<&', $fh or die "failed to dup socket fd: $!";
    $self->recv_fh($dup_fh);
    return;
}

sub connect_recv_callback {
    my ($self) = @_;
    $self->widget->fileevent(
        $self->recv_fh,
        'readable',
        sub { return $self->_server_callback; },
        );
    return;
}

sub disconnect_recv_callback {
    my ($self) = @_;

    my $w = $self->widget;
    return unless Tk::Exists($w);

    $w->fileevent(
        $self->recv_fh,
        'readable',
        '',
        );
    return;
}

# trace

sub trace_prefix {
    my ($self, @args) = @_;
    my $path = $self->SUPER::trace_prefix(@args);
    unless ($path) {
        my $w = $self->widget;
        $path = sprintf('widget=%s', Tk::Exists($w) ? $w->PathName : '(destroyed)');
    }
    return $path;
}

# waiting

sub waitVariable {
    my ($self, $var) = @_;
    $self->_waitVariable_hash->{$var} = $var;
    weaken $self->_waitVariable_hash->{$var};
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to waitVariable with destroyed widget";

    $self->zircon_trace('startWAIT(0x%x) for %s=%s', refaddr($self), $var, $$var);
    $w->waitVariable($var); # traced
    $self->zircon_trace('stopWAIT(0x%x) with %s=%s', refaddr($self), $var, $$var);
    Tk::Exists($w)
        or cluck "Widget $w destroyed during waitVariable";
    return;
}

sub _close_waitVariables {
    my ($self, $reason) = @_;
    my $_waitVariable_hash = $self->_waitVariable_hash;
    return unless $_waitVariable_hash;
    foreach my $ref (values %{$_waitVariable_hash}) {
        defined $ref or next;
        ${$ref} = $reason;
    }
    return;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

sub _waitVariable_hash {
    my ($self) = @_;
    my $_waitVariable_hash = $self->{'_waitVariable_hash'};
    return $_waitVariable_hash;
}

sub DESTROY {
    my ($self) = @_;
    $self->zircon_trace;
    $self->SUPER::DESTROY;
    $self->_close_waitVariables('zircon_context_destroyed');
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
