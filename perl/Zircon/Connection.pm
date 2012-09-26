
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
use Scalar::Util qw( weaken );
use Try::Tiny;

my @mandatory_args = qw(
    context
    handler
    );

my $optional_args = {
    'timeout_interval' => 500, # 0.5 seconds
};

my @weak_args = qw(
    handler
    );

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;

    for my $key (@mandatory_args) {
        my $value = $args->{"-${key}"};
        defined $value or die "missing -${key} parameter";
        $self->{$key} = $value;
    }

    while (my ($key, $default) = each %{$optional_args}) {
        my $value = $args->{"-${key}"};
        defined $value or $value = $default;
        $self->$key($value);
    }

    for my $key (@weak_args) {
        weaken $self->{$key};
    }

    $self->state('inactive');
    $self->update;

    return;
}

sub selection_owner_callback {
    my ($self, $key) = @_;
    $self->_do_safely(
        sub { $self->_selection_owner_callback($key); });
    return;
}

sub _selection_owner_callback {
    my ($self, $key) = @_;
    for ($key) {
        when ('local')  { $self->_server_callback; }
        when ('remote') { $self->_client_callback; }
        default {
            die sprintf
                "invalid selection owner callback key: '%s'"
                , $key;
        }
    }
    return;
}

# client

sub send {
    my ($self, $request) = @_;
    $self->state eq 'inactive'
        or die 'Zircon: busy connection';
    $self->selection('remote')->content($request);
    $self->state('client_request');
    $self->update;
    $self->timeout_start;
    return;
}

sub _client_callback {
    my ($self) = @_;

    for ($self->state) {

        when ('client_request') {
            $self->state('client_waiting');
        }

        when ('client_waiting') {
            my $reply = $self->selection('remote')->get;
            $self->reply($reply);
            $self->state('client_reply');
        }

        when ('client_reply') {
            my $reply = $self->reply;
            $self->handler->zircon_connection_reply($reply);
            $self->state('inactive');
        }

        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }

    }

    return;
}

sub go_client {
    my ($self) = @_;
    $self->selection_call('local', 'clear');
    $self->selection_call('remote', 'own');
    return;
}

# server

sub _server_callback {
    my ($self) = @_;

    for ($self->state) {

        when ('inactive') {
            my $request = $self->selection('local')->get;
            $self->request($request);
            $self->state('server_request');
        }

        when ('server_request') {
            my $request = $self->request;
            my $reply = $self->handler->zircon_connection_request($request);
            $self->selection('local')->content($reply);
            $self->state('server_reply');
        }

        when ('server_reply') {
            $self->state('inactive');
        }

        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }

    }

    return;
}

sub go_server {
    my ($self) = @_;
    $self->selection_call('remote', 'clear');
    $self->selection_call('local', 'own');
    return;
}

# selections

sub local_selection_id {
    my ($self, @args) = @_;
    return $self->selection_id('local', @args);
}

sub remote_selection_id {
    my ($self, @args) = @_;
    return $self->selection_id('remote', @args);
}

sub selection_id {
    my ($self, $key, @args) = @_;
    if (@args) {
        my ($id) = @args;
        ( defined $id && $id ne '' )
            or die 'undefined/empty selection ID';
        $self->{'selection'}{$key} =
            $self->context->selection_new(
                '-id'           => $id,
                '-handler'      => $self,
                '-handler_data' => $key,
            );
        $self->update;
    }
    my $selection = $self->{'selection'}{$key};
    my $id = defined $selection ? $selection->id : undef;
    return $id;
}

sub selection {
    my ($self, $key) = @_;
    my $selection = $self->{'selection'}{$key};
    defined $selection
        or die sprintf "Zircon: no selection for key '%s'", $key;
    return $selection;
}

sub selection_call {
    my ($self, $key, $method, @args) = @_;
    my $selection = $self->{'selection'}{$key};
    return unless defined $selection;
    return $selection->$method(@args);
}

# timeouts

sub timeout_start {
    my ($self) = @_;
    my $timeout_handle =
        $self->timeout(
            $self->timeout_interval,
            $self->callback('timeout_callback'));
    $self->timeout_handle($timeout_handle);
    return;
}

sub timeout_cancel {
    my ($self) = @_;
    my $timeout_handle = $self->timeout_handle;
    if (defined $timeout_handle) {
        $timeout_handle->cancel;
        $self->timeout_handle(undef);
    }
    return;
}

sub timeout_callback {
    my ($self) = @_;
    $self->timeout_handle(undef);
    try { $self->handler->zircon_connection_timeout; }
    catch { die $_; } # propagate any error
    finally { $self->reset; };
    return;
}

sub timeout_interval {
    my ($self, @args) = @_;
    ($self->{'timeout_interval'}) = @args if @args;
    return $self->{'timeout_interval'};
}

sub timeout_handle {
    my ($self, @args) = @_;
    ($self->{'timeout_handle'}) = @args if @args;
    return $self->{'timeout_handle'};
}

sub timeout {
    my ($self, @args) = @_;
    my $timeout_handle =
        $self->context->timeout(@args);
    return $timeout_handle;
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

sub _do_safely {
    my ($self, $callback) = @_;
    try {
        $self->timeout_cancel;
        $callback->();
        $self->update;
        if ($self->state eq 'inactive'
            and my $after = $self->after
            ) {
            $self->timeout(
                0, sub { $after->(); });
        }
    }
    catch {
        $self->reset;
        die $_; # propagate any error
    }
    finally {
        $self->after(undef)
            if $self->state eq 'inactive';
        $self->timeout_start
            unless $self->state eq 'inactive';
    };
    return;
}

sub update {
    my ($self) = @_;
    for ($self->state) {
        when ('inactive') { $self->go_inactive; }
        when (/^client_/) { $self->go_client; }
        when (/^server_/) { $self->go_server; }
        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }
    }
    return;
}

sub reset {
    my ($self) = @_;
    $self->state('inactive');
    $self->go_inactive;
    return;
}

sub go_inactive {
    my ($self) = @_;
    $self->request('');
    $self->reply('');
    $self->selection_call('local',  'empty');
    $self->selection_call('remote', 'empty');
    $self->go_server;
    return;
}

# attributes

sub handler {
    my ($self) = @_;
    return $self->{'handler'};
}

sub context {
    my ($self) = @_;
    return $self->{'context'};
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

sub after {
    my ($self, @args) = @_;
    ($self->{'after'}) = @args if @args;
    return $self->{'after'};
}

sub state {
    my ($self, @args) = @_;
    ($self->{'state'}) = @args if @args;
    return $self->{'state'};
}

1;

=head1 NAME - Zircon::Connection

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
