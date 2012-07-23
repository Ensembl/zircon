
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

    my ($handler, $context, $conf_dir, $program) =
        @{$args}{qw( -handler -context -conf_dir -program )};

    $self->{'handler'} = $handler;
    weaken $self->{'handler'};

    my $protocol = $self->{'protocol'} =
        Zircon::Protocol->new(
            '-context' => $context,
            '-app_id'  => 'Utterloss',
            '-server'  => $handler,
        );
    my $peer_clipboard =
        $protocol->connection->local_selection_id;
    $program ||= 'zmap';
    my @zmap_command = (
        $program
        , "--conf_dir=${conf_dir}"
        , "--peer-name=ZMap"
        , "--peer-clipboard=${peer_clipboard}"
        );

    printf "%s\n", join ' ', map { "'$_'" } @zmap_command;

    my $pid = fork;
    defined $pid or die 'fork() failed';
    unless ($pid) {
        exec @zmap_command
            or POSIX::_exit(1);
    }

    return;
}

1;
