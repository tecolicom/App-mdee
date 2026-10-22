use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));
use Text::ANSI::Fold::Util qw(ansi_width);

use lib '.';
use t::Util;

my $md = 't/table_wrap.md';
my $V = "\x{2502}";   # │
my $strip = sub { local $_ = shift; s/\e\[[0-9;]*[mK]//g; s/\e\]8;;[^\e]*\e\\//g; $_ };
sub table_lines { grep { /[\x{2502}\x{253C}]/ } map { $strip->($_) } split /\n/, shift }

# table_width wraps over-wide columns
my $wrapped = run("'-Mmd::config(colorize=0,table=1,rule=1,table_width=40)' $md")->stdout;
my @w = table_lines($wrapped);
ok(@w > 6, 'rows were wrapped into extra lines');
ok(!(grep { ansi_width($_) > 40 } @w), 'every table line fits in 40 columns');
ok((grep { /^\s+$V/ } @w), 'continuation lines keep the column rule');
is(scalar(grep { /\x{253C}/ } @w), 1, 'exactly one separator row');
unlike($wrapped, qr/^\s*[。、]/m, 'no line starts with Japanese closing punctuation');

my $plain = run("'-Mmd::config(colorize=0,table=1,rule=1)' $md")->stdout;
ok((grep { ansi_width($_) > 40 } table_lines($plain)), 'without table_width the table is wider than 40');
is(run("'-Mmd::config(colorize=0,table=1,rule=1,table_width=200)' $md")->stdout, $plain,
   'a fitting width leaves output unchanged');

# table_cell caps a column (colon separated)
my $cell = run("'-Mmd::config(colorize=0,table=1,rule=1,table_cell=0:10)' $md")->stdout;
ok(!(grep { /$V(.*)$/ && ansi_width($1) > 12 } table_lines($cell)),
   'table_cell caps column 2 at 10 (+padding)');

my $notrim = run("'-Mmd::config(colorize=0,table=1,rule=1,table_trim=0,table_cell=0:10)' $md")->stdout;
ok(!(grep { /^\S*$V[^$V]*$V(.*?)$V/ && ansi_width($1) > 12 } table_lines($notrim)),
   'non-trim mode shifts the cell list');

done_testing;
