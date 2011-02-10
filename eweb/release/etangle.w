Etangle
=======
Filippo Erik Negroni <f.e.negroni@googlemail.com>
Version 9.10

Tangle AsciiDoc documents with embedded code snippets.
Written in Python 3.

----
<copyright>=
Copyright (C) 2009 Filippo Erik Negroni

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>
----


Introduction
------------
Etangle collects and reorders _code snippets_ and writes them out into source code modules.

The code snippets Etangle looks for are embedded within the _listing blocks_ of an AsciiDoc document.


Embedding code snippets
~~~~~~~~~~~~~~~~~~~~~~~
An AsciiDoc listing block consists of any number of lines between two delimiters: the two delimiters are identical lines, usually four dashes, one at the beginning and one at the end of the block.

When rendering a document, AsciiDoc simply copies the contents of any listing block without any of the usual formatting: any content that might look like an AsciiDoc keyword will not be interpreted by AsciiDoc when rendering.

The listing block is therefore the ideal place where to embed code snippets, since AsciiDoc will still render the blocks correctly without the use of any eWEB tools.

For a listing block to be identified as an eWEB code snippet, the first line of content must be a WEB directive.


General requirements
--------------------
This is the first version of Etangle extracted from an eWEB document using the bootstrap version of Etangle.

The requirements are therefore the same as for the bootstrap version.

To produce one single source code module, unnamed, composed of all the code snippets, in the correct order.

The content of each code snippet is scanned for references to other code snippets, so that the correct order is produced.

We are also not concerned about various issues: scalability, performance, robustness.

The supported eWEB directives are:

. root code snippet definition-extension: `<*>=`
. named code snippet definition-extension: `<name>=`
. named code snippet reference: `<name>`


Overall strategy
----------------
Scan input for listing blocks, for each listing block, scan the first line for a recognised eWEB directive.

Only definition-extension directives (`<...>=`) are supported on the first line of a code snippet. Any spaces after `=` are ignored, but nothing else can follow `=` other than spaces and the newline character.

If we don't recognise the directive, we skip the listing block entirely.

If we do recognise the directive, we extract the name, which could be an asterisk `*` for the root code snippet, and we then associate the content of the snippet with its name.

If we encounter the same definition again, we extend it, not replace it. This behaviour will change later when we support re-definition and extension.

A code snippet might have reference directives within itself, but we do not resolve them until we have scanned the entire document and identified every snippet.

Once the document has entirely been scanned, and all code snippets been identified, we can then proceed to produce the output.

One output module
~~~~~~~~~~~~~~~~~
Since we only process one document and produce one source module, we are going to simply read the input document from standard input and write one source code module on standard output.

To write the output, we start writing the content of the root code snippet.

For each code snippet, including the root one, we resolve any reference directive and we proceed until all references are resolved.


Collecting code snippets
------------------------
The most appropriate data structure for the purpose of storing and retrieving code snippets by name is a *map*, which Python provides as a built in type. The accessor methods provided by the language are also sufficient for our purposes at this stage.

The `snippets` global identifier will contain all the code snippets, and will start life as an empty builtin dictionary type.

The `dict` type in Python provides the easiest way to code a map. It is also very basic and we need to keep this in mind for scalability and performance in the future.

A couple of notes about the built in `dict` type.

First, `dict` will replace the value associated to a key when a new assignment to the same key is made.

Second, trying to retrieve a non-existent key raises an exception.

To that effect, there exists a `defaultdict` type which will ensure we always match a key upon retrieval: a default value will be returned instead of an exception when a key we try to retrieve is missing from the map.


Internal representation of a code snippet
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
In order to use `defaultdict`, we need to establish the suitable default value.

To establish it, we must think of what type of values will be stored against a key in the map of code snippets.

When we retrieve the contents of a listing block, the result will be a collection of lines of text. In particular, most Python standard libraries deal with text on a line basis. Text files are accessed as collections of lines.

By storing the content of each code snippet as a collection of lines, such collection can be extended by the content of another code snippet with the same name.

We could therefore infer that the default value of a code snippet is an empty list.

----
<snippets-map-definition>=
snippets = collections.defaultdict(list)
----

To use `defaultdict` we must import the associated module.

----
<imports>=
import collections
----


Scanning for listing blocks
---------------------------
All eWEB documents are AsciiDoc documents with special embedded WEB directives inside listing blocks.

Therefore, every eWEB document is a text file: a collection of lines of text.

Python's standard library sees a text file in exactly this way, and the builtin types make dealing with AsciiDoc documents very easy, if not necessarily fast or scalable.

We also conveniently described that from a data abstraction point of view, each code snippet is a list of lines of text, with an associated name, all stored in a map.

When scanning for listing blocks, we are therefore going to try and keep the granularity at the text line level.

Just like in the bootstrap version, Etangle will only process one document. For simplicity, this document comes from the standard input.

This means we do not need to perform any file management operations such as opening and closing files.

`stdin` is available as a member of module `sys`, so we import it:

----
<imports>=
import sys
----

Scanning algorithm
~~~~~~~~~~~~~~~~~~
At first we scan each line until we find the beginning of a listing block: four dashes `----` in the default AsciiDoc configuration.

