
package Zircon::Tk::Selection;

use strict;
use warnings;
use Carp;

use Scalar::Util qw( weaken );

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
        $self->zircon_trace;
        $self->widget->SelectionOwn(
            '-selection' => $self->id,
            '-command' => $self->callback('owner_callback'),
            );
        $self->owns(1);
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
    my $get =
        $self->widget->SelectionGet(
            '-selection' => $self->id);
    $self->zircon_trace("\n%s\n", $get);
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
    $self->zircon_trace;
    my $content = $self->content;
    my $size = (length $content) - $offset;
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
    ($self->{'content'}) = @args if @args;
    return $self->{'content'};
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

# tracing

sub zircon_trace_format {
    my ($self) = @_;
    return ( "id = '%s'", $self->id );
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
