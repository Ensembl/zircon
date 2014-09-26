#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Differences;
use lib "t/lib";
use TestShared qw( do_subtests );


sub main {
    do_subtests(qw( request_tt reply_tt element_tt parse_tt ));
    return 0;
}

main();

sub request_tt {
    plan tests => 4;
    my $P = MockProtoJSON->new(-app_tag => 'zircon_test');

    eq_or_diff
      ($P->serialise_request(vanish => 'view4'),
       _make_expected_request(0, 'vanish', 'view4', undef),
       'request, empty');

    eq_or_diff
      ($P->serialise_request(smudge => view5 => 'with finger'),
       _make_expected_request(1, 'smudge', 'view5', '"with finger"'),
       'request, flat');

    eq_or_diff
      ($P->serialise_request(prod => view6 => [ finger => { side => 'left' } ]),
       _make_expected_request(2, 'prod', 'view6', <<'__EO_REQ__'),
{
               "finger" : {
                  "side" : "left"
               }
            },
__EO_REQ__
       'request, depth 1');

    eq_or_diff
      ($P->serialise_request(prod => view7 => [ finger => { side => 'left' },
                                          [ speed => {}, 'quick' ] ]),
       _make_expected_request(3, 'prod', 'view7', <<'__EO_REQ__'),
{
               "finger" : {
                  "_content" : {
                     "speed" : {
                        "_content" : "quick"
                     }
                  },
                  "side" : "left"
               }
            },
__EO_REQ__
       'request, depth 2');

    return;
}

