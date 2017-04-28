
UPI Syntax
================================================================================
For UPI I want the syntax to remain independent of the big picture concepts.
The syntax is an independent venture, and a venture whose design shouldn't affect
the concept of UPI, however, in practicality syntax is the way developers
will interface with UPI so it is very important.

This document will contain my initial thoughts and design of the syntax for UPI,
however, all designs are subject to change.  I will attempt to detail the
decisions and reasons for each decision so that any changes will be made with
the appropriate background knowledge.

Code Normalization vs Flexibility
--------------------------------------------------------------------------------
I've come to learn that code normalization is very important when it comes to
large projects and interoperability.  It's very jarring for people to maintain
code with different styles even if they are in the same langauge.
Too much flexibility leads to disparate code bases that makes them difficult to
coexist together.  Flexibility in itself is a good thing, but there are times
when more of it provides little to no benefit while opening the door to
code that can looks like it's written in another language.

Whitespace with Semantic Meaning
--------------------------------------------------------------------------------
I don't know python but I do know that it uses whitespace to provide semantic
meaning such as delimiting what's inside a block.  This is different from many
mainstream languages which turns off some developers but there are clear
benefits that promote code normalization.

Tabs vs Spaces
--------------------------------------------------------------------------------
For now UPI will use 1 tab for indentation.  Spaces at the beginning of a line
will be syntax errors. Here's a list of reasons for this:

* less options, i.e. 2 spaces vs 3 spaces vs 4 spaces vs 8 spaces etc.
* less opportunity for developer mistakes where some lines may have a few too
  many or too little spaces
* editors can adjust their tab width to the developers preference without
  having to modify the code itself
* 1 tab takes up less characters than N spaces

One disadvantage is alignment when it comes to multiple lines.  Say you had
the following:
```
SomeProperty a
             b
             c
```
I think in the cases where you want to have alignment between multiple lines,
you should use spaces for that alignment.  I'll have to think on this more.

Newlines
--------------------------------------------------------------------------------
For now I'm going to require newlines to be '\n' while making the '\r'
character a syntax error.