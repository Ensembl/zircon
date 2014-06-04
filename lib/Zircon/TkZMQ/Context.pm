
package Zircon::TkZMQ::Context;

use strict;
use warnings;

use feature 'state';

use Carp qw( croak cluck );
use Errno qw(EAGAIN ENODATA);
use Readonly;
use Scalar::Util qw( weaken refaddr );
use Time::HiRes qw( gettimeofday );

use ZMQ::LibZMQ3;
use ZMQ::Constants qw(ZMQ_REP ZMQ_REQ ZMQ_LAST_ENDPOINT ZMQ_POLLIN ZMQ_FD ZMQ_DONTWAIT ZMQ_SNDMORE ZMQ_LINGER EFSM);

use base 'Zircon::Trace';
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONTEXT_TRACE';

Readonly my $ZMQ_DEFAULT_ENDPOINT => 'tcp://127.0.0.1:*';

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\%args);
    return $new;
}

sub _init {
    my ($self, $args) = @_;
    $self->{'waitVariable_hash'} = { };
    my $widget = $args->{'-widget'};
    defined $widget or die 'missing -widget argument';
    $self->{'widget'} = $widget;
    $self->zircon_trace;
    return;
}

sub set_connection_params {
    my ($self, %args) = @_;
    while (my ($key, $value) = each %args) {
        $self->$key($value) if $self->can($key);
    }
    return;
}

sub transport_init {
    my ($self, $request_callback, $after_callback) = @_;
    $self->zircon_trace;

    $self->_request_callback($request_callback);
    $self->_after_request_callback($after_callback);

    my $_zmq_context = zmq_ctx_new;
    $_zmq_context or die "zmq_ctx_new failed: $!";
    $self->_zmq_context($_zmq_context);

    my $responder = zmq_socket($_zmq_context, ZMQ_REP);
    $responder or die "failed to get ZMQ_REP socket: $!";

    my $local_endpoint = $self->local_endpoint;
    my $rv = zmq_bind($responder, $self->local_endpoint);
    $rv and die "failed to bind responder socket to '$local_endpoint': $!";
    $self->_zmq_responder($responder);

    $local_endpoint = zmq_getsockopt($responder, ZMQ_LAST_ENDPOINT);
    $local_endpoint =~ s/\0$//; # strip trailing null, if any.
    $local_endpoint or die "failed to get actual endpoint: $!";
    $self->local_endpoint($local_endpoint);
    $self->zircon_trace("local_endpoint: '%s'", $local_endpoint);

    my $fh = zmq_getsockopt($responder, ZMQ_FD);
    $fh or die "failed to get socket fd: $!";
    open my $dup_fh, '<&', $fh or die "failed to dup socket fd: $!";

    $self->widget->fileevent(
        $dup_fh, 'readable',
        sub { return $self->_server_callback; },
        );

    return;
}

sub _send_msg {
    my ($self, $msg, $socket, $flags) = @_;

    my $error;
    my $exp = length $msg;

    my $rv = zmq_msg_send($msg, $socket, $flags || 0);
    if ($rv < 0) {
        my $zerr = zmq_strerror($!);
        $error = "zmq_msg_send failed: '$zerr'";
    }
    elsif ($rv != $exp) {
        $error = "zmq_msg_send length mismatch, sent $rv, should have been $exp";
    }
    # else okay

    return $error;
}

sub _recv_msg {
    my ($self, $socket, $flags) = @_;

    state $msg = zmq_msg_init;

    my $rv = zmq_msg_recv($msg, $socket, $flags);
    if ($rv < 0) {
        my $zerr = zmq_strerror($!);
        return (undef, $!, "zmq_recv_msg failed: '$zerr'");
    }

    my $payload = zmq_msg_data($msg);
    unless (defined $payload) {
        return (undef, ENODATA, "_recv_msg: error retrieving data");
    }

    return ($payload, 0, undef);
}

