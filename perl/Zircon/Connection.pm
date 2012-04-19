
package Zircon::Connection;


=pod

SEQUENCE OF EVENTS

- client : sets request
- server : reads request
- client :
- server : sets reply
- client : reads reply
- server :
- client : processes reply

=cut


use strict;
use warnings;
use feature qw( switch );

use Carp;
use Readonly;
use Scalar::Util qw( weaken );
use Try::Tiny;

Readonly::Scalar my $DEBUG => 0;

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;

    my $widget = $args->{'-widget'};
    defined $widget or die 'missing -widget parameter';
    $self->{'widget'} = $widget;

    my $handler = $args->{'-handler'};
    defined $handler or die 'missing -handler parameter';
    $self->{'handler'} = $handler;
    weaken $self->{'handler'};

    $self->state('inactive');

    return;
}

# client

sub send { ## no critic (Subroutines::ProhibitBuiltinHomonyms) 
    my ($self, $request) = @_;
    $DEBUG and warn sprintf
        "\nZircon::Connection::send()\n>>>\n%s\n<<<\n"
        , $request;
    $self->state eq 'inactive'
        or die 'Zircon: busy connection';
    $self->request($request);
    $self->widget->SelectionOwn(
        '-selection' => $self->local_selection);
    $self->widget->SelectionClear(
        '-selection' => $self->local_selection);
    $self->client_state('client_request');
    return;
}

sub client_callback {
    my ($self) = @_;

    given ($self->state) {

        when ('client_request') {
            $self->client_state('client_waiting');
        }

        when ('client_waiting') {
            my $reply =
                $self->widget->SelectionGet(
                    '-selection' => $self->remote_selection);
            $self->reply($reply);
            $self->client_state('client_reply');
        }

        when ('client_reply') {
            my $reply = $self->reply;
            try {
                $self->handler->zircon_connection_reply($reply);
            }
            catch { die $::_; } # propagate any error
            finally {
                $self->server_state('inactive');
            };
        }

    }

    return;
}

sub client_state {
    my ($self, $state) = @_;
    $DEBUG and warn sprintf
        "Zircon client: %s -> %s\n"
        , $self->state, $state;
    $self->state($state);
    $self->remote_selection_own;
    return;
}

# server

sub server_callback {
    my ($self) = @_;
    given ($self->state) {

        when ('inactive') {
            my $request =
                $self->widget->SelectionGet(
                    '-selection' => $self->local_selection);
            $self->request($request);
            $self->server_state('server_request');
        }

        when ('server_request') {
            my $request = $self->request;
            my $reply = '';
            try {
                $reply = $self->handler->zircon_connection_request($request);
            }
            catch { die $::_; } # propagate any error
            finally {
                $self->reply($reply);
                $self->server_state('server_reply');
            };
        }

        when ('server_reply') {
            $self->server_state('inactive');
        }

    }

    return;
}

sub server_state {
    my ($self, $state) = @_;
    $DEBUG and warn sprintf
        "Zircon server: %s -> %s\n"
        , $self->state, $state;
    $self->state($state);
    $self->local_selection_own;
    return;
}

# selections

sub local_selection {
    my ($self, @args) = @_;
    if (@args) {
        my ($local_selection) = @args;
        $self->{'local_selection'} = $local_selection;
        if (defined $local_selection) {
            $self->widget->SelectionHandle(
                -selection => $local_selection,
                $self->callback('local_selection_callback'));
            $self->local_selection_own;
        }
    }
    return $self->{'local_selection'};
}

sub local_selection_own {
    my ($self) = @_;
    my $local_selection = $self->local_selection;
    if (defined $local_selection) {
        $self->widget->SelectionOwn(
            '-selection' => $local_selection,
            '-command' => $self->callback('server_callback'),
            );
    }
    return;
}

sub local_selection_callback {
    my ($self, @args) = @_;
    return $self->selection_callback('reply', @args);
}

sub remote_selection {
    my ($self, @args) = @_;
    if (@args) {
        my ($remote_selection) = @args;
        $self->{'remote_selection'} = $remote_selection;
        if (defined $remote_selection) {
            $self->widget->SelectionHandle(
                -selection => $remote_selection,
                $self->callback('remote_selection_callback'));
        }
    }
    return $self->{'remote_selection'};
}

sub remote_selection_own {
    my ($self) = @_;
    my $remote_selection = $self->remote_selection;
    if (defined $remote_selection) {
        $self->widget->SelectionOwn(
            '-selection' => $remote_selection,
            '-command' => $self->callback('client_callback'),
            );
    }
    return;
}

sub remote_selection_callback {
    my ($self, @args) = @_;
    return $self->selection_callback('request', @args);
}

sub selection_callback {
    my ($self, $method, $offset, $bytes) = @_;
    my $content = $self->$method;
    my $size = (length $content) - $offset;
    return
        $size < $bytes
        ? substr $content, $offset
        : substr $content, $offset, $bytes
        ;
}

# callbacks

sub callback {
    my ($self, $method) = @_;
    return $self->{'callback'}{$method} ||=
        $self->_callback($method);
}

sub _callback {
    my ($self, $method) = @_;
    weaken $self; # break circular references
    my $callback = sub {
        defined $self or return; # because a weak reference may become undef
        return $self->$method(@_);
    };
    return $callback;
}

# attributes

sub handler {
    my ($self) = @_;
    return $self->{'handler'};
}

sub widget {
    my ($self) = @_;
    return $self->{'widget'};
}

sub request {
    my ($self, @args) = @_;
    ($self->{'request'}) = @args if @args;
    return $self->{'request'};
}

sub reply {
    my ($self, @args) = @_;
    ($self->{'reply'}) = @args if @args;
    return $self->{'reply'};
}

sub state { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self, @args) = @_;
    ($self->{'state'}) = @args if @args;
    return $self->{'state'};
}

1;
