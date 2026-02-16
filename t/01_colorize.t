use strict;
use warnings;
use Test::More;
use open qw(:std :encoding(utf-8));

# Test that module loads
use_ok('App::Greple::md');

# Check greple is available
my $greple = `which greple 2>/dev/null`;
chomp $greple;
plan skip_all => "greple not found" unless $greple;

my $test_md = 't/test.md';
plan skip_all => "$test_md not found" unless -f $test_md;

my $cmd = "$^X -Ilib $greple";

# Basic output test
my $out = `$cmd -Mmd $test_md 2>/dev/null`;
ok(length($out) > 0, "greple -Mmd produces output");

# Output should contain ANSI escape sequences
like($out, qr/\e\[/, "output contains ANSI color sequences");

# Dark mode should also work
my $dark = `$cmd '-Mmd::config(mode=dark)' $test_md 2>/dev/null`;
ok(length($dark) > 0, "dark mode produces output");
like($dark, qr/\e\[/, "dark mode contains ANSI sequences");

# --cm override should work
my $override = `$cmd -Mmd --cm h1=RD $test_md 2>/dev/null`;
ok(length($override) > 0, "--cm override produces output");

# OSC 8 test: output should contain OSC 8 sequences for links
like($out, qr/\e\]8;;/, "output contains OSC 8 hyperlink sequences");

done_testing;
