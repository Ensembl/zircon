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
    my $P = MockProtoXML->new;

    eq_or_diff
      ($P->serialise_request(vanish => 'view4'),
       q{<zmap app_id="Bob" request_id="0" socket_id="endpoint_remote" type="request" version="3.0">
<request command="vanish" view_id="view4" />
</zmap>}, 'request, empty');

    eq_or_diff
      ($P->serialise_request(smudge => view5 => 'with finger'),
       q{<zmap app_id="Bob" request_id="1" socket_id="endpoint_remote" type="request" version="3.0">
<request command="smudge" view_id="view5">
with finger
</request>
</zmap>}, 'request, flat');

    eq_or_diff
      ($P->serialise_request(prod => view6 => [ finger => { side => 'left' } ]),
       q{<zmap app_id="Bob" request_id="2" socket_id="endpoint_remote" type="request" version="3.0">
<request command="prod" view_id="view6">
<finger side="left" />
</request>
</zmap>}, 'request, depth 1');

    eq_or_diff
      ($P->serialise_request(prod => view7 => [ finger => { side => 'left' },
                                          [ speed => {}, 'quick' ] ]),
       q{<zmap app_id="Bob" request_id="3" socket_id="endpoint_remote" type="request" version="3.0">
<request command="prod" view_id="view7">
<finger side="left">
<speed>
quick
</speed>
</finger>
</request>
</zmap>}, 'request, depth 2');

    return;
}


sub reply_tt {
    plan tests => 3;

    my $P = MockProtoXML->new;

    eq_or_diff
      ($P->serialise_reply
       (req5 => cmd5 => [ undef,
                          [ message => { }, 'Done that' ] ]),
       q{<zmap app_id="Bob" request_id="req5" socket_id="endpoint_local" type="reply" version="3.0">
<reply command="cmd5" return_code="ok">
<message>
Done that
</message>
</reply>
</zmap>}, 'reply, ok');

    eq_or_diff
      ($P->serialise_reply
       (req6 => cmd6 => [ [ 345, 'could not' ],
                          [ message => { }, 'I fell over' ] ]),
       q{<zmap app_id="Bob" request_id="req6" socket_id="endpoint_local" type="reply" version="3.0">
<reply command="cmd6" reason="could not" return_code="345" />
</zmap>}, 'reply, failed 345');

    eq_or_diff
      ($P->serialise_reply
       (req7 => cmd7 => [ undef,
                          [ message => { }, 'Done that' ],
                          [ data => { payload => 1 },
                            [ gubbins => {} => [ 'stop' ] ] ] ]),
       q{<zmap app_id="Bob" request_id="req7" socket_id="endpoint_local" type="reply" version="3.0">
<reply command="cmd7" return_code="ok">
<message>
Done that
</message>
<data payload="1">
<gubbins>
<stop />
</gubbins>
</data>
</reply>
</zmap>}, 'reply, ok');

    return;
}

sub element_tt {
    plan tests => 7;

    my $X = new_ok('Zircon::Protocol::Serialiser::XML', [ -app_id => $0, -connection => {} ]);

    eq_or_diff
      ($X->serialise_element(tag => { attr2 => 3, Attr1 => 4, zttr3 => 5 },
            'text content'),
       q{<tag Attr1="4" attr2="3" zttr3="5">
text content
</tag>}, 'attrib sort');

    eq_or_diff
      ($X->serialise_element(tag => { funkies => 'quote " me a <node> & return it, would you?' }, undef),
       q{<tag funkies="quote &quot; me a &lt;node&gt; &amp; return it, would you?" />},
       'empty + attrib');

    eq_or_diff
      ($X->serialise_element('hr'), '<hr />', 'empty1');

    eq_or_diff
      ($X->serialise_element(hr => {}), '<hr />', 'empty2');

    eq_or_diff
      ($X->serialise_element(hr => {}, ''), "<hr>\n\n</hr>", 'empty3 (ws)');

    eq_or_diff
      ($X->serialise_element(data => {} =>
            [ message => {}, 'Text' ],
            [ detail => { foo => 5 },
              [ wag => {}, 'On' ] ]),
       qq{<data>
<message>\nText\n</message>
<detail foo="5">
<wag>\nOn\n</wag>
</detail>
</data>}, 'nesting');

    return;
}


sub parse_tt {
    plan tests => 6;
    my $P = MockProtoXML->new;
    my $Q = MockProtoXML->new;

    my $req = [ finger => { side => 'left' },
                undef # optional, but made explicit during parsing
              ];
    my $xml = $P->serialise_request(prod => view6 => $req);

    eq_or_diff($Q->parse_request($xml),
               [ '0', 'Bob', 'prod', 'view6', [ $req ] ],
               'command: prod');



    my $reply = [ message => { }, "  Roger   \n  " ];
    $xml = $P->serialise_reply(req1 => cmd1 => [ undef, $reply ]);
    $reply->[-1] = 'Roger';
    like($xml, qr{>\n  Roger   \n  \n<},
         'whitespace augmented during xml generation');
    eq_or_diff($Q->parse_reply($xml),
               [ req1 => cmd1 => ok => undef, undef, [ $reply ] ],
               'reply: ok, whitespace trimmed during parsing')
      or diag $xml;

    $xml = $P->serialise_reply(req2 => cmd2 => [ [ '502', 'Yeargh' ] ]);
    eq_or_diff($Q->parse_reply($xml),
               [ req2 => cmd2 => 502 => 'Yeargh', undef, undef ],
               'reply: 502 fail');

  {
    local $TODO = 'is the spec correct for this?';
    $reply = [ view => { view_id => 'deja0' }, undef ];
    $xml = $P->serialise_reply(req3 => cmd3 => [ undef, $reply ]);
    eq_or_diff($Q->parse_reply($xml),
               [ req3 => cmd3 => ok => undef,
                 'deja0', # comes back undef, should be the view_id ??
                 , [ $reply ] ],
               'reply: view ok')
      or diag $xml;
  }

  {
    local $TODO = 'deserialising nested is borked';
    my $nested = [ data => {} =>
                   [ message => {}, 'Text' ],
                   [ detail => { foo => 5 },
                     [ wag => {}, 'On' ] ]
        ];
    $xml = $P->serialise_reply(req4 => cmd4 => [ undef, $nested ]);
    eq_or_diff($Q->parse_reply($xml),
               [ req4 => cmd4 => ok => undef, undef, [ $nested ] ],
               'reply: nested ok')
        or diag $xml;
  }

    return;
}



# These Mocks cheerfully assume some methods work as class methods.
package MockProtoXML;
use base qw( Zircon::Protocol::Serialiser::XML );

sub inhibit_timestamps { return 1 }

sub _init {
    my ($self, $arg_hash) = @_;
    $self->SUPER::_init($arg_hash);
    $self->{'request_id'} = 0;
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