.AsciiDoc custom configuration
[NOTE]
==============================
AsciiDoc can be customised by the end user to the extent of modifying some of the markups. In particular, a user could modify which markup delimits a listing block.

Although the current version only supports the default markup, a future version will support either a command line option, or the ability to read the AsciiDoc configuration file.
===============================

When we enter a listing block, we must scan the first line.

If the first line is a recognised and allowed WEB directive, we analise the command and behave accordingly.

Unfortunately in Python, `readline()` and `__next__()` are mutually exclusive on the same file object.

To use the _for loop_ style iteration on a file (using `__next__()`), we must define a finite state automata, with a state variable that is used on each iteration to determine what to do next.

If we instead use `readline()`, we can make additional calls to it within the inner loops.

For simplicity, we will use the `readline()` approach.

----
<input-scan-loop>=
line = sys.stdin.readline()
while line:
    if line == '----\n':
        process_listing_block()
    line = sys.stdin.readline()
----

NOTE: scanning sys.stdin directly gives back lines with their newline. input() on the other hand returns lines without the newline character at the end.

`process_listing_block()` is responsible for scanning the block and determine if it's a snippet.

To qualify as an eWEB code snippet, the first line of the listing block must be an allowed WEB directive.

These are expressed very formally using regular expressions, but can be summarised as having a name part (which can be empty) in between angle brackets (`<` and `>`) and an additional character which determines the action to perform.

Etangle, in this version, only supports the definition-extension directive, which is identified by having the single equal sign at the end (`=`).

So the regular expression in Python becomes:

----
<web-definition-extension-directive-regex>=
WEB_DEFINITION_EXTENSION = r'''^<(\*|[-\w]+)>=\s*$'''
----

If the first line matches a WEB definition-extension directive, we save the name of the snippet, we save the lines that follow (zero or more) in a collection until we see the end of the listing block, at which point we add the snippet to the map.

----
<process_listing_block-definition>=
def process_listing_block():
    <web-definition-extension-directive-regex>
    line = sys.stdin.readline()
    m = re.match(WEB_DEFINITION_EXTENSION,line)
    if not m:
        return
    name = m.group(1)
    lines = []
    line = sys.stdin.readline()
    while line and line != '----\n':
        lines.append(line)
        line = sys.stdin.readline()
    snippets[name].extend(lines)
----

NOTE: The assumption is that `snippets` is a `defualtdict`: in the code, we try and extend a code snippet, assuming it is already present in the map. `snippets` will create a new key with an empty list as its value when we try to extend a non existing snippet.

We must import the regular expression module for `process_listing_block()` to work.

----
<imports>=
import re
----


Output
------
Once the input has been processed by the input scanning loop routine, we can start printing the code snippets in the correct order, starting from the _root_ snippet, identified by its name, an `*` (asterisk).

Remember that our snippets dictionary succeeds when looking for snippets that don't exist, essentially returning empty lists for them.

The nature of printing code snippets is recursive:

Each line in a code snippet must be analysed.

If the line is a reference directive, we must retrieve the referenced code snippet and recursively resolve any references with it.

If a line is *not* a code snippet, we just print it.

To this effect, we can define a general routine called `print_snippet` which will recursively take care of printing each snippet contents and resolve any references.

The spaces preceding the reference are used to indent the referenced snippet. In a recursive reference, the indentation must be summed up.

Given such a routine, emitting the output resolves to printing the _root_ snippet `*`, with no indentation.

----
<emit-output>=
print_snippet('*', '')
----

----
<print_snippet-definition>=
def print_snippet(name,indent):
    for line in snippets[name]:
        <web-reference-directive-regex>
        m = re.match(WEB_REFERENCE,line)
        if not m:
            sys.stdout.write(indent+line)
            continue
        print_snippet(m.group(2),indent+m.group(1))
----

A WEB reference directive is a line where a code snippet name is delimited by angle brackets, and appears on its own, optionally preceded by spaces. The spaces in front of the reference *are* important: they will be used to indent the content of every line contained in the referenced snippet. And this indentation will recursively apply to any snippet referenced by it.

Within the regular expression we save the spacing in front of the first angle bracket as a group, so that we can use its content as indentation.

----
<web-reference-directive-regex>=
WEB_REFERENCE = r'''^(\s*)<([-\w]+)>\s*$'''
----

We must import the regular expression module in order to identify each line.

----
<imports>=
import re
----


Sha Bang and Copyright
----------------------
In order to allow our Python program to work as an executable file, we must add the traditional shabang line at the beginning.

We assume Python3 is installed and accessible from the environment's PATH.

----
<shabang>=
#!/usr/bin/env python3
----

We also want the copyright to be shown in the final module so that it can be printed too.

----
<module-copyright>=
_copyright = '''\
etangle - tangles embedded WEB code snippets within asciidoc literate programs.
<copyright>
'''
----

etangle.py
----------
A simple Python script will incorporate all the elements we defined in the previous sections in the correct order:

----
<*>=
<shabang>

<module-copyright>

<imports>

<snippets-map-definition>

<process_listing_block-definition>

<print_snippet-definition>

<input-scan-loop>

<emit-output>
----
