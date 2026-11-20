---
title: Welcome to Lookdown
tags: [markdown, quick-look]
status: ready
---

# Welcome to Lookdown

Lookdown makes **Quick Look** show Markdown the way you read it in the Claude app or Obsidian: real headings, *styled* text, tables, colored code and callouts. Select any `.md` file in Finder and press <kbd>Space</kbd>.

> [!tip] Try it
> Pick a theme on the left. Your next spacebar preview uses it.

## What it renders

- **Text**: *italic*, **bold**, ~~strikethrough~~, ==highlights==, `inline code` and [links](https://commonmark.org)
- **Lists**: nested lists, numbered steps and task lists
- **Tables** with column alignment
- **Code blocks** with syntax colors for 50+ languages
- **Callouts** from Obsidian and GitHub, including ones that fold
- **Math**: inline $e^{i\pi} + 1 = 0$ and display equations
- **Front matter**, shown as properties like Obsidian does
- **Footnotes**[^1], [[wikilinks]] and #tags

### A short checklist

- [x] Install Lookdown
- [x] Open it once so macOS finds the extension
- [ ] Press Space on a Markdown file

## Code

```swift
struct Greeting {
    let name: String

    func render() -> String {
        "Hello, \(name)!"   // string interpolation
    }
}
```

```bash
# Reset Quick Look if a preview looks stale
qlmanage -r
```

## Tables

| Theme  | Body font | Feels like      |
| :----- | :-------: | --------------: |
| Warm   | Serif     | The Claude app  |
| Clean  | Sans      | Obsidian        |
| GitHub | Sans      | A GitHub README |

## Math

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

> [!warning]- What Quick Look can't do
> Quick Look runs no scripts, so Mermaid diagrams show as source and code blocks have no copy button.

> Plain blockquotes still read like quotes.

[^1]: Footnotes collect at the bottom, like this one.
