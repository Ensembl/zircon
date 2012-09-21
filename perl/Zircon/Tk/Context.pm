
package Zircon::Tk::Context;

use strict;
use warnings;

use Zircon::Tk::Selection;

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
    return;
}

# selections

sub selection_new {
    my ($self, @args) = @_;
    my $selection =
      Zircon::Tk::Selection->new(
          '-widget' => $self->widget, @args);
    return $selection;
}

# timeouts

sub timeout {
    my ($self, @args) = @_;
    my $timeout_handle =
        $self->widget->after(@args);
    return $timeout_handle;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
