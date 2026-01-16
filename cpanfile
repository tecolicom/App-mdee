requires 'perl', 'v5.26';
requires 'Getopt::Long::Bash';
requires 'App::Greple', '10.02';
requires 'App::Greple::tee', '1.03';
requires 'App::ansifold', '1.34';
requires 'App::ansicolumn', '1.50';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
