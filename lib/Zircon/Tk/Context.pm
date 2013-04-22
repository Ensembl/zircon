
package Zircon::Tk::Context;

use strict;
use warnings;

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
    my $timeout_handle =
        $self->widget->after(@args);
    $self->zircon_trace('configured (%d millisec)', $args[0]);
    return $timeout_handle;
}

# waiting

sub waitVariable {
    my ($self, $var) = @_;
    $self->zircon_trace('enter for %s=%s', $var, $$var);
    $self->widget->waitVariable($var);
    $self->zircon_trace('exit with %s=%s', $var, $$var);
    return;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return sprintf('Z:T:Context: widget=%s', $self->widget->PathName);
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
