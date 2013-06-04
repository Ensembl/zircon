package ConnHandler;
use strict;
use warnings;

=head1 NAME

ConnHandler - a minimal Handler

=head1 DESCRIPTION

A small handler for L<Zircon::Connection>.

It needs the underlying widget to implement C<state_bump> and
C<handle_request> methods.

=head1 AUTHOR

Matthew Astley mca@sanger.ac.uk

=cut


sub new {
    my ($pkg) = @_;
    return bless { }, __PACKAGE__;
}

sub zconn {
    my ($self, @arg) = @_;
    ($self->{zconn}) = @arg if @arg;
    return $self->{zconn} or
      die "Need zconn set now";
}

sub zircon_connection_timeout {
    my ($self, @info) = @_;
    $self->widget->state_bump(zircon_connection_timeout => @info);
    $self->widget->destroy;
    return;
}

sub zircon_connection_request {
    my ($self, $request) = @_;
    $self->widget->state_bump(requested => $request);
    my $reply = $self->widget->handle_request($request);
    $self->zconn->after(sub { $self->zcreq_done($reply) });
    return $reply;
}

sub zircon_connection_reply {
    my ($self, $reply) = @_;
    $self->widget->state_bump(reply => $reply);
    return;
}

sub zcreq_done {
    my ($self, $reply) = @_;
    $self->widget->state_bump(replied => $reply);
    return;
}

sub widget {
    my ($self) = @_;
    return $self->zconn->context->widget;
}


1;
