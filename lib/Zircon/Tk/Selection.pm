
package Zircon::Tk::Selection;

use strict;
use warnings;
use Carp qw( croak confess cluck );

use Scalar::Util qw( weaken );
use Try::Tiny;
use File::Slurp qw( slurp );
use Time::HiRes qw( usleep );

use Zircon::Tk::Context;

use base qw( Zircon::Trace );
our $ZIRCON_TRACE_KEY = 'ZIRCON_SELECTION_TRACE';
our $DELAY_FILE_KEY = 'ZIRCON_DEBUG_DELAY';
our $OWN_SAFETY_TIMEOUT = 10e3; # 10 sec, arbitrarily chosen

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

my @mandatory_args = qw(
    name
    platform
    id
    handler
    widget
    );

my $optional_args = {
    'handler_data' => undef,
};

my @weak_args = qw(
    handler
    );

sub init {
    my ($self, $args) = @_;

    for my $key (@mandatory_args) {
        defined ( $self->{$key} = $args->{"-${key}"} )
            or croak "missing -${key} argument";
    }
    while (my ($key, $default) = each %{$optional_args}) {
        my $value = $args->{"-${key}"};
        defined $value or $value = $default;
        $self->{$key} = $value;
    }
    for my $key (@weak_args) {
        weaken $self->{$key};
    }

    Tk::Exists($self->widget)
        or croak "Attempt to construct with invalid widget";

    $self->empty;
    $self->owns(0);

    $self->widget->SelectionHandle(
        -selection => $self->id,
        $self->callback('selection_callback'));

    return;
}


# Cause SelectionOwn to happen.  Call returns [nothing] before the
# SelectionOwn message has been sent to Xserver.
#
# Calling this method again before the previous call has taken effect
# is likely to be ineffective and will generate warnings, but that
# should not affect what the Xserver ultimately sees.
sub own {
    my ($self) = @_;
    if (! $self->owns) {
        $self->debug_delay('own');
        $self->zircon_trace('provoking timestamped event');
        $self->_own_provoke;

        # A little early, but the state represents the intention
        $self->owns(1);
    }
    return;
}

# Contortions to let us deliver SelectionOwn request in the execution
# context of an incoming X11 event that has a recent timestamp;
# without adding new ways to block indefinitely.
#
#
# Detail: in perl-tk 804.029 a04d1f0dca91ad8ffa055bf009ff6270c68ef617
# SelectionOwn behaves as specified in ICCCM, ie. the timestamp given
# is taken from the most recent user interaction (if we can find one,
# else CurrentTime==0).
#
# Often there is no user context, but if we are in a waitWindow or
# similar which was triggered by a KeyPress or ButtonPress then THAT
# time is used.
#
# The second time we Own using the same timestamp, the XServer decides
# the ownership is stale and ignores it.  Zircon times out.
#
# This code gives Tk_OwnSelection's call to TkCurrentTime an execution
# context for a more recent event.

