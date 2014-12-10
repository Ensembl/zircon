# Singleton for the ZeroMQ context object, of which there must be only one per process

package Zircon::Context::ZMQ::Ctx;

use strict;
use warnings;

use Scalar::Util qw( weaken refaddr );

use ZMQ::LibZMQ3;

use parent 'Zircon::Trace';
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONTEXT_TRACE';

my $_singleton;

sub new {
    my ($class) = @_;

    if ($_singleton) {
        $class->zircon_trace("returning existing 0MQ context '%x'", $_singleton->ctx);
        return $_singleton;
    } else {
        $class->zircon_trace('creating new 0MQ context');
        my $_ctx = zmq_ctx_new;
        $_ctx or die "zmq_ctx_new failed: $!";
        $class->zircon_trace("new context '%x'", $_ctx);
        $_singleton = bless { _ctx => $_ctx }, $class;
        my $retval = $_singleton;
        weaken $_singleton;
        return $retval;
    }
}

sub ctx {
    my ($self) = @_;
    return $self->{_ctx};
}

# For tests
sub exists {
    return $_singleton && $_singleton->{_ctx};
}

sub zircon_trace_prefix { return 'ZMQ::Ctx' }

DESTROY {
    my ($self) = @_;
    $self->zircon_trace("ctx = '%x'", refaddr $self->ctx // 'undef');
    if (my $_ctx = $self->ctx) {
        $self->zircon_trace('destroying 0MQ context...');
        zmq_ctx_destroy($_ctx);
        undef $self->{_ctx};
        $self->zircon_trace('...destroyed');
    }
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
