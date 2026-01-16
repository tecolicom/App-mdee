requires 'perl', '5.016';
requires 'App::Greple', '10.02';
requires 'App::Greple::tee', '1.03';
requires 'App::ansifold', '1.34';
requires 'App::ansicolumn', '1.48';
requires 'App::nup', '0.99';
requires 'Getopt::Long::Bash', '0.7.0';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
