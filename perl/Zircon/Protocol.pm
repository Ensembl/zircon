
package Zircon::Protocol;

use strict;
use warnings;

use Scalar::Util qw( weaken );

use Zircon::Connection;
use Zircon::Protocol::Result::Reply;
use Zircon::Protocol::Result::Timeout;

use base qw(
    Zircon::Protocol::Command
    Zircon::Protocol::XML
    Zircon::Connection::Handler
    );

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\%arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;

    $self->{'is_open'} = 1;
    $self->{'request_id'} = 0;

    for (qw( app_id context selection_id server )) {
        my $attribute = $arg_hash->{"-$_"};
        defined $attribute
            or die "missing -$_ parameter";
    }

    @{$self}{qw( app_id server )} =
        @{$arg_hash}{qw( -app_id -server )};
    weaken $self->{'server'};

    my ($context, $selection_id) =
        @{$arg_hash}{qw( -context -selection_id )};
    my $connection = Zircon::Connection->new(
        '-context' => $context,
        '-handler' => $self,
        );
    $self->{'connection'} = $connection;
    $connection->local_selection_id($selection_id);

    return;
}

sub send_handshake {
    my ($self, $remote_selection_id, $callback) = @_;
    $self->connection->remote_selection_id($remote_selection_id);
    $self->send_command(
        'handshake', undef, $callback);
    return;
}

sub send_ping {
    my ($self, $callback) = @_;
    $self->send_command(
        'ping', undef, $callback);
    return;
}

sub send_shutdown_clean {
    my ($self, $callback) = @_;
    $self->send_command(
        'shutdown', undef, 'clean',
        sub {
            my ($result) = @_;
            $self->close if
                $result->isa('Zircon::Protocol::Result::Reply')
                && $result->success;
            $callback->($result) if $callback;
        });
    return;
}

sub send_goodbye_exit {
    my ($self, $callback) = @_;
    $self->send_command(
        'goodbye', undef, 'exit', $callback);
    return;
}

sub send_command {
    my ($self, $command, $view, @args) = @_;
    $self->is_open or die "the connection is closed\n";
    my $command_method = sprintf 'command_request_%s', $command;
    $self->can($command_method)
        or die sprintf "invalid command '%s'", $command;
    my $callback = pop @args;
    $self->callback($callback);
    my $request = $self->$command_method(@args);
    my $request_xml = $self->request_xml($command, $view, $request);
    $self->connection->send($request_xml);
    return;
}

# connection handlers

sub zircon_connection_request {
    my ($self, $request_xml) = @_;
    my ($request_id, $command, $view, $request) =
        @{$self->request_xml_parse($request_xml)};
    my ($reply, %args) = $self->command_request($command, $view, $request);
    $self->connection->after($args{'after'});
    my $reply_xml = $self->reply_xml($request_id, $command, $reply);
    return $reply_xml;
}

sub zircon_connection_reply {
    my ($self, $reply_xml) = @_;
    if (my $callback = $self->callback) {
        my ($request_id,
            $command, $return_code, $reason,
            $view, $reply,
            ) = @{$self->reply_xml_parse($reply_xml)};
        my $success =
            defined $return_code
            && $return_code eq 'ok';
        my $result = Zircon::Protocol::Result::Reply->new(
            '-success' => $success);
        $callback->($result);
        $self->callback(undef);
    }
    else {
        printf "\nZircon client: app_id: '%s': reply\n>>>\n%s\n<<<\n"
            , $self->app_id, $reply_xml;
    }
    return;
}

sub zircon_connection_timeout {
    my ($self) = @_;
    if (my $callback = $self->callback) {
        my $result = Zircon::Protocol::Result::Timeout->new;
        $callback->($result);
        $self->callback(undef);
    }
    else {
        printf
            "Zircon client: app_id: '%s': timeout\n"
            , $self->app_id;
    }
    return;
}

# utilities

sub close {
    my ($self) = @_;
    $self->{'is_open'} = 0;
    return;
}

# attributes

sub app_id {
    my ($self) = @_;
    my $app_id = $self->{'app_id'};
    return $app_id;
}

sub server {
    my ($self) = @_;
    my $server = $self->{'server'};
    return $server;
}

sub connection {
    my ($self) = @_;
    my $connection = $self->{'connection'};
    return $connection;
}

sub is_open {
    my ($self) = @_;
    my $is_open = $self->{'is_open'};
    return $is_open;
}

sub callback {
    my ($self, @args) = @_;
    ($self->{'callback'}) = @args if @args;
    return $self->{'callback'};
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
