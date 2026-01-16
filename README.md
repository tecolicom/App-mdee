
# NAME

mdv - Markdown viewer using greple

# SYNOPSIS

    mdv [ options ] file ...

    Options:
        -h, --help          show help message
        -v, --version       show version
        -w, --width=#       output width (default: 80)
        -x, --trace         enable trace mode
        --border-style=#    ansicolumn border style
        -C, --pane=#        ansicolumn pane option
        -p, --paragraph     ansicolumn paragraph mode

# VERSION

    Version 0.01

# DESCRIPTION

**mdv** is a Markdown viewer command using [greple(1)](http://man.he.net/man1/greple) for syntax
highlighting.  It provides colorized output of Markdown files with
support for:

- Headers (h1-h5)
- Bold text
- Inline code (backticks)
- Code blocks (fenced with \`\`\`)
- HTML comments
- Tables

Output is processed through [ansifold(1)](http://man.he.net/man1/ansifold) for line wrapping and
[ansicolumn(1)](http://man.he.net/man1/ansicolumn) for terminal paging.

# DEPENDENCIES

This command requires the following CPAN modules:

- [App::Greple](https://metacpan.org/pod/App%3A%3AGreple)
- [App::Greple::tee](https://metacpan.org/pod/App%3A%3AGreple%3A%3Atee)
- [App::ansifold](https://metacpan.org/pod/App%3A%3Aansifold)
- [App::ansicolumn](https://metacpan.org/pod/App%3A%3Aansicolumn)
- [Getopt::Long::Bash](https://metacpan.org/pod/Getopt%3A%3ALong%3A%3ABash)

# AUTHOR

Kazumasa Utashiro

# LICENSE

Copyright 2025 Kazumasa Utashiro.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
