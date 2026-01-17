# H1: mdee Test Document

This is a test file for checking **bold text** and `inline code` styles.

## H2: Pipeline Architecture

The `mdee` command constructs a **pipeline** of commands.

### H3: Processing Stages

Each stage can be enabled using `--fold`, `--table`, and `--nup` options.

#### H4: Syntax Highlighting

Uses `greple` with `-G` and `--ci=G` options.

##### H5: Color Specifications

Colors like `L00DE/${base}` use **Term::ANSIColor::Concise** format.

## H2: Code Block Examples

Here is a code block:

```bash
greple -G --ci=G --all --need=0 \
    --cm 'L00DE/${base}' -E '^#\h+.*' \
    file.md
```

Another example:

```perl
my $color = '#CCCDFF';
print "Base color: $color\n";
```

## H2: Table Example

|Name|Description|Status|
|-|-|-|
|greple|Pattern matching tool|active|
|ansifold|ANSI-aware text folding|active|
|ansicolumn|Column formatting with ANSI support|active|

## H2: List Example

- First item with `inline code`
- Second item with **bold text**
- Third item with a longer description that might wrap to multiple lines when displayed in a narrow terminal window

<!-- This is an HTML comment that should be dimmed -->

### H3: Nested Content

Some text with `multiple` inline `code` segments and **bold** words.

#### H4: More Details

Final section with `code` and **emphasis**.

##### H5: Deep Nesting

The deepest level with `L00DE/${base}` color specification.
