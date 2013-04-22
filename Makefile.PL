use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile
  (NAME => 'Zircon',
   MIN_PERL_VERSION => '5.010', # a guess
   VERSION => '0.05', # https://metacpan.org/module/ExtUtils::MakeMaker#VERSION
  );

