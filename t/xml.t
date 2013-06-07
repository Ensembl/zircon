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
    my $P = MockProto->new;

    eq_or_diff
      ($P->request_xml(vanish => 'view4'),
       q{<zmap app_id="Bob" clipboard_id="sel_id_remote" request_id="0" type="request" version="2.0">
<request command="vanish" view_id="view4" />
</zmap>}, 'request, empty');

    eq_or_diff
      ($P->request_xml(smudge => view5 => 'with finger'),
       q{<zmap app_id="Bob" clipboard_id="sel_id_remote" request_id="1" type="request" version="2.0">
<request command="smudge" view_id="view5">
with finger
</request>
</zmap>}, 'request, flat');

    eq_or_diff
      ($P->request_xml(prod => view6 => [ finger => { side => 'left' } ]),
       q{<zmap app_id="Bob" clipboard_id="sel_id_remote" request_id="2" type="request" version="2.0">
<request command="prod" view_id="view6">
<finger side="left" />
</request>
</zmap>}, 'request, depth 1');

    eq_or_diff
      ($P->request_xml(prod => view7 => [ finger => { side => 'left' },
                                          [ speed => {}, 'quick' ] ]),
       q{<zmap app_id="Bob" clipboard_id="sel_id_remote" request_id="3" type="request" version="2.0">
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

    eq_or_diff
      (MockProto->reply_xml
       (req5 => cmd5 => [ undef,
                          [ message => { }, 'Done that' ] ]),
       q{<zmap app_id="Bob" clipboard_id="sel_id_local" request_id="req5" type="reply" version="2.0">
<reply command="cmd5" return_code="ok">
<message>
Done that
</message>
</reply>
</zmap>}, 'reply, ok');

    eq_or_diff
      (MockProto->reply_xml
       (req6 => cmd6 => [ [ 345, 'could not' ],
                          [ message => { }, 'I fell over' ] ]),
       q{<zmap app_id="Bob" clipboard_id="sel_id_local" request_id="req6" type="reply" version="2.0">
<reply command="cmd6" reason="could not" return_code="345" />
</zmap>}, 'reply, failed 345');

    eq_or_diff
      (MockProto->reply_xml
       (req7 => cmd7 => [ undef,
                          [ message => { }, 'Done that' ],
                          [ data => { payload => 1 },
                            [ gubbins => {} => [ 'stop' ] ] ] ]),
       q{<zmap app_id="Bob" clipboard_id="sel_id_local" request_id="req7" type="reply" version="2.0">
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
    plan tests => 6;
    my $e = Zircon::Protocol::XML->can('_element_xml'); # a sub, not a method

    eq_or_diff
      ($e->(tag => { attr2 => 3, Attr1 => 4, zttr3 => 5 },
            'text content'),
       q{<tag Attr1="4" attr2="3" zttr3="5">
text content
</tag>}, 'attrib sort');

    eq_or_diff
      ($e->(tag => { funkies => 'quote " me a <node> & return it, would you?' }, undef),
       q{<tag funkies="quote &quot; me a &lt;node&gt; &amp; return it, would you?" />},
       'empty + attrib');

    eq_or_diff
      ($e->('hr'), '<hr />', 'empty1');

    eq_or_diff
      ($e->(hr => {}), '<hr />', 'empty2');

    eq_or_diff
      ($e->(hr => {}, ''), "<hr>\n\n</hr>", 'empty3 (ws)');

    eq_or_diff
      ($e->(data => {} =>
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
    plan tests => 5;
    my $P = MockProto->new;

    my $req = [ finger => { side => 'left' },
                undef # optional, but made explicit during parsing
              ];
    my $xml = $P->request_xml(prod => view6 => $req);

    eq_or_diff(MockProto->request_xml_parse($xml),
               [ '0', 'prod', 'view6', [ $req ] ],
               'command: prod');



    my $reply = [ message => { }, "  Roger   \n  " ];
    $xml = $P->reply_xml(req1 => cmd1 => [ undef, $reply ]);
    $reply->[-1] = 'Roger';
    like($xml, qr{>\n  Roger   \n  \n<},
         'whitespace augmented during xml generation');
    eq_or_diff(MockProto->reply_xml_parse($xml),
               [ req1 => cmd1 => ok => undef, undef, [ $reply ] ],
               'reply: ok, whitespace trimmed during parsing')
      or diag $xml;

    $xml = $P->reply_xml(req2 => cmd2 => [ [ '502', 'Yeargh' ] ]);
    eq_or_diff(MockProto->reply_xml_parse($xml),
               [ req2 => cmd2 => 502 => 'Yeargh', undef, undef ],
               'reply: 502 fail');

  {
    local $TODO = 'is the spec correct for this?';
    $reply = [ view => { view_id => 'deja0' }, undef ];
    $xml = $P->reply_xml(req3 => cmd3 => [ undef, $reply ]);
    eq_or_diff(MockProto->reply_xml_parse($xml),
               [ req3 => cmd3 => ok => undef,
                 'deja0', # comes back undef, should be the view_id ??
                 , [ $reply ] ],
               'reply: view ok')
      or diag $xml;
  }
    return;
}



# These Mocks cheerfully assume some methods work as class methods.
package MockProto;
use base qw( Zircon::Protocol::XML );

sub new {
    my $self = {};
    return bless $self, __PACKAGE__;
}

sub app_id { return 'Bob' }

sub connection { return 'MockConn' }

package MockConn;
sub local_selection_id { return 'sel_id_local' }
sub remote_selection_id { return 'sel_id_remote' }

1;
