package App::mdee;

our $VERSION = "0.01";

1;
=encoding utf-8

=head1 NAME

mdee - Markdown, Easy on the Eyes

=head1 SYNOPSIS

    mdee [ options ] file ...

    mdee README.md              # view markdown file
    mdee -C2 document.md        # 2-column view
    mdee -f file.md             # filter mode (highlight only)
    cat file.md | mdee -f       # highlight stdin

=head1 DESCRIPTION

B<mdee> is a Markdown viewer command that combines L<greple(1)> for
syntax highlighting with L<nup(1)> for multi-column paged output.

It provides colorized display of Markdown files with support for
headers, bold text, inline code, code blocks, HTML comments, tables,
and list items with proper indentation.

This tool is primarily designed for viewing Markdown files generated
by LLMs, not for human-authored documents.

See L<mdee(1)> for full documentation.

=head1 AUTHOR

Kazumasa Utashiro

=head1 LICENSE

Copyright 2026 Kazumasa Utashiro.

This software is released under the MIT License.

=cut
