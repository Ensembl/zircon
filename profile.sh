
#  If $ANACODE_ZIRCON is set, we assume it is the full path to a
#  Zircon repository and update our search paths accordingly.

if true &&
    [ -n "$ANACODE_ZIRCON" ] &&
    [ -d "$ANACODE_ZIRCON" ] &&
    true
then

    PATH="$PATH\
:$ANACODE_ZIRCON/bin\
"

    PERL5LIB="$PERL5LIB\
:$ANACODE_ZIRCON/perl\
"

fi
