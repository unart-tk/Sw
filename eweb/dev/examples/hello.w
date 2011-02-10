Hello World
===========

Example program to test `etangle.py`.

Hello
-----

The basic hello world in C:

----
<main>=
int
main(void)
{
    <print-hello-world-message>
    return 0;
}
----

To print, we use printf:

----
<print-hello-world-message>=
printf("Hello, World\n");
----

To declare printf, use stdio.h:

----
<includes>=
#include <stdio.h>
----


The final program
-----------------

Hello.c:

----
<*>=
<includes>

<main>
----
