use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));

use App::Greple::md;
use Text::ANSI::Fold::Util qw(ansi_width);

# box_lines: a box drawn by ansicolumn around the lines, folded in it

sub box { [ App::Greple::md::box_lines(@_) ] }
sub widths { my %w = map { ansi_width($_) => 1 } @{+shift}; [ sort { $a <=> $b } keys %w ] }

# as wide as the longest line, with a space before the right border
is_deeply(box(['hello world', 'second'], width => 40),
	  [ "\x{250C}" . "\x{2500}" x 13 . "\x{2510}",
	    "\x{2502} hello world \x{2502}",
	    "\x{2502} second      \x{2502}",
	    "\x{2514}" . "\x{2500}" x 13 . "\x{2518}" ],
	  'fit: the box style, as wide as the text');

# the label on the top, at the left
like(box(['x'], label => ' note ', width => 40)->[0], qr/^\x{250C}\x{2500} note \x{2500}+\x{2510}$/,
     'label: on the top border');

# fill: as wide as the width
is_deeply(widths(box(['hello'], width => 30, fill => 1)), [30], 'fill: the width');
is_deeply(widths(box(['hello'], width => 30, fill => 1, border => 'shadow-box')), [30],
	  'fill: the width, with the shadow');

# a line longer than the width is folded in the box
{
    my $b = box(['a long line that does not fit in the box of this width at all'], width => 30);
    is_deeply(widths($b), [30], 'fold: the width');
    ok(@$b > 3, 'fold: more lines');
}

# margin: spaces at the left, out of the box, taken from the width
{
    my $b = box(['hello'], width => 30, fill => 1, margin => 2);
    like($b->[0], qr/^  \x{250C}/, 'margin: at the left');
    is_deeply(widths($b), [28], 'margin: the box is narrower by the margins at both sides');
}

done_testing;
