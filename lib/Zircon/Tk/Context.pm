
package Zircon::Tk::Context;

use strict;
use warnings;

use Carp qw( croak cluck );
use Tk::Xlib;
use Zircon::Tk::Selection;
use base 'Zircon::Trace';
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONTEXT_TRACE';


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
    defined $widget or die 'missing -widget argument';
    $self->{'widget'} = $widget;
    $self->zircon_trace;
    return;
}

# platform
sub platform { return 'Tk'; }

# selections

sub selection_new {
    my ($self, @args) = @_;
    $self->zircon_trace('for (%s)', "@args");
    my $selection =
        Zircon::Tk::Selection->new(
            '-platform' => $self->platform,
            '-widget'   => $self->widget,
            @args);
    return $selection;
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

# waiting

sub waitVariable {
    my ($self, $var) = @_;
    $self->zircon_trace('enter for %s=%s', $var, $$var);
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to waitVariable with destroyed widget";
    $w->waitVariable($var);
    Tk::Exists($w)
        or cluck "Widget $w destroyed during waitVariable";
    $self->zircon_trace('exit with %s=%s', $var, $$var);
    return;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

sub widget_xid {
    my ($self) = @_;
    return $self->widget->id;
}

# other app's windows

# Desperately risk-averse algorithm for "does xwinid exist?"
#
#   on hearing from the window,
#   get the path back to root window
#   unless we already have it
#
#   to check that the window still exists,
#   chase the path from the root window downwards,
#   assuming that the path is still valid
#
#   when window is known to exist (event from it),
#   check that it still exists on the known path,
#   and if it does not, just clear the path (re-parented?)
#
# Last part not implemented - YAGNI
sub window_exists {
    my ($self, $win_id, $does_exist) = @_;

    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to check window_exists with destroyed widget";

    my $path = $self->{_window_exists}{$win_id} ||= [];
    if (!@$path) {
        if (!$does_exist) {
            # If it exists, we don't know where it is
            return 0;
        } else {
            # Get the path of parents back up to root
            my $win = __id2window($win_id);
            while ($win) {
                push @$path, $win;
                ($win) = __xquerytree($w, $win);
            }
            my @id = map { sprintf '0x%X', $$_ } @$path;
            $self->zircon_trace('window path (%s) registered',
                                (join ' <- ', @id));
            return 1;
        }
    } else {
        my @id = map { sprintf '0x%X', $$_ } @$path;
        if ($does_exist) {
            # YAGNI
            return 1;
        } else {
            # Go look for $win_id starting at root
            for (my $i=@$path-1; $i > 0; $i--) {
                my $parent = $path->[$i];
                my $win = $path->[$i-1];
                my (undef, @kid) = __xquerytree($w, $parent);
                if (grep { $$win == $$_ } @kid) {
                    # $win still exists under $parent
$self->zircon_trace('window 0x%X exists under 0x%X', $$win, $$parent);
# Sometimes it fibs.  The child was present, but when we query it - boom!
                } else {
                    # The path has become invalid
                    delete $self->{_window_exists}{$win_id};
                    $self->zircon_trace('window path (%s) now invalid at 0x%X',
                                        (join ' <- ', @id), $$win);
                    return 0; # assume it was not reparented
                }
            }
            $self->zircon_trace('window path (%s) still valid',
                                (join ' <- ', @id));
            return 1;
        }
    }
}

sub __xquerytree {
    my ($w, $win) = @_;
    return try {
        # see e.g. Xlib/tree_demo in perl-tk
        my ($root, $parent);
        my @kid = $w->Display->XQueryTree($win, $root, $parent);
        # try will not protect us when $win does not exist.
        # We cannot reach Tk_CreateErrorHandler from here.
        # Ask for a BadWindow and we are *gone*.
        return ($parent, @kid);
    } catch {
        die "XQueryTree died unexpectedly: $_";
    };
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
        bless $obj, 'Window'; # no critic (Anacode::ProhibitRebless)
        return $obj;
    }
}


# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return sprintf('Z:T:Context: widget=%s', $self->widget->PathName);
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
