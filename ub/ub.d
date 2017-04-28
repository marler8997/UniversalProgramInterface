module ub;

import core.stdc.string : memmove, strlen;

import std.stdio;
import std.array  : Appender, appender;
import std.getopt : getopt;
import std.file   : SpanMode, DirEntry, dirEntries, getcwd, isDir, mkdir, exists;
import std.format : format, sformat;

import more.io;
import more.format : Escaped;

import upi.parser;
import ubnormalize : normalizeUpiFile;

class SilentException : Exception
{
    this()
    {
        super(null);
    }
}

void getUpiFiles(T)(T sink, const(char)[] directory = getcwd())
{
    foreach(entry; dirEntries(cast(string)directory, "*.upi", SpanMode.shallow))
    {
        if(entry.isFile)
        {
            sink.put(entry);
        }
        else if(entry.isDir)
        {
            writefln("Error: directory '%s' ends in .upi but this doesn't mean anything right now", entry.name);
            throw new SilentException();
        }
        else
        {
            writefln("Error: file '%s' ends in .upi but is neither a normal file or directory", entry.name);
            throw new SilentException();
        }
    }
}

version(Windows)
{
    enum defaultRepository = r"C:\UpiRepository";
}
else
{
    enum defaultRepository = "/home/upi";
}
string repositoryDir = defaultRepository;

void loadRepository(ExpandableGCBuffer!char sharedFileBuffer)
{
    writefln("Loading repository \"%s\"", repositoryDir);

    if(!exists(repositoryDir))
    {
        writefln("Created repository \"%s\"", repositoryDir);
        mkdir(repositoryDir);
    }

    auto upiFiles = appender!(DirEntry[])();
    getUpiFiles(upiFiles, repositoryDir);

    writefln("Repository \"%s\" has %s upi file(s)", repositoryDir, upiFiles.data.length);

    foreach(upiFileEntry; upiFiles.data)
    {
        writefln("[DEBUG] loading \"%s\"", upiFileEntry.name);
        File file = File(upiFileEntry, "r");
        UpiFile upiFile;
        parseDirectives(upiFileEntry.name, file, &upiFile, sharedFileBuffer);
    }
}

void usage()
{
    writeln("Usage: ub [-options] <command>");
    writeln(" <command>");
    writeln("    install <upi-file>");
    writeln("    normalize | norm <upi-files>...");
    writeln(" Options:");
    writefln("   -r <repo>   Override the default repository \"%s\"", defaultRepository);
}

void dumpStack(void* p)
{
    writefln("stack variable address 0x%x", p);
    const(uint)* wordPtr = cast(uint*)p;
    for(int i = 0; i < 20 ;i++)
    {
        writefln("0x%x 0x%08x", wordPtr + i, *(wordPtr+i));
    }
    stdout.flush();
}

int main(string[] args)
{
    try
    {
        bool help = false;
        getopt(args,
            "h", &help,
            "r", &repositoryDir);
        if(help)
        {
            usage();
            return 0;
        }
        args = args[1..$];
        if(args.length == 0)
        {
            usage();
            return 0;
        }

        string command = args[0];
        if(command == "install")
        {
            foreach(upiFile; args[1..$])
            {
                writefln("TODO: need to install \"%s\"", upiFile);
            }
        }
        else if(command == "normalize" || command == "norm")
        {
            //auto sharedBuffer = expandable(new char[2000]);
            auto sharedBuffer = expandable(new char[10]);
            foreach(upiFile; args[1..$])
            {
                normalizeUpiFile(upiFile, &sharedBuffer);
            }
        }
        else if(command == "validate")
        {
            //auto sharedBuffer = expandable(new char[2000]);
            auto sharedBuffer = expandable(new char[10]);
            loadRepository(sharedBuffer);

            auto upiFiles = appender!(DirEntry[])();
            getUpiFiles(upiFiles);

            if(upiFiles.data.length == 0)
            {
                writefln("Error: there are no upi files in this directory");
                return 1;
            }

            writefln("Found %s upi file(s):", upiFiles.data.length);
            foreach(upiFileEntry; upiFiles.data)
            {
                writefln("  %s", upiFileEntry.name);
                File file = File(upiFileEntry, "r");
                UpiFile upiFile;
                parseDirectives(upiFileEntry.name, file, &upiFile, sharedBuffer);
            }
        }
        else
        {
            writefln("unknown command \"%s\"", command);
            return 1;
        }

        stdout.flush();
        return 0;
    }
    catch(SilentException)
    {
        return 1;
    }
}

struct DirectiveState
{
    string name;
    void delegate(UpiDelegateParser!char* parser, const(char)[] property) propertyHandler;
    void delegate(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState) subDirectiveHandler;
    void reset()
    {
        this.name = null;
        this.propertyHandler = null;
        this.subDirectiveHandler = null;
    }
    void set(UpiDirectiveClass obj)
    {
        this.name = obj.name;
        this.propertyHandler = &obj.handleProperty;
        this.subDirectiveHandler = &obj.handleDirective;
    }
}

