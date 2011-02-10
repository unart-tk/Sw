#!/usr/bin/env python3

_copyright = '''\
etangle - tangles embedded WEB code snippets within asciidoc literate programs.
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
'''

import collections
import sys
import re
import re

snippets = collections.defaultdict(list)

def process_listing_block():
    WEB_DEFINITION_EXTENSION = r'''^<(\*|[-\w]+)>=\s*$'''
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

def print_snippet(name,indent):
    for line in snippets[name]:
        WEB_REFERENCE = r'''^(\s*)<([-\w]+)>\s*$'''
        m = re.match(WEB_REFERENCE,line)
        if not m:
            sys.stdout.write(indent+line)
            continue
        print_snippet(m.group(2),indent+m.group(1))

line = sys.stdin.readline()
while line:
    if line == '----\n':
        process_listing_block()
    line = sys.stdin.readline()

print_snippet('*', '')
