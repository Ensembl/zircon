
package Zircon::ZMap::Core;

#  The transport/protocol independent code to manage ZMap processes.

use strict;
use warnings;

use Carp;
use Scalar::Util qw( weaken refaddr );
use POSIX ();
use Try::Tiny;

use base qw( Zircon::Trace );
our $ZIRCON_TRACE_KEY = 'ZIRCON_ZMAP_TRACE';

my @_list = ( );

sub list {
    my ($pkg) = @_;
    # filter the list because weak references may become undef
    my $list = [ grep { defined } @_list ];
    return $list;
}

my $_string_zmap_hash = { };

sub from_string {
    my ($pkg, $string) = @_;
    my $zmap = $_string_zmap_hash->{$string};
    return $zmap;
}

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = {
        '_program' => 'zmap',
    };
    bless($new, $pkg);
    push @_list, $new;
    weaken $_list[-1];
    $_string_zmap_hash->{"$new"} = $new;
    weaken $_string_zmap_hash->{"$new"};
    $new->_init(\%arg_hash);
    $new->launch_zmap;
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;
    my $program = $arg_hash->{'-program'};
    $self->{'_program'} = $program if $program;
    $self->{'_arg_list'} = [@{
        $arg_hash->{'-arg_list'} || []
    }]; # copy now because list is modified by subclass _init
    $self->{'_id_view_hash'} = { };
    $self->{'_view_list'} = [ ];
    return;
}

sub launch_zmap {
    my ($self) = @_;

    my @e = $self->zmap_command;
    warn "Running: @e\n";
    my $pid = fork;
    confess "Error: couldn't fork()\n" unless defined $pid;
    if ($pid) { # parent
        warn "Started $e[0], pid $pid\n";
        return $pid;
    }
    { exec @e; }
    # DUP: EditWindow::PfamWindow::_launch_belvu
    # DUP: Hum::Ace::LocalServer
    try {
        warn "exec '@e' failed: $!";
        close STDERR; # _exit does not flush
        close STDOUT;
    }; # no catch, just be sure to _exit
    POSIX::_exit(127); # avoid triggering DESTROY

    return; # unreached, quietens perlcritic
}

sub zmap_command {
    my ($self) = @_;
    my @zmap_command = ( $self->program );
    my $arg_list = $self->arg_list;
    push @zmap_command, @{$arg_list} if $arg_list;
    return @zmap_command;
}

sub add_view {
    my ($self, $id, $view) = @_;
    $self->id_view_hash->{$id} = $view;
    weaken $self->id_view_hash->{$id};
    push @{$self->_view_list}, $view;
    weaken $self->_view_list->[-1];
    return;
}

# waiting

sub waitVariable {
    my ($self, $var) = @_;
    die sprintf
        "waitVariable() is not implemented in %s, "
        . "derived classes must implement it"
        , __PACKAGE__;
}

# attributes

sub program {
    my ($self) = @_;
    my $program = $self->{'_program'};
    return $program;
}

sub arg_list {
    my ($self) = @_;
    my $arg_list = $self->{'_arg_list'};
    return $arg_list;
}

sub id_view_hash {
    my ($self) = @_;
    my $id_view_hash = $self->{'_id_view_hash'};
    return $id_view_hash;
}

sub view_list {
    my ($self) = @_;
    # filter the list because weak references may become undef
    my $view_list = [ grep { defined } @{$self->_view_list} ];
    return $view_list;
}

sub _view_list {
    my ($self) = @_;
    my $view_list = $self->{'_view_list'};
    return $view_list;
}


# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return 'Z:ZMap';
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