struct DefaultUpiBuilder
{
    DirectiveState currentDirective;
    bool currentDirectiveFinishedProperties;
    this(UpiFile* upiFile)
    {
        this.currentDirective.subDirectiveHandler = &upiFile.handleDirective;
    }
    void handle(UpiDelegateParser!char* parser, UpiParserEvent event, UpiParseEventArg arg)
    {
        final switch(event)
        {
            case UpiParserEvent.startDirective:
                if(currentDirective.subDirectiveHandler == null)
                {
                    throw parser.fatal("directive '%s' does not support any sub-directives", currentDirective.name);
                }

                // call property handler with null to mark no more properties
                // if it has not been called yet and it has a property handler
                if(!currentDirectiveFinishedProperties)
                {
                    currentDirectiveFinishedProperties = true;
                    if(currentDirective.propertyHandler != null)
                    {
                        currentDirective.propertyHandler(parser, null);
                    }
                }

                {
                    auto saveDirective = this.currentDirective;
                    scope(exit) this.currentDirective = saveDirective;

                    this.currentDirective.reset();
                    saveDirective.subDirectiveHandler(parser, arg.string, &currentDirective);
                    if(this.currentDirective.name is null)
                    {
                        throw parser.fatal("unhandled directive '%s' (parent=\"%s\")", arg.string, saveDirective.name);
                    }
                    currentDirectiveFinishedProperties = false;
                    parser.parse();
                }
                break;
            case UpiParserEvent.property:
                if(currentDirective.propertyHandler == null)
                {
                    throw parser.fatal("directive '%s' does not support any properties", currentDirective.name);
                }
                currentDirective.propertyHandler(parser, arg.string);
                break;
            case UpiParserEvent.endDirectives:
                assert(0, "did not expect the endDirectives event");
        }
    }
}

void printAndExit(string errorMessage, string filename, uint lineNumber)
{
    writefln("%s(%s) %s", filename, lineNumber, errorMessage);
    throw new SilentException();
}

/*
 TODO: the FileExt type is a workaround.
       what I'd really like to be able to do is create the following function:

size_t rawReadReturnSize(T)(ref File file, T[] buffer)
{
    return file.rawRead(buffer).length;
}

And then get a delegate for it like this:

&file.rawReadReturnSize

But this depends on my idea "UFCS converts to delegate".
*/
struct DummyFileType
{
    size_t rawReadReturnSize(T)(T[] buffer)
    {
        auto this_ = cast(File*)&this;
        return this_.rawRead!T(buffer).length;
        return 0;
    }
}
auto extensionDelegate(alias DummyType, string methodName, T)(T obj)
{
    DummyType dummy;
    mixin("auto delegate_ = &dummy."~methodName~";");
    delegate_.ptr = obj;
    return delegate_;
}

void parseDirectives(string filename, File file, UpiFile* upiFile, ExpandableGCBuffer!char sharedBuffer)
{
    auto parser = UpiDelegateParser!char();

    //auto dg = extensionDelegate!(FileExt, rawReadReturnSize)(file);
    auto reader = DelegateLinesReader((&file).extensionDelegate!(DummyFileType, q{rawReadReturnSize!char}),
        sharedBuffer.buffer, &sharedBuffer.expand, 150);
    parser.reader = &reader.readLines;
    auto builder = DefaultUpiBuilder(upiFile);
    parser.handler = &builder.handle;
    parser.errorHandler = &printAndExit;
    parser.filenameForErrors = filename;

    parser.lineNumber = 1;

    parser.parse();

    assert(file.eof, "the parser did not read the whole file");
}

struct UpiFile
{
    Appender!(CommandLineProgram[]) commandLinePrograms;
    Appender!(Task[]) tasks;
    void handleDirective(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState)
    {
        if(directiveName == "CommandLineProgram")
        {
            subDirectiveState.set(new CommandLineProgram());
        }
        else if(directiveName == "Task")
        {
            subDirectiveState.set(new Task());
        }
    }
}

