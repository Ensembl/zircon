#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Differences;
use lib "t/lib";
use TestShared qw( do_subtests );


sub main {
    do_subtests(qw( reply_tt element_tt ));
    return 0;
}

main();


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



# These Mocks cheerfully assume the methods all work as class methods.
package MockProto;
use base qw( Zircon::Protocol::XML );

sub app_id { return 'Bob' }

sub connection { return 'MockConn' }

package MockConn;
sub local_selection_id { return 'sel_id_local' }

1;