sub _make_expected_request {
    my ($request_id, $command, $view, $content, $multi) = @_;
    $content = _make_expected_content($content, $multi);
    my $request = sprintf(<< '__EO_REQUEST__', $content // '', $command, $view);
         "request" : {
%s
            "command" : "%s",
            "view_id" : "%s"
         }
__EO_REQUEST__
    $request =~ s/^,?\s*$(\n)//msg; # remove any blank or empty lines
    return _make_expected_outer ('request', $request_id, 'endpoint_remote', $request);
}


sub reply_tt {
    plan tests => 3;
    my $P = MockProtoJSON->new(-app_tag => 'zircon_test');

    eq_or_diff
      ($P->serialise_reply
       (req5 => cmd5 => [ undef,
                          [ message => { }, 'Done that' ] ]),
       _make_expected_reply('req5', 'cmd5', 'ok' => undef, <<'__EO_REP__'),
{
               "message" : {
                  "_content" : "Done that"
               }
            },
__EO_REP__
       'reply, ok');

    eq_or_diff
      ($P->serialise_reply
       (req6 => cmd6 => [ [ 345, 'could not' ],
                          [ message => { }, 'I fell over' ] ]),
       _make_expected_reply('req6', 'cmd6', 345 => 'could not', <<'__EO_REP__'),
__EO_REP__
    'reply, failed 345');

    eq_or_diff
      ($P->serialise_reply
       (req7 => cmd7 => [ undef,
                          [ message => { }, 'Done that' ],
                          [ data => { payload => 1 },
                            [ gubbins => {} => [ 'stop' ] ] ] ]),
       _make_expected_reply('req7', 'cmd7', 'ok' => undef, <<'__EO_REP__', 1),
{
                  "message" : {
                     "_content" : "Done that"
                  }
               },
               {
                  "data" : {
                     "_content" : {
                        "gubbins" : {
                           "_content" : {
                              "stop" : {}
                           }
                        }
                     },
                     "payload" : 1
                  }
               }
__EO_REP__
    'reply, ok, extra data');

    return;
}

sub _make_expected_reply {
    my ($request_id, $command, $return_code, $reason, $content, $multi) = @_;
    $return_code =~ /^\d+$/ or $return_code = sprintf('"%s"', $return_code);
    $content = _make_expected_content($content, $multi);
    if ($reason) {
        $reason = sprintf('            "reason" : "%s",', $reason);
    }
    my $reply = sprintf(<< '__EO_REPLY__', $content // '', $command, $reason // '', $return_code);
         "reply" : {
%s
            "command" : "%s",
%s
            "return_code" : %s
         }
__EO_REPLY__
    $reply =~ s/^,?\s*$(\n)//msg; # remove any blank or empty lines
    return _make_expected_outer ('reply', $request_id, 'endpoint_local', $reply);
}

sub _make_expected_content {
    my ($content, $multi) = @_;
    if ($content) {
        if ($multi) {
            $content = sprintf(<<'__EO_CONTENT__', $content);
            "_content" : [
               %s
            ],
__EO_CONTENT__
        } else {
            $content = sprintf('%s"_content" : %s,', scalar(' ' x 12), $content);
        }
        chomp $content;
    }
    return $content;
}

sub _make_expected_outer {
    my ($type, $request_id, $socket_id, $content) = @_;
    $request_id =~ /^\d+$/ or $request_id = sprintf('"%s"', $request_id);
    return sprintf(<< '__EO_OUTER__', $content, $request_id, $socket_id, $type);
{
   "zircon_test" : {
      "_content" : {
%s      },
      "app_id" : "Bob",
      "request_id" : %s,
      "socket_id" : "%s",
      "type" : "%s",
      "version" : "3.0"
   }
}
__EO_OUTER__
}


sub element_tt {
    plan tests => 6;

    my $J = new_ok('Zircon::Protocol::Serialiser::JSON', [ -app_id => $0, -connection => {} ]);

    eq_or_diff
      ($J->serialise_element(tag => { attr2 => 3, Attr1 => 4, zttr3 => 5 },
            'text content'),
       {
           tag => {
               Attr1 => 4,
               _content => 'text content',
               'attr2' => 3,
               'zttr3' => 5,
           }
       },
       'attrib sort');

    eq_or_diff
      ($J->serialise_element('hr'), { hr => {} }, 'empty1');

    eq_or_diff
      ($J->serialise_element(hr => {}), { hr => {} }, 'empty2');

    eq_or_diff
      ($J->serialise_element(hr => {}, ''), { hr => { _content => '' } }, 'empty3 (ws)');

    eq_or_diff
      ($J->serialise_element(data => {} =>
            [ message => {}, 'Text' ],
            [ detail => { foo => 5 },
              [ wag => {}, 'On' ] ]),
       { data => {
           _content => [
               { message => { _content => 'Text' } },
               { detail  => {
                   _content => { wag => { _content => 'On' } },
                   foo => 5,
                 } }
               ],
         }
       },
       'nesting');

    return;
}


sub parse_tt {
    plan tests => 4;
    my $P = MockProtoJSON->new;
    my $Q = MockProtoJSON->new;

    my $req = [ finger => { side => 'left' },
                undef # optional, but made explicit during parsing
              ];
    my $json = $P->serialise_request(prod => view6 => $req);

    eq_or_diff($Q->parse_request($json),
               [ 0, 'Bob', 'prod', 'view6', [ $req ] ],
               'command: prod');

    # Is it important that whitespace is stripped, when it was
    # there to start with? vvv
    #
    # my $reply = [ message => { }, "  Roger   \n  " ];
    # $json = $P->serialise_reply(req1 => cmd1 => [ undef, $reply ]);
    # $reply->[-1] = 'Roger';
    # like($json, qr{>\n  Roger   \n  \n<},
    #      'whitespace augmented during json generation');
    # eq_or_diff($Q->parse_reply($json),
    #            [ req1 => cmd1 => ok => undef, undef, [ $reply ] ],
    #            'reply: ok, whitespace trimmed during parsing')
    #   or diag $json;

    $json = $P->serialise_reply(req2 => cmd2 => [ [ '502', 'Yeargh' ] ]);
    eq_or_diff($Q->parse_reply($json),
               [ req2 => cmd2 => 502 => 'Yeargh', undef, undef ],
               'reply: 502 fail');

  {
    local $TODO = 'is the spec correct for this?';
    my $reply = [ view => { view_id => 'deja0' }, undef ];
    $json = $P->serialise_reply(req3 => cmd3 => [ undef, $reply ]);
    eq_or_diff($Q->parse_reply($json),
               [ req3 => cmd3 => ok => undef,
                 'deja0', # comes back undef, should be the view_id ??
                 , [ $reply ] ],
               'reply: view ok')
      or diag $json;
  }

  {
    local $TODO = 'deserialising nested is borked';
    my $nested = [ data => {} =>
                   [ message => {}, 'Text' ],
                   [ detail => { foo => 5 },
                     [ wag => {}, 'On' ] ]
        ];
    $json = $P->serialise_reply(req4 => cmd4 => [ undef, $nested ]);
    eq_or_diff($Q->parse_reply($json),
               [ req4 => cmd4 => ok => undef, undef, [ $nested ] ],
               'reply: nested ok')
        or diag $json;
  }

    return;
}



# These Mocks cheerfully assume some methods work as class methods.
package MockProtoJSON;
use base qw( Zircon::Protocol::Serialiser::JSON );

sub inhibit_timestamps { return 1 }

sub _init {
    my ($self, $arg_hash) = @_;
    $self->SUPER::_init($arg_hash);
    $self->_json->pretty->canonical;
    return;
}

sub _app_id { return 'Bob' }

sub _connection { return MockConn->new }

package MockConn;

sub new {
    my $self = {};
    return bless $self, __PACKAGE__;
}

sub local_endpoint { return 'endpoint_local' }
sub remote_endpoint { return 'endpoint_remote' }

1;
