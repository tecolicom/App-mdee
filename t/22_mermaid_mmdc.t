use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));

use File::Temp qw(tempdir);

use lib '.';
use t::Util;

# image_types with mermaid and a mermaid_command whose name does not
# start with mmdr: it is run as mmdc of mermaid-cli, given the look by
# its options (-b, -s, -t) and the options of puppeteer in a file of
# -p, all the diagrams to be drawn from a Markdown file in one run,
# and one by one from a .mmd file each when that fails.  The stub here writes a
# PNG of 64x102 (3 rows) and logs its arguments.

$ENV{HOME} = my $dir = tempdir(CLEANUP => 1);
$ENV{TMPDIR} = "$dir/tmp";
mkdir "$dir/tmp";
my $cache = "$dir/tmp/mdee-mermaid-$>";

my $PH = "\x{10EEEE}";

my $log  = "$dir/log";
my $stub = "$dir/mmdc-stub";
$ENV{STUB_LOG} = $log;
{
    open my $fh, '>', $stub or die;
    print $fh "#!$^X\n", <<'STUB';
use strict;
use warnings;
my %opt;
for (my $i = 0; $i < @ARGV; $i++) {
    $opt{$ARGV[$i]} = $ARGV[$i + 1] if $ARGV[$i] =~ /^-[iotp]$/;
}
open my $log, '>>', $ENV{STUB_LOG} or die;
print $log "@ARGV\n";
close $log;
$opt{-i} =~ /\.(mmd|md)$/ or exit 2;
my $md = $1 eq 'md';
my $text = do { open my $in, '<', $opt{-i} or die; local $/; <$in> };
if ($text =~ /BAD/) {
    print STDERR "Error: Parse error on line 2:\n",
	"Parser.parseError (https://x.invalid/mermaid.mjs:1561:21)\n",
	"    at #evaluate (file:///x/ExecutionContext.js:402:19)\n";
    exit 1;
}
# a Markdown file: OUT-1.png, OUT-2.png ... for its diagrams
my @out = $md
    ? map { $opt{-o} =~ s/\.md$/-$_.png/r } 1 .. (() = $text =~ /^```mermaid$/mg)
    : $opt{-o};
for (@out) {
    open my $png, '>:raw', $_ or die;
    print $png "\x89PNG\r\n\x1a\n", pack('N', 13), 'IHDR',
	pack('NNCCCCC', 64, 102, 8, 6, 0, 0, 0), "\0\0\0\0",
	pack('N', 0), 'IEND', "\xae\x42\x60\x82";
}
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
my $term = "image_term=80x24:16x34,image_tty=$tty,image_align=left";
my $img  = "$term,mermaid_command=$stub";

sub mdee_out {
    my($cfg, $md) = @_;
    unlink $tty;
    run("'-Mmd::config($cfg)' $md")->stdout;
}
sub plain { (my $s = shift) =~ s/\e\[[0-9;]*[mK]//g; $s }

my $doc = md('doc.md', join '',
    "```mermaid\nflowchart LR\n  A[入力] --> B\n```\n\n",
    "```mermaid\nsequenceDiagram\n  A->>B: hi\n```\n\n",
    "end\n");

# each diagram in a run of its own, with the options of mmdc
{
    my $out = mdee_out("$base,image_types=mermaid,$img", $doc);
    is(scalar(() = plain($out) =~ /^$PH/mg), 6, 'three rows for each diagram');
    my @runs = runs();
    is(scalar @runs, 1, 'one run for the diagrams');
    like($runs[0], qr/-i \S+\.md -o \S+\.md$/, 'from a Markdown file of them');
    like($runs[0], qr/-e png -t default -b white -s 1.5 -p \S+\.json\b/, 'the look by the options, and -p');
    unlike($runs[0], qr/ -q /, 'not -q, for the lines of the diagrams drawn');
    unlike($runs[0], qr/ -c | --size/, 'no option of mmdr');
    is(scalar(() = glob "$cache/*.png"), 2, 'two diagrams are kept');
}

# the dark theme in the dark mode
{
    unlink $log;
    mdee_out("mode=dark,image_types=mermaid,$img", $doc);
    my($run) = runs();
    like($run // '', qr/-t dark -b #0d1117 /, 'the dark theme on the dark background');
}

# the browser goes to the network through a proxy that is not there,
# unless the command has its own options of puppeteer
{
    unlink $log;
    my $md = md('proxy.md', "```mermaid\ngraph TD\n  P1 --> Q1\n```\n");
    mdee_out("$base,image_types=mermaid,$img", $md);
    my($run) = runs();
    ok(($run // '') =~ /-p (\S+)/, 'proxy: -p is given');
    unlink $log;
    $md = md('proxy2.md', "```mermaid\ngraph TD\n  P2 --> Q2\n```\n");
    mdee_out("$base,image_types=mermaid,$term,mermaid_command=$stub -p /my/config.json", $md);
    ($run) = runs();
    is(scalar(() = ($run // '') =~ /-p /g), 1, 'proxy: not given with -p of the command');
}

# a diagram with an error stops the run of all: they are drawn one by
# one then, and the others are shown
{
    unlink $log;
    my $out = mdee_out("$base,image_types=mermaid,$img", md('mixed.md', join '',
	"```mermaid\ngraph TD\n  M1 --> M2\n```\n\n",
	"```mermaid\nBAD\n```\n\n",
	"```mermaid\ngraph TD\n  M3 --> M4\n```\n"));
    my @runs = runs();
    is(scalar @runs, 4, 'mixed: one run of all, and one for each');
    like($runs[0], qr/-i \S+\.md /, 'mixed: all first');
    is(scalar(grep { /-i \S+\.mmd / } @runs[1..$#runs]), 3, 'mixed: then each from a .mmd file');
    is(scalar(() = plain($out) =~ /^$PH/mg), 6, 'mixed: the others are shown');
    is(scalar(() = $out =~ /Parse error/g), 1, 'mixed: the error of the bad one');
}

# a single diagram is drawn from a .mmd file
{
    unlink $log;
    mdee_out("$base,image_types=mermaid,$img", md('single.md', "```mermaid\ngraph TD\n  S1 --> S2\n```\n"));
    my @runs = runs();
    is(scalar @runs, 1, 'single: one run');
    like($runs[0] // '', qr/-i \S+\.mmd /, 'single: from a .mmd file');
    like($runs[0] // '', qr/ -q /, 'single: -q');
}

# the message of mmdc, without the stack of JavaScript after it
{
    my $out = mdee_out("$base,image_types=mermaid,$img", md('bad.md', "```mermaid\nBAD\n```\n"));
    my @box = grep { /\x{2502}/ } split /\n/, plain($out);
    is(scalar @box, 1, 'bad: one line of the message');
    like($box[0] // '', qr/Error: Parse error on line 2:/, 'bad: the error');
    unlike($out, qr/parseError|ExecutionContext/, 'bad: no stack');
}

# the browser for mmdc: the first found, unless PUPPETEER_EXECUTABLE_PATH
{
    require App::Greple::md::Mermaid;
    open my $fh, '>', "$dir/chrome" or die; close $fh; chmod 0755, "$dir/chrome";
    local @App::Greple::md::Mermaid::BROWSERS = ("$dir/none/chrome", "$dir/chrome");
    local $ENV{PUPPETEER_EXECUTABLE_PATH};
    is(App::Greple::md::Mermaid::browser(), "$dir/chrome", 'browser: the first found');
    local @App::Greple::md::Mermaid::BROWSERS = ('chrome');
    local $ENV{PATH} = "$dir/none:$dir";
    is(App::Greple::md::Mermaid::browser(), "$dir/chrome", 'browser: a name in PATH');
    $ENV{PUPPETEER_EXECUTABLE_PATH} = '/my/chrome';
    is(App::Greple::md::Mermaid::browser(), undef, 'browser: none with PUPPETEER_EXECUTABLE_PATH');
}

# without a command, the first of mmdr and mmdc found in PATH
{
    require App::Greple::md::Mermaid;
    mkdir "$dir/bin";
    symlink $stub, "$dir/bin/mmdr" or die;
    local $ENV{PATH} = "$dir/none:$dir/bin";
    is(App::Greple::md::Mermaid::default_command(), 'mmdr', 'PATH: mmdr when there is no mmdc');
    symlink $stub, "$dir/bin/mmdc" or die;
    is(App::Greple::md::Mermaid::default_command(), 'mmdr', 'PATH: mmdr first');
    unlink "$dir/bin/mmdr";
    is(App::Greple::md::Mermaid::default_command(), 'mmdc', 'PATH: mmdc when there is no mmdr');
    local $ENV{PATH} = "$dir/none";
    is(App::Greple::md::Mermaid::default_command(), 'mmdr', 'PATH: mmdr when none is found');
}

done_testing;
