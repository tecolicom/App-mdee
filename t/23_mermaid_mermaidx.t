use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));

use File::Temp qw(tempdir);

use lib '.';
use t::Util;

# image_types with mermaid and a mermaid_command named mermaidx: it is
# run as mermaidx of PyPI, which runs mermaid.js in Python without a
# browser, given the look by its options (-t, -b, --scale), each
# diagram from a .mmd file of its own, with no file of options.  The
# stub writes a PNG of 64x34 (1 row) and logs its arguments; with BAD
# in the code, it fails with a traceback of Python, as mermaidx does.

$ENV{HOME} = my $dir = tempdir(CLEANUP => 1);
$ENV{TMPDIR} = "$dir/tmp";
mkdir "$dir/tmp";

my $PH = "\x{10EEEE}";

my $log  = "$dir/log";
mkdir "$dir/bin";
my $stub = "$dir/bin/mermaidx";
$ENV{STUB_LOG} = $log;
{
    open my $fh, '>', $stub or die;
    print $fh "#!$^X\n", <<'STUB';
use strict;
use warnings;
my %opt;
for (my $i = 0; $i < @ARGV; $i++) {
    $opt{$ARGV[$i]} = $ARGV[$i + 1] if $ARGV[$i] =~ /^-[io]$/;
}
open my $log, '>>', $ENV{STUB_LOG} or die;
print $log "@ARGV\n";
close $log;
$opt{-i} =~ /\.mmd$/ or exit 2;
my $text = do { open my $in, '<', $opt{-i} or die; local $/; <$in> };
if ($text =~ /BAD/) {
    print STDERR "Traceback (most recent call last):\n",
	"  File \"/x/mermaidx/diagram.py\", line 609, in _svg\n",
	"    raise RuntimeError(f\"Mermaid rendering failed: {e}\") from e\n",
	"RuntimeError: Mermaid rendering failed: Error: Parse error on line 2:\n",
	"-------------------^\n";
    exit 1;
}
open my $png, '>:raw', $opt{-o} or die;
print $png "\x89PNG\r\n\x1a\n", pack('N', 13), 'IHDR',
    pack('NNCCCCC', 64, 34, 8, 6, 0, 0, 0), "\0\0\0\0",
    pack('N', 0), 'IEND', "\xae\x42\x60\x82";
STUB
    close $fh;
    chmod 0755, $stub;
}
sub runs { my @l; if (open my $fh, '<', $log) { @l = <$fh> } @l }

sub md {
    my($name, $text) = @_;
    open my $fh, '>:encoding(utf-8)', "$dir/$name" or die;
    print $fh $text;
    close $fh;
    "$dir/$name";
}

my $tty = "$dir/tty";
my $base = 'mode=light';
my $img  = "image_term=80x24:16x34,image_tty=$tty,image_align=left,mermaid_command=$stub";

sub mdee_out {
    my($cfg, $md) = @_;
    run("'-Mmd::config($cfg)' $md")->stdout;
}
sub plain { (my $s = shift) =~ s/\e\[[0-9;]*[mK]//g; $s }

# each diagram in a run of its own, with the options of mermaidx
{
    my $out = mdee_out("$base,image_types=mermaid,$img", md('doc.md', join '',
	"```mermaid\ngraph TD\n  A --> B\n```\n\n",
	"```mermaid\ngraph TD\n  C --> D\n```\n"));
    is(scalar(() = plain($out) =~ /^$PH/mg), 2, 'a row for each diagram');
    my @runs = runs();
    is(scalar @runs, 2, 'a run for each diagram');
    like($runs[0], qr/^-q -t default -b white --scale 1\.5 -i \S+\.mmd -o \S+\.png$/,
	 'the look by the options, PNG by the name of the output');
    unlike($runs[0], qr/ -[ecp] /, 'no option of mmdc or mmdr');
}

# the message of mermaidx, without the traceback of Python and the
# exception which carries it
{
    my $out = plain(mdee_out("$base,image_types=mermaid,$img", md('bad.md', "```mermaid\nBAD\n```\n")));
    my @box = grep { /\x{2502}/ } split /\n/, $out;
    like($box[0] // '', qr/^\x{2502} Error: Parse error on line 2: /, 'bad: the error of mermaid.js');
    is(scalar @box, 2, 'bad: and the line after it');
    unlike($out, qr/Traceback|RuntimeError|diagram\.py/, 'bad: no traceback');
    like($out, qr/mermaidx/, 'bad: the name of the command');
}

done_testing;
