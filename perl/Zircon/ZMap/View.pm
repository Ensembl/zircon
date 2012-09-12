
package Zircon::ZMap::View;

use strict;
use warnings;

use Scalar::Util qw( weaken );
use POSIX();

use Zircon::Protocol;

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\%args);
    return $new
}

sub _init {
    my ($self, $args) = @_;

    my ($handler, $context, $selection_id, $conf_dir, $program, $program_args) =
        @{$args}{qw( -handler -context -selection_id -conf_dir -program -program_args )};

    $self->{'handler'} = $handler;
    weaken $self->{'handler'};

    my $protocol = $self->{'protocol'} =
        Zircon::Protocol->new(
            '-context' => $context,
            '-selection_id' => $selection_id,
            '-app_id'  => 'Utterloss',
            '-server'  => $handler,
        );
    $program ||= 'zmap';
    my @zmap_command = (
        $program
        , "--conf_dir=${conf_dir}"
        , "--peer-name=utterloss"
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

# attributes

sub protocol {
    my ($self) = @_;
    my $protocol = $self->{'protocol'};
    return $protocol;
}

1;
