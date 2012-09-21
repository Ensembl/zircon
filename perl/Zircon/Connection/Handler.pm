
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

#  timeout: log a warning

sub zircon_connection_timeout {
    warn "zircon_connection_timeout()\n";
    return;
}

#  debug: log a warning

sub zircon_connection_debug {
    warn "zircon_connection_debug()\n";
    return;
}

# utilities

sub _zircon_connection_callback_undefined {
    my ($self, $callback) = @_;
    return sprintf
        "Zircon connection callback method '%s()' not available from class %s.\n"
        , $callback, ref $self;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
