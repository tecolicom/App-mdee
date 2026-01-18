use v5.14;
use warnings;
use utf8;

use Test::More;
use File::Spec;

# Skip tests on platforms without bash or with old bash
BEGIN {
    my $bash_check = `bash --version 2>&1`;
    if ($? != 0) {
        plan skip_all => 'bash is not available on this system';
    }
    if ($bash_check =~ /version (\d+)\.(\d+)/) {
        my ($major, $minor) = ($1, $2);
        if ($major < 4 || ($major == 4 && $minor < 3)) {
            plan skip_all => "bash 4.3+ required (found $major.$minor)";
        }
    }
}

# Skip if getoptlong.sh is not available
BEGIN {
    my $check = `command -v getoptlong.sh 2>/dev/null`;
    if ($? != 0) {
        plan skip_all => 'getoptlong.sh is not available in PATH';
    }
}

my $mdee = File::Spec->rel2abs('script/mdee');
my $test_md = File::Spec->rel2abs('t/test.md');

# Check if mdee exists
ok(-x $mdee, 'mdee is executable');

# Test: help option
subtest 'help option' => sub {
    my $out = `$mdee --help 2>&1`;
    like($out, qr/mdee.*Markdown/i, '--help shows description');
    like($out, qr/--mode/, '--help shows --mode option');
    like($out, qr/--theme/, '--help shows --theme option');
    like($out, qr/--filter/, '--help shows --filter option');
    like($out, qr/\[no-\]fold/, '--help shows --fold option');
    like($out, qr/\[no-\]table/, '--help shows --table option');
    like($out, qr/\[no-\]nup/, '--help shows --nup option');
};

# Test: version option
subtest 'version option' => sub {
    my $out = `$mdee --version 2>&1`;
    like($out, qr/^\d+\.\d+/, '--version shows version number');
};

# Test: dryrun option
subtest 'dryrun option' => sub {
    my $out = `$mdee --dryrun $test_md 2>&1`;
    like($out, qr/greple/, '--dryrun shows greple command');
    like($out, qr/nup/, '--dryrun shows nup command');
};

# Test: mode option
subtest 'mode option' => sub {
    my $out_light = `$mdee --dryrun --mode=light $test_md 2>&1`;
    my $out_dark = `$mdee --dryrun --mode=dark $test_md 2>&1`;
    isnt($out_light, $out_dark, 'light and dark modes produce different output');
};

# Test: no-nup option
subtest 'no-nup option' => sub {
    my $out = `$mdee --dryrun --no-nup $test_md 2>&1`;
    unlike($out, qr/\|\s*nup/, '--no-nup excludes nup from pipeline');
};

# Test: no-fold option
subtest 'no-fold option' => sub {
    my $out = `$mdee --dryrun --no-fold $test_md 2>&1`;
    unlike($out, qr/ansifold/, '--no-fold excludes ansifold from pipeline');
};

# Test: no-table option
subtest 'no-table option' => sub {
    my $out = `$mdee --dryrun --no-table $test_md 2>&1`;
    unlike($out, qr/ansicolumn/, '--no-table excludes ansicolumn from pipeline');
};

# Test: filter option
subtest 'filter option' => sub {
    my $out = `$mdee --dryrun -f $test_md 2>&1`;
    unlike($out, qr/ansifold/, '-f disables fold');
    unlike($out, qr/ansicolumn/, '-f disables table');
    unlike($out, qr/\|\s*nup/, '-f disables nup');
};

# Test: list-themes option
subtest 'list-themes option' => sub {
    my $out = `$mdee --list-themes 2>&1`;
    like($out, qr/Built-in themes/i, '--list-themes shows themes');
    like($out, qr/default/, '--list-themes shows default theme');
};

# Test: width option
subtest 'width option' => sub {
    my $out = `$mdee --dryrun --width=60 $test_md 2>&1`;
    like($out, qr/-sw60/, '--width=60 sets fold width');
};

# Test: show option
subtest 'show option' => sub {
    # Count -E options in first greple command (before first pipe)
    sub count_patterns {
        my $out = shift;
        my ($first_cmd) = $out =~ /^(.*?)\s+\|/s;
        return () = ($first_cmd // '') =~ /-E/g;
    }

    # all fields enabled by default (13 patterns)
    my $default = `$mdee --dryrun $test_md 2>&1`;
    is(count_patterns($default), 13, 'default has 13 patterns');

    # --show italic=0 disables italic (11 patterns: 13 - 2 italic patterns)
    my $no_italic = `$mdee --dryrun --show italic=0 $test_md 2>&1`;
    is(count_patterns($no_italic), 11, '--show italic=0 removes 2 patterns');

    # --show bold=0 disables bold (11 patterns: 13 - 2 bold patterns)
    my $no_bold = `$mdee --dryrun --show bold=0 $test_md 2>&1`;
    is(count_patterns($no_bold), 11, '--show bold=0 removes 2 patterns');

    # --show all enables all fields (13 patterns)
    my $all = `$mdee --dryrun --show all $test_md 2>&1`;
    is(count_patterns($all), 13, '--show all has 13 patterns');

    # --show all= --show bold enables only bold (2 patterns)
    my $only_bold = `$mdee --dryrun '--show=all=' --show=bold $test_md 2>&1`;
    is(count_patterns($only_bold), 2, '--show all= --show bold has 2 patterns');

    # unknown field should error
    my $unknown = `$mdee --dryrun --show unknown $test_md 2>&1`;
    like($unknown, qr/unknown field/, '--show unknown produces error');
};

done_testing;
