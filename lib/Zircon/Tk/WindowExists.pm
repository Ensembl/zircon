package Zircon::Tk::WindowExists;

use strict;
use warnings;

use Try::Tiny;
use POSIX;
use IO::Handle;

sub new {
    my ($pkg) = @_;
    my $new = { };
    bless $new, $pkg;
    return $new;
}

sub query {
    my ($self, $window_id) = @_;
    $self->ensure_open;
    local $SIG{PIPE} = 'IGNORE';
    print { $self->out } "query? $window_id\n";
    my $in = $self->in;
    my $reply = <$in>;
    if ($reply && $reply eq "exists! $window_id\n") {
        return 1;
    } else {
#        warn "pid=$$: We are told window $window_id is gone\n";
# warning for reassurance, after a scary Xlib exit message
# but we muffle the exit message
        return 0;
    }
}

sub in {
    my ($self) = @_;
    return $self->{in}; # child stdout
}

sub out {
    my ($self) = @_;
    return $self->{out}; # child stdin
}

sub pid {
    my ($self) = @_;
    return $self->{pid}; # parent tracks child pid
}

sub ensure_open {
    my ($self) = @_;

    # Use existing child?
    return if defined $self->in && $self->in->opened;
    $self->tidy;

    # Spawn
    my ($q_read, $q_write); # queries to child
    my ($a_read, $a_write); # answers to parent
    (pipe($q_read, $q_write) && pipe($a_read, $a_write))
      or die "pipe failed: $!";
    my $pid = fork();

    if (!defined $pid) {
        die "fork failed: $!";
    } elsif ($pid) { # parent
        $self->{out} = $q_write;
        $self->{in} = $a_read;
        $self->{pid} = $pid;
        $q_write->autoflush(1);

        # Close our unused ends so EOFs arrive
        close $q_read;
        close $a_write;

    } else { # child
        # Redirect the pipes before exec, else they are closed
        my @err;
        try {
            try { untie *STDIN };
            try { untie *STDOUT };
            try { untie *STDERR };

            open STDIN, '<&', $q_read or push @err, "dup STDIN: $!";
            open STDOUT, '>&', $a_write or push @err, "dup STDOUT: $!";

            close $a_read;
            close $q_write;
        } catch {
            # do not propagate errors before (exec || exit)
            push @err, "Redirections failed: $_";
        };

        my $pkg = __PACKAGE__;
        my @cmd = ($^X, "-M$pkg", "-E", "$pkg\->main");
        if (!@err) {
            { exec @cmd };
            push @err, "exec '@cmd' failed: $!";
        }
        warn "$pkg: child pid=$$ failed to start";
        warn "  $_\n" foreach @err;
        try { close STDERR }; # for flush
        POSIX::_exit(127); # avoid DESTROY and END actions
    }
    return; # parent only
}

sub tidy {
    my ($self) = @_;
    my $pid = delete $self->{pid};
    return unless $pid;

    kill INT => $pid; # most likely already dead
    close $self->in;
    close $self->out;
    waitpid $pid, 0;
    return $?;
}

sub DESTROY { # parent only
    my ($self) = @_;
    $self->tidy;
    return;
}

sub main { # child only
    require Tk;
    require Tk::Xlib;

    $| = 1;

    my $pkg = __PACKAGE__;
    my $M = MainWindow->new(-title => $pkg);
    $M->withdraw;

    my $obj = $pkg->new;
    $M->fileevent(\*STDIN, readable => [ $obj, '_do_query', $M ]);
    Tk::MainLoop();
    return 0;
}

# method used in Tk event spec, in child
sub _do_query { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $widget) = @_;

    # Get query from parent, which comes explicitly on STDIN
    my $ln = <STDIN>; ## no critic (InputOutput::ProhibitExplicitStdin)

    if (!defined $ln) {
        # EOF
        $widget->destroy;
        return;
    }
    chomp $ln;
    die "Bad input '$ln'" unless $ln =~ m{^query\? (\S+)$};
    my $win_id = $1;
    my $win = __id2window($win_id);
    my ($root, $parent);

    # Temporary 2>/dev/null
    open my $old_stderr, '>&', \*STDERR
      or warn "Failed dup of STDERR\n";
    open STDERR, '>', '/dev/null'
      or warn "Failed redirect STDERR to nul\n";

    # see e.g. Xlib/tree_demo in perl-tk
    # Ask for a BadWindow and we are *gone*.
    my @kid = $widget->Display->XQueryTree($win, $root, $parent);

    if ($old_stderr) {
        open STDERR, '>&', $old_stderr
          or 1; # we are muted indefinitely
    }
    die "Window $win_id did not exist.  We survived asking?"
      unless defined $root;

    # still here?  cool!
    print "exists! $win_id\n";
    return;
}


sub __id2window {
    my ($id) = @_;
    # hackery to construct object from hexid
    if (ref($id)) {
        # assume it is a Window from Tk::Xlib
        return $id;
    } else {
        $id = hex($id) if $id =~ /^0x/;
        my $obj = \$id;
        # there is no constructor, they come from Tk/Xlib.so
        bless $obj, 'Window'; ## no critic (Anacode::ProhibitRebless)
        return $obj;
    }
}

1;
