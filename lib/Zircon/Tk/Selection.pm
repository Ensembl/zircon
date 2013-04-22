
package Zircon::Tk::Selection;

use strict;
use warnings;
use Carp;

use Scalar::Util qw( weaken );
use Try::Tiny;

use base qw( Zircon::Trace );
our $ZIRCON_TRACE_KEY = 'ZIRCON_SELECTION_TRACE';

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

    $self->empty;
    $self->owns(0);

    $self->widget->SelectionHandle(
        -selection => $self->id,
        $self->callback('selection_callback'));

    return;
}

sub own {
    my ($self) = @_;
    if (! $self->owns) {
        $self->zircon_trace('provoking timestamped event');
        $self->_own_provoke;
        $self->zircon_trace('did SelectionOwn');

        # check we got it - does not notice if the XServer binned our
        # ownership due e.g. to timestamp staleness
        my $owner = $self->widget->SelectionOwner('-selection' => $self->id);
        my $name = defined $owner ? $owner->PathName : 'external';
        warn 'SelectionOwn('.($self->id).") failed, owner=$name; collision?\n"
          unless $owner == $self->widget;

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
sub _own_provoke {
    my ($self) = @_;

    my $V = \$self->{'_own_var'};
    # absent=unused, 0 = waiting, 1 = timeout, 2 = complete

    my $w = $self->widget;

    if (!defined $$V or 2 == $$V) {
        # unused or previous call complete - continue
        $$V = 0;
    } else {
        confess "recursive ->own call? _own_var=$$V";
        # May be caused by: own dies, catch in Zircon::Connection
        # _do_safely, which issues a reset, which calls ->own again.
    }

    try { $w->property('delete', 'Zircon_Own') }; # belt&braces
    my $after = $w->after
      (10e3, # 10 sec timeout is an arbitrarily chosen safety feature
       sub { $$V = 1; warn "_own_provoke: timeout!"; });

    # Can only have one callback bound to widget, but we probably have
    # two selections to manage.  Re-bind each time we need it.
    $w->bind('<Property>' => [ $self, '_own_timestamped',
                               map { Tk::Ev($_) } qw( # t E d ) ]);

    $w->property('set', 'Zircon_Own', "STRING", 8, $self->id);
    $w->waitVariable($V);
    $after->cancel;
    $w->bind('<Property>' => ''); # cancel
    try { $w->property('delete', 'Zircon_Own') }; # ready for next

    if (2 == $$V) {
        # leave $$V==2 for next time
        return 1;
    } else {
        my $id = $self->id;
        $$V = 2; # reset for next time
        die "Failed to Own selection $id";
    }
}

# This callback runs in the context of the PropertyNotify, which has a
# recent timestamp.  The timestamp is re-used by pTk for SelectionOwn.
sub _own_timestamped {
    my ($self, @arg) = @_;

    my $propval = try { $self->widget->property('get', 'Zircon_Own') } catch { "absent: $_" };
    $propval =~ s{\x00}{}; # probably comes back NUL-terminated

    # Tk:Ev(d) gives property name, but use property value instead
    # because documentation doesn't promise data for PropertyNotify
    $self->zircon_trace('PropertyNotify(#=%s t=%s E=%s d=%s) => %s', @arg, $propval);
    if ($propval eq $self->id) {
        $self->widget->SelectionOwn
          ('-selection' => $self->id,
           '-command' => $self->callback('owner_callback'));
        $self->{'_own_var'} = 2;
    }

    return;
}

sub clear {
    my ($self) = @_;
    if ($self->owns) {
        $self->widget->SelectionOwn(
            '-selection' => $self->id);
        $self->widget->SelectionClear(
            '-selection' => $self->id);
        $self->owns(0);
    }
    return;
}

sub get {
    my ($self) = @_;
    $self->zircon_trace('start');
    my $get =
        $self->widget->SelectionGet(
            '-selection' => $self->id);
    $self->zircon_trace("result:\n%s\n", $get);
    return $get;
}

sub owner_callback {
    my ($self) = @_;
    $self->zircon_trace;
    $self->owns(0);
    $self->handler->selection_owner_callback(
        $self->handler_data);
    return;
}

sub selection_callback {
    my ($self, $offset, $bytes) = @_;
    my $content = $self->content;
    my $size = (length $content) - $offset;
    $self->zircon_trace("Get for [$offset,$bytes) of $size bytes remaining");
    $self->taken(1) if $size <= $bytes; # peer has read the content
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

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