sub _get_request {
    my ($self) = @_;

    $self->zircon_trace;

    $self->_request_header(undef);
    $self->_request_body(undef);

    my ($header, $request, $errno, $error);
    my $responder = $self->_zmq_responder;

    ($header, $errno, $error) = $self->_recv_msg($responder, ZMQ_DONTWAIT);
    unless (defined $header) {
        if ($errno == EAGAIN or $errno == EFSM) {
            # nothing to do for now
            return;
        } else {
            return "_recv_msg(header) error: '$error'";
        }
    }
    $self->zircon_trace("header: '%s'", $header);

    ($request, $errno, $error) = $self->_recv_msg($responder, ZMQ_DONTWAIT);
    unless (defined $request) {
        if ($errno == EAGAIN) { # we should not get EFSM here
            return "request body not there";
        } else {
            return "_recv_msg(body) error: '$error'";
        }
    }
    $self->zircon_trace("request: '%s'", $request);

    $self->_request_header($header);
    $self->_request_body($request);

    return;
}

sub _server_callback {
    my ($self) = @_;

    $self->zircon_trace('start');

  ZMQ: while (1) {

      my $error = $self->_get_request;
      if ($error) {
          warn "_get_request: $error";
          last ZMQ;
      }
      unless ($self->_request_body) {
          $self->zircon_trace('EAGAIN');
          last ZMQ;
      }

      $error = $self->_process_server_request;
      if ($error) {
          warn "Zircon::TkZMQ::Context::_server_callback: $error";
          return;
      }
  }

    $self->_after_request_callback->() if $self->_after_request_callback;
    $self->zircon_trace('done with 0MQ for this event');
    return;
}