// Not all upi directives need to be classes, but for those
// that are, they can use this as a base class
class UpiDirectiveClass
{
    string name;
    this(string name)
    {
        assert(name);
        this.name = name;
    }
    auto duplicateSubDirectives(UpiDelegateParser!char* parser, const(char)[] subDirectiveName)
    {
        return parser.fatal("the '%s' directive may only have 1 '%s' sub-directive", name, subDirectiveName);
    }
    void handleProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        throw parser.fatal("the '%s' directive does not support any properties", name);
    }
    void handleDirective(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState)
    {
        throw parser.fatal("directive '%s' does not support any sub-directives", name);
    }
}
class CommandLineProgram : UpiDirectiveClass
{
    string programName;
    Source source;
    Appender!(ImplementsTask[]) implementedTasks;
    this() { super("CommandLineProgram"); }
    override void handleProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(property is null) // no more properties
        {
            if(programName is null) throw parser.fatal("CommandLineProgram requires a name");
        }
        else
        {
            if(programName) throw parser.fatal("CommandLineProgram only supports 1 property");
            programName = property.idup;
        }
    }
    override void handleDirective(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState)
    {
        if(directiveName == "Source")
        {
            if(source) throw duplicateSubDirectives(parser, directiveName);
            source = new Source();
            subDirectiveState.set(source);
        }
        else if(directiveName == "ImplementsTask")
        {
            auto directive = new ImplementsTask();
            implementedTasks.put(directive);
            subDirectiveState.set(directive);
        }
    }
}
class ImplementsTask : UpiDirectiveClass
{
    string name;
    string category;
    this() { super("ImplementsTask"); }
    override void handleProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(property is null) // no more properties
        {
            if(name is null) throw parser.fatal("ImplementsTask requires a name");
        }
        else
        {
            if(name) throw parser.fatal("ImplementsTask only supports 1 property");
            name = property.idup;
        }
    }
    override void handleDirective(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState)
    {
        if(directiveName == "Category")
        {
            subDirectiveState.name = "Category";
            subDirectiveState.propertyHandler = &handleCategoryProperty;
        }
    }
    void handleCategoryProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(category) throw parser.fatal("The Category directive only supports 1 property");
        category = property.idup;
    }
}

class Task : UpiDirectiveClass
{
    string name;
    string description;
    string category;
    Appender!(InputParameter[]) inputParameters;
    string outputFile;
    this()
    {
        super("Task");
    }
    override void handleProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(property is null) // no more properties
        {
            if(name is null) throw parser.fatal("Task requires a name");
        }
        else
        {
            if(name) throw parser.fatal("Task only supports 1 property");
            name = property.idup;
        }
    }
    override void handleDirective(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState)
    {
        if(directiveName == "Description")
        {
            subDirectiveState.name = "Description";
            subDirectiveState.propertyHandler = &handleDescriptionProperty;
        }
        else if(directiveName == "Category")
        {
            subDirectiveState.name = "Category";
            subDirectiveState.propertyHandler = &handleCategoryProperty;
        }
        else if(directiveName == "InputParameter")
        {
            auto directive = new InputParameter();
            inputParameters.put(directive);
            subDirectiveState.set(directive);
        }
        else if(directiveName == "OutputFile")
        {
            if(outputFile) throw duplicateSubDirectives(parser, directiveName);
            subDirectiveState.name = "OutputFile";
            subDirectiveState.propertyHandler = &handleOutputFileProperty;
        }
    }
    void handleDescriptionProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(description) throw parser.fatal("The Description directive only supports 1 property");
        description = property.idup;
    }
    void handleCategoryProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(category) throw parser.fatal("The Category directive only supports 1 property");
        category = property.idup;
    }
    void handleOutputFileProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(property is null) // no more properties
        {
            if(!outputFile) throw parser.fatal("OutputFile requires a property");
        }
        else
        {
            if(!outputFile) outputFile = property.idup;
            else throw parser.fatal("OutputFile only supports 1 property");
        }
    }
}
class InputParameter : UpiDirectiveClass
{
    string name;
    string type;
    this() { super("InputParameter"); }
    override void handleProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(property is null) // no more properties
        {
            if(name is null) throw parser.fatal("InputParameter requires a name and type");
            if(type is null) throw parser.fatal("InputParameter requries a type");
        }
        else
        {
            if(name is null) name = property.idup;
            else if(type is null) type = property.idup;
            else throw parser.fatal("InputParameter only supports 2 properties");
        }
    }
}

class Source : UpiDirectiveClass
{
    string language;
    Appender!(string[]) fileSpecifiers;
    this()
    {
        super("Source");
    }
    override void handleDirective(UpiDelegateParser!char* parser, const(char)[] directiveName, DirectiveState* subDirectiveState)
    {
        if(directiveName == "Language") {
            subDirectiveState.name = "Language";
            subDirectiveState.propertyHandler = &handleLanguageProperty;
        } else if(directiveName == "Files") {
            subDirectiveState.name = "Files";
            subDirectiveState.propertyHandler = &handleFilesProperty;
        }
    }
    void handleLanguageProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        if(language) throw parser.fatal("The Language directive only supports 1 property");
        language = property.idup;
    }
    void handleFilesProperty(UpiDelegateParser!char* parser, const(char)[] property)
    {
        fileSpecifiers.put(property.idup);
    }
}