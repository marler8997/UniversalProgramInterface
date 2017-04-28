UPI (Universal Program Interface )
================================================================================
UPI is an interface that aims to provide universal sharing of program
functionality.



Examples
--------------------------------------------------------------------------------

#### Describe the contents of a directory or a repository.
- what do the files do?
- if they need to be built, how do you build them?
- what functionality do they depend on?
    note: when having a dependency, they will depend on upi functionality, not
          necessarily other repos.

For example, say you had a repository with some `c++` code that is meant to
be used as a library, either static or dynamic. UPI might look something like:
```
Repository
{
  CppLibrary
  {
    InterfaceHeaders inc/*.h
    SourceFiles src/*.cpp
  }
}
```

The word "CppLibrary" would allow compilers to know what this repo contains.
It also has properties such as InterfaceHeaders and SourceFiles that compilers
can use to know where the source code lives, and also allows libraries that
may want to use this library to know where the header files are.

The hope is that a tool like a compiler could use this UPI file to be able to
build this library.  And note that this UPI file contains much less information
than say a Makefile would.  UPI attempts to describe what something is whereas
a Makefile describes how to produce outputs from inputs.  This allows files
that have a UPI description to be freely interacted with any number of tools
which could be compilers, test frameworks, analysis tools, etc.  A UPI isn't
a hard mapping to a set of steps to produce something, it is a description
using shared interfaces that allows any tool to know what it can do with
the objects.

Lets explore what a compiler interface might look like. Compilers have alot
of functionality and expose complex interfaces that interact with many peices
of the environment.  Many common compilers use a command-line interface, so
this example will assume the same, however this doesn't have to be the case.

> I imagine a compiler could define a UPI interface which tools can read
> to generate code that allows programs to pass this information to the
> compiler and also generates code that the compiler can use to read this
> information as well.  It could also generate code that accepts multiple
> types of interfaces simultaneously.

For sake of simplicity we'll assume a very simple compiler.  It accepts
the names of source files on the command line, it reads the environment
to get the current directory to know where to search for relative file
names, and then produces binary output.
```
CppCompiler
{
    // Note: the CppCompiler definition implies certain properties
    //       for example, it implies that it takes CppSource files
    //       as an input
    InvokeInterface
    {
        CommandLine
        {
            Name cppc
        }
    }
}
```





>  Note: I like that using '{' and '}' for blocks make it easy to type and looks clean, however
>        it has a drawback when you have large nested blocks and it's hard to tell where certain
>        blocks end.  Something like XML has an advantage in these cases. A good comprimise could
>        be to allow close '}' to be affixed with their start tags like this `}Tag`.

Shared UPI Databases
--------------------------------------------------------------------------------
Any UPI file that is meant to be shared, should have a URL associated with it
in order to obtain the location where it lives.  The URL could point to a
file on an HTTP server, or could be a git repository, etc.  In order for a
UPI to reference another UPI file, it must specify the URL of where the
referenced UPI file lives.

#### How to find UPI files

I think debian/ubuntu's aptitude program uses a good technique.  They allow you
to add/remove repositories of packages.  You could do the same with UPI
repositories. For example,
```
# The UPI respository containing all standard UPI files
http://github.com/upi/std
# A personal UPI repository containing some personal UPI assets
http://github.com/myuser/mycoolupistuff
```
These repositories are downloaded and then UPI can use them.  They should be
manageable through the command line,i.e.
```
> upi add http://github.com/myuser/mycoolupistuff
> upi remove http://github.com/myuser/mycoolupistuff
```


Thoughts About UPI File Assets like binaries and configuration paths
--------------------------------------------------------------------------------
There will probably be a single directory, call it the "install directory"
where the upi files and binaries live.

This directory will also hold ALL the tools that UPI downloads like
compilers and the like.  Note that some tools may use files that don't
live inside the UPI directory, but they will be discoverable from something
inside the upi install directory.

So "system-wide" resources will go into the "install directory".  There can
also be "user-specific" resources which should allow configuration to
be shared accross systems for a specific user.   I believe these resources
will also go into the install directory.

I also anticipate that you can have "user-repository" specific configuration.
For example, say you want to use a particular compiler with a particular
set of configuration for a git repo containing a library.  Those settings
can be saved somewhere in the "install directory" and shared accross systems.


Notes and Thoughts
--------------------------------------------------------------------------------
* Source Code should be able to specify a minimum version, like c99 or c++11,
  etc.
* A git repository may have specified a path to ignore for generated files, i.e.
  the "bin" directory should be ignored.  UPI should provide a way for a
  repository to specify this information.
* UPI can describe source or binaries. When a compiler is called on source, it
  can generate binaries but something should also be able generate a new UPI
  for the new binary.  This new UPI will contain all the information about the
  generated binary such as what platform it can run on.  It will also contain
  information about the tool that was taken from the original source UPI.

  This means that a compiler will need a UPI that contains information about
  what it generates. That way when a tool invokes the compiler using it's UPI
  interface, the tool will also be able to generate the new UPI for the compiled
  binary.
* A global UPI registry.  A place where tools can be registered.  Say someone is
  looking for a compiler, you can look one up in the UPI registry.  The entry
  should contain a url to download the tools.  This could also be used for an
  automated test suite.  You could use the registry to look up all compilers for
  your code and automatically build the code using all the tools that are
  registered to work on your platform.
