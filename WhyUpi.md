Why UPI
================================================================================
The worst part about sitting at a new computer is setting up your environment
and installing all your software. UPI can make this process easier.

Software comes in many different forms. It can be an os-specific binary
compiled for a specific processor, a script that requires an interpreter, or a
large set of files/binaries/libraries. If you push this definition you could
even say that something like a configuration file is really just "software" that
"depends on" the program that uses it.

Every program must solve the problem of platform/environment/os dependencies.
UPI can be used to explicitly declare these dependencies so that other programs
can be used to interact with it properly. For example, you may have a binary
copy of photoshop that runs on windows and another that runs on linux.  The
UPI file will indicate which binary runs on which OS so that a program can be
used to select the right one. Some examples of properties that software should
be able to specify include:

* Dependencies
   - Shared Runtime Library Dependencies
   - Other Software Dependencies
* Download Locations
   - Binary Downloads
   - Source Downloads
* Platform Support

UPI is the fabric that allows software to specify this information in a format
that can be understand by any program.

The next thing to consider is how to specify what software we want. This
requires a universal way of identifying software. Software must
be searchable using various criteria such as:

* Organization (i.e. adobe, microsoft, ...)
* Type (i.e. "photo editor", "compiler", ...)
* Name (i.e. "photoshop", "visual studio", ...)



