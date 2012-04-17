
package Zircon::Connection::Handler;

=pod

This class supplies default implementations for all the callbacks that
a connection object may call.  It is recommended (but not required)
that connection handler classes inherit this class.

=cut

use strict;
use warnings;

#  request and reply: these are mandatory so their default
#  implementations raise an error.

sub zircon_connection_request {
    my ($self) = @_;
    die $self->_zircon_connection_callback_undefined(
        'zircon_connection_request');
}

sub zircon_connection_reply {
    my ($self) = @_;
    die $self->_zircon_connection_callback_undefined(
        'zircon_connection_reply');
}

# utilities

sub _zircon_connection_callback_undefined {
    my ($self, $callback) = @_;
    return sprintf
        "Zircon connection callback method '%s()' not available from class %s.\n"
        , $callback, ref $self;
}

1;
