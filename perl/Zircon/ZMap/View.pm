
package Zircon::ZMap::View;

use strict;
use warnings;

use feature qw( switch );
use Scalar::Util qw( weaken );
use POSIX();

use Zircon::Protocol;

use base qw( Zircon::Protocol::Server );

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\%args);
    return $new
}

sub _init {
    my ($self, $args) = @_;

    my (
        $handler, $context, $app_id, $selection_id,
        $conf_dir, $program, $program_args,
        ) = @{$args}{qw(
        -handler  -context  -app_id  -selection_id
        -conf_dir  -program  -program_args
        )};

    $self->{'handler'} = $handler;
    weaken $self->{'handler'};

    @{$self}{qw( name start end )}=
        @{$args}{qw( -name -start -end )};

    my $protocol = $self->{'protocol'} =
        Zircon::Protocol->new(
            '-context' => $context,
            '-selection_id' => $selection_id,
            '-app_id'  => $app_id,
            '-server'  => $self,
        );
    $program ||= 'zmap';
    my @zmap_command = (
        $program
        , "--conf_dir=${conf_dir}"
        , "--peer-name=${app_id}"
        , "--peer-clipboard=${selection_id}"
        );
    push @zmap_command, @{$program_args} if $program_args;

    warn sprintf "%s\n", join ' ', map { "'$_'" } @zmap_command;

    my $pid = fork;
    defined $pid or die 'fork() failed';
    unless ($pid) {
        exec @zmap_command
            or POSIX::_exit(1);
    }

    return;
}

sub shutdown_clean {
    my ($self, @args) = @_;
    $self->protocol->send_shutdown_clean(@args);
    return;
}

my @sequence_key_list = qw(
    name
    start
    end
    );

sub send_new_view {
    my ($self) = @_;

    my $request =
        [ 'sequence',
          { map { $_ => scalar $self->$_ } @sequence_key_list } ];

    $self->protocol->send_command(
        'new_view', undef, $request, undef);

    return;
}

# protocol server

sub zircon_server_handshake {
    my ($self, @args) = @_;
    my $self_ = $self;
    weaken $self_;
    $self->protocol->connection->after(
        sub {
            defined $self_ or return;
            $self_->send_new_view;
        });
    $self->SUPER::zircon_server_handshake(@args);
    return;
}

sub zircon_server_protocol_command {
    my ($self, $command, $view, $request_body) = @_;

    for ($command) {

        when ('features_loaded') {

            my $request_hash = { };
            for (@{$request_body}) {
                my ($name, $attribute_hash) = @{$_};
                $request_hash->{$name} = $attribute_hash;
            }

            my $status = $request_hash->{'status'}{'value'};
            my $client_message = $request_hash->{'status'}{'message'};
            my @feature_list = split /;/, $request_hash->{'featureset'}{'names'};

            $self->handler->zircon_zmap_view_features_loaded(
                $status, $client_message, @feature_list);

            my $message = "feature list received";

            return $self->protocol->message_ok($message);
        }

        default {
            return $self->SUPER::zircon_server_protocol_command(
                $command, $view, $request_body);
        }

    }

    return; # unreached, quietens perlcritic
}

# attributes

sub protocol {
    my ($self) = @_;
    my $protocol = $self->{'protocol'};
    return $protocol;
}

sub name {
    my ($self) = @_;
    my $name = $self->{'name'};
    return $name;
}

sub start {
    my ($self) = @_;
    my $start = $self->{'start'};
    return $start;
}

sub end {
    my ($self) = @_;
    my $end = $self->{'end'};
    return $end;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
