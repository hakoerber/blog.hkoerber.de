---
title: "Sphinx: Use CSV macro for simple Markdown-like tables"
date: "2018-12-30T19:39:16+01:00"
summary: |
  How to use the "csv-tables" macro to get Markdown-like table syntax in Sphinx
tags:
- sphinx
- documentation
---

I am quite fond of [Sphinx](http://www.sphinx-doc.org/en/master/), a documentation generator using [reStructuredText](http://docutils.sourceforge.net/rst.html) markup syntax. At Tradebyte, we use Sphinx extensively for all kinds of documentation.

One thing I do not like about Sphinx is its table syntax[^1]:

[^1]: Taken from http://www.sphinx-doc.org/en/master/usage/restructuredtext/basics.html#tables --- retrieved 2018-12-30

```rst
+------------------------+------------+----------+----------+
| Header row, column 1   | Header 2   | Header 3 | Header 4 |
| (header rows optional) |            |          |          |
+========================+============+==========+==========+
| body row 1, column 1   | column 2   | column 3 | column 4 |
+------------------------+------------+----------+----------+
| body row 2             | ...        | ...      |          |
+------------------------+------------+----------+----------+
```

In my experience, it is very tedious to write and maintain. The rationale behind the syntax is rooted in the desing of reStructuredText: it is supposed to be readable as text without rendering to another format like HTML.

In contrast to that, Markdown has the following syntax for tables[^2]:

[^2]: Taken from https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet --- retrieved 2018-12-30

```markdown
| Tables        | Are           | Cool  |
| ------------- | ------------- | ----- |
| col 3 is      | right-aligned | $1600 |
| col 2 is      | centered      |   $12 |
| zebra stripes | are neat      |    $1 |
```

CSV tables to the rescue!

You can use a sphinx extension to get Markdown-like syntax for you tables, using ``csv-table`` like this:

```rst
.. csv-table::

   :header-rows: 1
   :separator: |

   Header 1 | Header 2
   Cell 1 | Cell 2
```

This gives you (kind of) the same functionality as with Markdown, at least for simple tables (e.g. no joined cells)