sub _process_server_request {
    my ($self, $collision_result) = @_;

    $self->zircon_trace('start (collision: %s)', $collision_result // 'none');

    my $reply = $self->_request_callback->($self->_request_body, $self->_parse_header, $collision_result);
    $self->zircon_trace("reply:   '%s'", $reply // '<undef>');

    if (my $e = $self->_send_msg($reply // '', $self->_zmq_responder)) {
        return "_send_msg failed: $e";
    }

    $self->zircon_trace('reply sent');
    return;
}

# platform
sub platform { return 'ZMQ'; }

sub _collision_handler {
    my ($self, $my_sec, $my_usec) = @_;

    $self->zircon_trace("collision detected!");

    my $error = $self->_get_request;
    if ($error) {
        warn "_get_request: $error";
        return;
    }

    my $h = $self->_parse_header;
    my $cmp = ($my_sec               <=> $h->{clock_sec}
               ||
               $my_usec              <=> $h->{clock_usec}
               ||
               $self->local_endpoint cmp $self->remote_endpoint);
    if ($cmp < 0) {
        $self->zircon_trace("collision WIN");
        $self->_collision_state('WIN');
    } else {
        $self->zircon_trace("collision LOSE");
        $self->_collision_state('LOSE');
    }
    return;
}

sub send {
    my ($self, $request, $reply_ref, $request_id) = @_;

    # Largely for the benefit of exists.t
    die "send attempted but no widget" unless Tk::Exists($self->widget);

    my $error = 'unset';
    my $zerr;

    my ($sec, $usec) = gettimeofday;
    my $header = {
        request_id => $request_id,
        clock_sec  => $sec,
        clock_usec => $usec,
    };

    my $responder = $self->_zmq_responder;

    $self->_collision_state('clear');

    my $attempt = 0;
  RETRY: foreach my $timeout_interval ( $self->timeout_list ) {

      $attempt++;

      $zerr = undef;
      my $requester = $self->_get_zmq_requester; # must be in retry loop as may change

      $header->{request_attempt} = $attempt;
      my $s_header = $self->_format_header($header);
      $self->zircon_trace("header '%s'", $s_header);

      if (my $e = $self->_send_msg($s_header, $requester, ZMQ_SNDMORE)) {
          $error = "$e (header)";
          next RETRY;
      }
      $self->zircon_trace('header, attempt %d, interval %d', $attempt, $timeout_interval);

      if (my $e = $self->_send_msg($request, $requester)) {
          $error = "$e (body)";
          next RETRY;
      }
      $self->zircon_trace('body, attempt %d', $attempt);

      my $reply_msg;

    POLL: while (1) {

        my %client_reply_pollitem = (
            socket  => $requester,
            events  => ZMQ_POLLIN,
            callback => sub {
                $reply_msg = zmq_recvmsg($requester);
                $reply_msg or warn "Zircon::TkZMQ::Context::send: zmq_recvmsg failed: $!";
                return;
            },
            );
        my %server_request_pollitem = (
            socket  => $responder,
            events  => ZMQ_POLLIN,
            callback => sub { return $self->_collision_handler($sec, $usec); },
            );

        $self->zircon_trace('waiting for reply');
        my @prv = zmq_poll([ \%client_reply_pollitem, \%server_request_pollitem ], $timeout_interval);

        unless (@prv) {
            $zerr = zmq_strerror($!);
            $error = "zmq_poll failed";
            next RETRY;
        }

        unless ($prv[0] or $prv[1]) {
            if ($! == EAGAIN) {
                $self->zircon_trace('timeout awaiting reply');
                $error = 'zmq_poll timeout';
                next RETRY;
            } else {
                $zerr = zmq_strerror($!);
                $error = 'zmq_poll error';
                next RETRY;
            }
        }

        $self->zircon_trace('zmq_poll: reply: %d, server: %d', @prv[0..1]);
        last POLL if $prv[0];   # got a reply

        # Must have been a collision
        if ($self->_collision_state eq 'LOSE') {
            $self->_process_server_request('LOSE');
            # FIXME: reset retries
        }

        redo POLL; # do we need to decouple poll 1?

    } # POLL

      # Should have something now :-)
      my ($retval, $collision_result);

      if ($reply_msg) {
          $$reply_ref = zmq_msg_data($reply_msg);
          $retval = length($$reply_ref); # DANGER what if length is zero? Shouldn't happen with our protocol.
      } else {
          warn "no reply";
          $retval = 0;
      }

      my $cs = $self->_collision_state;
      if ($cs eq 'WIN') {
          $self->zircon_trace("collision win - deferred service");
          $collision_result = sub { return $self->_process_server_request('WIN'); };
      } elsif ($cs eq 'LOSE') {
          $collision_result = 'LOSE';
      } elsif ($cs ne 'clear') {
          warn "Unexpected collision_state '$cs'";
      }

      return ($retval, $collision_result);

  } continue { # RETRY
      $error = "$error: '$zerr'" if $zerr;
      warn $error;
      $self->_destroy_zmq_requester;
  }

    warn "retries exhausted";
    return -1;
}

sub _format_header {
    my ($self, $header) = @_;
    return sprintf('%d/%d %d,%d', @{$header}{qw( request_id request_attempt clock_sec clock_usec )});
}

sub _parse_header {
    my ($self) = @_;
    my $header = $self->_request_header;
    return unless $header;
    my ($seq, $ts) = split(' ', $header);
    return unless $seq and $ts;
    my ($id, $attempt) = split('/', $seq);
    my ($sec, $usec) = split(',', $ts);
    return {
        request_id      => $id,
        request_attempt => $attempt,
        clock_sec       => $sec,
        clock_usec      => $usec,
    };
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
    $self->waitVariable_hash->{$var} = $var;
    weaken $self->waitVariable_hash->{$var};
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to waitVariable with destroyed widget";

    $self->zircon_trace('startWAIT(0x%x) for %s=%s', refaddr($self), $var, $$var);
    $w->waitVariable($var); # traced
    $self->zircon_trace('stopWAIT(0x%x) with %s=%s', refaddr($self), $var, $$var);
    Tk::Exists($w)
        or cluck "Widget $w destroyed during waitVariable";
    return;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

# FIXME: see ensembl-otter:SpeciesListWindow.
# rather than expose this, we should offer a cleanup method.
#
sub waitVariable_hash {
    my ($self) = @_;
    my $waitVariable_hash = $self->{'waitVariable_hash'};
    return $waitVariable_hash;
}

sub _request_header {
    my ($self, @args) = @_;
    ($self->{'_request_header'}) = @args if @args;
    my $_request_header = $self->{'_request_header'};
    return $_request_header;
}

sub _request_body {
    my ($self, @args) = @_;
    ($self->{'_request_body'}) = @args if @args;
    my $_request_body = $self->{'_request_body'};
    return $_request_body;
}

sub _request_callback {
    my ($self, @args) = @_;
    ($self->{'_request_callback'}) = @args if @args;
    my $_request_callback = $self->{'_request_callback'};
    return $_request_callback;
}

sub _after_request_callback {
    my ($self, @args) = @_;
    ($self->{'_after_request_callback'}) = @args if @args;
    my $_after_request_callback = $self->{'_after_request_callback'};
    return $_after_request_callback;
}

sub _collision_state {
    my ($self, @args) = @_;
    ($self->{'_collision_state'}) = @args if @args;
    my $_collision_state = $self->{'_collision_state'};
    return $_collision_state;
}

# ZMQ attribs

sub _zmq_context {
    my ($self, @args) = @_;
    ($self->{'_zmq_context'}) = @args if @args;
    my $_zmq_context = $self->{'_zmq_context'};
    return $_zmq_context;
}

sub _zmq_responder {
    my ($self, @args) = @_;
    ($self->{'_zmq_responder'}) = @args if @args;
    my $_zmq_responder = $self->{'_zmq_responder'};
    return $_zmq_responder;
}

sub _zmq_requester {
    my ($self, @args) = @_;
    ($self->{'_zmq_requester'}) = @args if @args;
    my $_zmq_requester = $self->{'_zmq_requester'};
    return $_zmq_requester;
}

sub _get_zmq_requester {
    my ($self) = @_;

    # if we already have a working socket, use that...
    my $_zmq_requester = $self->_zmq_requester;
    return $_zmq_requester if $_zmq_requester;

    # ...otherwise we need a new one.

    $_zmq_requester = zmq_socket($self->_zmq_context, ZMQ_REQ);
    $_zmq_requester or die "failed to get ZMQ_REQ socket: $!";

    zmq_setsockopt($_zmq_requester, ZMQ_LINGER, 0); # so we can exit without hanging

    my $remote = $self->remote_endpoint;
    $remote or die "remote_endpoint not set";

    my $rv = zmq_connect($_zmq_requester, $remote);
    $rv and die "failed to connect requester socket to '$remote': $!";
    $self->zircon_trace("requester connected to '%s'", $remote);

    # save it for later, and return it.
    return $self->_zmq_requester($_zmq_requester);
}

sub _destroy_zmq_requester {
    my ($self) = @_;
    my $_zmq_requester = $self->_zmq_requester;
    $_zmq_requester or return;

    $self->zircon_trace('destroying ZMQ_REQ socket');
    zmq_close($_zmq_requester);

    # get rid of the saved socket, so that we create a fresh one next time.
    $self->{'_zmq_requester'} = undef;
    return;
}

sub local_endpoint {
    my ($self, @args) = @_;
    ($self->{'local_endpoint'}) = @args if @args;
    my $local_endpoint = $self->{'local_endpoint'} ||= $ZMQ_DEFAULT_ENDPOINT;
    return $local_endpoint;
}

sub remote_endpoint {
    my ($self, @args) = @_;
    ($self->{'remote_endpoint'}) = @args if @args;
    my $remote_endpoint = $self->{'remote_endpoint'};
    return $remote_endpoint;
}

sub timeout_list {
    my ($self, @args) = @_;
    if (@args) {
        my $listref = (scalar(@args) == 1 and ref($args[0]) eq 'ARRAY') ? $args[0] : [ @args ];
        $self->{'timeout_list'} = $listref;
    }
    my $timeout_list = $self->{'timeout_list'} || [];
    return @$timeout_list;
}

# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    my $w = $self->widget;
    my $path = Tk::Exists($w) ? $w->PathName : '(destroyed)';
    return sprintf('Z:T:Context: widget=%s', $path);
}

sub disconnect {
    my ($self) = @_;
    $self->zircon_trace;

    $self->_destroy_zmq_requester;
    if (my $responder = $self->_zmq_responder) {
        $self->zircon_trace('responder...');
        zmq_unbind($responder, $self->local_endpoint);
        $self->zircon_trace('...unbound');
        zmq_close($responder);
        $self->zircon_trace('...closed');
    }
    if (my $ctx = $self->_zmq_context) {
        $self->zircon_trace('context...');
        zmq_ctx_destroy($ctx);
        $self->zircon_trace('...destroyed');
    }

    $self->zircon_trace('disconnected');
    return;
}

sub DESTROY {
    my ($self) = @_;
    $self->zircon_trace;
    $self->disconnect;
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