my @event_info;
{
    no warnings qw(qw);
    @event_info = qw( # t E d );
}

sub _own_provoke {
    my ($self) = @_;

    my $w = $self->widget;
    my $id = $self->id;

    Tk::Exists($w)
        or croak "Attempt to own selection $id with destroyed widget";

    # When timer is set, indicates that we are already waiting for
    # _own_timestamped to happen
    if (defined $self->{'_own_timer'}) {
        warn "SelectionOwn for previous ->own($id) call didn't happen yet - timer still running";
    } else {
        # Set the timer to inform us when things are not happening.
        $self->{'_own_timer'} = $w->after
          ($OWN_SAFETY_TIMEOUT,
           sub {
               warn "Requested SelectionOwn($id) has not happened after ${OWN_SAFETY_TIMEOUT}ms";
               delete $self->{'_own_timer'};
           });
    }

    try { $w->property('delete', 'Zircon_Own') }; # belt&braces

    # Can only have one callback bound to widget, but we probably have
    # two selections to manage.  Re-bind each time we need it.
    $w->bind('<Property>' => [ $self, '_own_timestamped',
                               map { Tk::Ev($_) } @event_info ]);

    $w->property('set', 'Zircon_Own', "STRING", 8, $self->id);

    # It should happen "later".  Return now.
    return;
}

# This callback runs in the context of the PropertyNotify, which has a
# recent timestamp.  The timestamp is re-used by pTk for SelectionOwn.
sub _own_timestamped {
    my ($self, @arg) = @_;
    my $id = $self->id;

    Zircon::Tk::Context->warn_if_tangled;

    my $w = $self->widget;
    if (!Tk::Exists($w)) {
        # I suspect it can't happen.  While trying to write an
        # automated test for it, the result was sometimes a segfault.
        warn "PropertyNotify($id) on destroyed window?!";
        return;
        # there is nothing useful we can do without the widget
    }

    my $propkey = $arg[3];
    my $propval = try { $w->property('get', $propkey) } catch { "absent: $_" };
    $propval =~ s{(\x00|\n)$}{}; # probably comes back NUL-terminated

    # Tk:Ev(d) gives property name, but use property value instead
    # because documentation doesn't promise data for PropertyNotify
    $self->zircon_trace('PropertyNotify(#=%s t=%s E=%s d=%s) => %s',
                        @arg, $propval);

    if ($propkey ne 'Zircon_Own' || $propval ne $id) {
        # event is not for us
        return;
    } elsif ($self->{'_own_timer'}) {
        $self->{'_own_timer'}->cancel;
        delete $self->{'_own_timer'};
    } else {
        warn "_own_timestamped($id): happens late";
    }

    $w->SelectionOwn
      ('-selection' => $id,
       '-command' => $self->callback('owner_callback'));
    $w->bind('<Property>' => ''); # cancel
    try { $w->property('delete', 'Zircon_Own') }; # ready for next

    return;
}

sub clear {
    my ($self) = @_;
    $self->zircon_trace($self->owns ? 'have it - will clear' : 'not mine - nop');
    if ($self->owns) {
        my $w = $self->widget;
        Tk::Exists($w)
            or croak "Attempt to clear selection with destroyed widget";
        $self->debug_delay('clear');
        $self->widget->SelectionOwn(
            '-selection' => $self->id);
        $self->widget->SelectionClear(
            '-selection' => $self->id);
        $self->owns(0);
    }
    return;
}

# Error when selection is not present (i.e. cleared)
# which is wrapped by Z:C->_do_safely
sub get {
    my ($self) = @_;
    $self->zircon_trace('start');
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to get selection with destroyed widget";
    Zircon::Tk::Context->warn_if_tangled; # SelectionGet contains an event loop, to emulate a synchronous call
    $self->debug_delay('get');
    my $get = $w->SelectionGet(
            '-selection' => $self->id);
    $self->zircon_trace("result:\n%s\n", $get);
    return $get;
}

sub owner_callback {
    my ($self) = @_;
    $self->zircon_trace;
    $self->owns(0);
    $self->debug_delay('lost');
    Zircon::Tk::Context->warn_if_tangled; # central callback point for incoming "selection taken"
    $self->handler->selection_owner_callback(
        $self->handler_data);
    return;
}

sub selection_callback {
    my ($self, $offset, $bytes) = @_;
    my $content = $self->content;
    my $size = (length $content) - $offset;
    $self->zircon_trace("Get for [$offset,$bytes) of $size bytes remaining");
    if ($size <= $bytes) {
        # peer has read the content
        $self->debug_delay('taken');
        $self->taken(1);
    }
    return
        $size < $bytes
        ? substr $content, $offset
        : substr $content, $offset, $bytes
        ;
}

sub empty {
    my ($self) = @_;
    $self->content('');
    return;
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

sub owns {
    my ($self, @args) = @_;
    ($self->{'owns'}) = @args if @args;
    return $self->{'owns'};
}

sub content {
    my ($self, @args) = @_;
    if (@args) {
        $self->taken(0);
        ($self->{'content'}) = @args;
    }
    return $self->{'content'};
}

sub taken {
    my ($self, @args) = @_;
    ($self->{'taken'}) = @args if @args;
    $self->zircon_trace('taken:=%s', @args) if @args;
    return $self->{'taken'};
}

sub name {
    my ($self) = @_;
    my $name = $self->{'name'};
    return $name;
}

sub platform {
    my ($self) = @_;
    my $platform = $self->{'platform'};
    return $platform;
}

sub id {
    my ($self) = @_;
    my $id = $self->{'id'};
    return $id;
}

sub handler {
    my ($self) = @_;
    my $handler = $self->{'handler'};
    return $handler;
}

sub handler_data {
    my ($self) = @_;
    my $handler_data = $self->{'handler_data'};
    return $handler_data;
}

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

# destructor

sub DESTROY {
    my ($self) = @_;
    $self->zircon_trace;
    return;
}

# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return sprintf "selection: %s: id = '%s'", $self->name, $self->id;
}

sub debug_delay {
    my ($self, $type) = @_;
    my $fn = $ENV{$DELAY_FILE_KEY};
    return unless $fn && -f $fn;
    $type .= " ".$self->name;
    foreach my $ln (slurp($fn)) {
        chomp $ln;
        my ($min, $max, $pat) = split / /, $ln, 3;
        next unless defined $pat;
        next unless $type =~ /$pat/;
        my $delay = rand($max - $min) + $min; # millisec
        $self->zircon_trace(q{Sleeping (%d..%d) => %dms for '%s' =~ %s},
                            $min, $max, $delay, $type, $pat);
        usleep($delay * 1000);
    }
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
