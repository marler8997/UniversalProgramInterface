module upi.parser;

static import core.stdc.stdlib;
import core.stdc.string : strlen;

import std.stdio     : File, writeln, writefln;
import std.string    : format;
import std.array     : Appender;

import more.io;
import more.format : CStringEscaped, Escaped;
import more.utf8;

class UpiParseException : Exception
{
    this(string errorMessage, string filename, uint lineNumber)
    {
        super(errorMessage, filename, lineNumber);
    }
}
    
/*
 Exporation of space-efficient UPI Memory Layout

   string name            | ptr      |---------> |name chars|
                          | length   |    | OR
                         [|name chars|]<---
   ushort propertyCount   |          |
                             ???
                             ...
   size_t childrenCount   |          |


*/

union UpiParseEventArg
{
    const(char)[] string;
    uint count;
    this(const(char)[] string)
    {
        this.string = string;
    }
    this(uint count)
    {
        this.count = count;
    }
}

enum UpiParserEvent
{
    startDirective, // takes a string
    property,       // takes a string
    endDirectives,  // takes a uint
}

// The default upi parser just uses delegate.
// By defining a default one it promotes shared usage which
// reduces template bloat.
alias UpiDelegateParser(CharType) = UpiTemplateParser!(LinesReaderDelegate!CharType);

template UpiTemplateParser(R)
{
    Exception stdoutErrorHandler(UpiTemplateParser* parser, const(char)[] errorMessage)
    {
        if(parser.filenameForErrors)
        {
            writefln("%s(%s) Error: %s", parser.filenameForErrors,
                parser.lineNumber, errorMessage);
        }
        else
        {
            writefln("Error line %s: %s", parser.lineNumber, errorMessage);
        }
        return null;
    }
    alias HandlerDelegate = void delegate(UpiTemplateParser*,UpiParserEvent,UpiParseEventArg);
    struct UpiTemplateParser
    {
        uint directiveDepth;
        const(char)* parsePtr;
        uint tabDepth;

        // Used to know whether or not the handler has
        // called the parse function again
        uint recursiveDepth;

        uint lineNumber;

        R reader;

        // I haven't figured out a way to templatize the handler type because
        // right now it's defined as a callback delegate that has the UpiTemplateParser
        // as the first parameter, but if the handler type is a template parameter then this
        // results in a recursive template definition.  So for now I just make it a 
        // delegate.
        HandlerDelegate handler;

        string filenameForErrors;
        void function(string errorMessage, string filename, uint lineNumber) errorHandler;

        // Even though this function will not return, it's return
        // value is an exception so that the caller can call throw
        // which helps control flow know that an exception will be thrown
        // at the caller site.
        UpiParseException fatal(T...)(string message)
        {
            if(errorHandler)
            {
                errorHandler(message, filenameForErrors, lineNumber);
            }
            throw new UpiParseException(message, filenameForErrors, lineNumber);
        }
        UpiParseException fatal(T...)(string fmt, T obj) if(T.length > 0)
        {
            return fatal(format(fmt, obj));
        }
        UpiParseException tooManyTabsError(uint max, uint actual)
        {
            return fatal("expected up to %s tab(s) on this line but got %s", max, actual);
        }

        /*
         Note: if continueParse is called recursively after startDirective, then the
               parser MUST NOT send the endDirective event.  This is because the handler
               will already know that the directive has ended.  Furthermore, it makes it easier
               on the handler because it will have the same stack context that it had
               when it received the startDirective event.
        */

    /+
        // The parse function can either be called once or it can be called
        // recursively inside the handler function callback.
        // For now the only times I can see this would be useful is during the
        // startDirective or property events.
        // This is possible because all the parser state is saved in the struct,
        // so if the handler needs to store things on the stack, it can call parse
        // instead of returning.
    +/

        // we are either at
        // 1) the start of the lin
        // 2) the end of the directive name
        void parse()
        {
            uint currentDirectiveChildDepth = 0;
            recursiveDepth++;
            //writefln("[DEBUG] recursiveDepth=%s, directiveDepth=%s", recursiveDepth, directiveDepth);
            if(recursiveDepth > 1)
            {
                currentDirectiveChildDepth = directiveDepth;
                goto AFTER_DIRECTIVE_NAME;
            }

          CHUNK_LOOP:
            while(true)
            {
                // read the next chunk
                {
                    auto nextLinesChunk = reader();
                    if(nextLinesChunk.length == 0)
                    {
                        break;
                    }
                    // TODO: after parsePtr detects '\0', need to make sure
                    //       that it is pointing to the end of the linext chunk,
                    //
                    //       i.e. parsePtr == nextLinesChunk.ptr + nextLinesChunk.length
                    //
                    //       if this fails then it means that the file contains NULL characters
                    //

                    parsePtr = nextLinesChunk.ptr;
                    assert(parsePtr[nextLinesChunk.length] == '\0', "readLines function did not terminate lines with NULL");
                }

              LINE_LOOP:
                while(true) // loop through each line
                {
                    tabDepth = parseTabDepth(&parsePtr);
                  AFTER_PARSE_TAB:
                    if(tabDepth > directiveDepth)
                        throw fatal("expected up to %s tab(s) on this line but got %s", directiveDepth, tabDepth);
                    if(tabDepth < currentDirectiveChildDepth)
                    {
                        break CHUNK_LOOP;
                    }
                    // restore the depth of the recursive directive
                    if(tabDepth < directiveDepth)
                    {
                        handler(&this, UpiParserEvent.endDirectives, UpiParseEventArg(directiveDepth-tabDepth));
                    }
                    directiveDepth = tabDepth + 1;

                    {
                        auto directiveName = parseAlphaNumeric(&parsePtr);
                        if(directiveName.length == 0)
                        {
                            if(*parsePtr == '\0') {
                                throw fatal("line is empty");
                            }
                            if(*parsePtr == ' ') {
                                throw fatal("lines cannot begin with the space ' ' (0x20) character");
                            }
                            throw fatal("expected a directive but got \"%s\"", CStringEscaped(parsePtr));
                        }

                        uint saveRecursiveDepth = recursiveDepth;
                        handler(&this, UpiParserEvent.startDirective, UpiParseEventArg(directiveName));
                        if(recursiveDepth > saveRecursiveDepth)
                        {
                            recursiveDepth = saveRecursiveDepth; // restore the recursive depth
                            if(*parsePtr == '\0') break LINE_LOOP;
                            goto AFTER_PARSE_TAB;
                        }
                    }
                  AFTER_DIRECTIVE_NAME:
                    while(true)  // loop through properties
                    {
                        if(*parsePtr == '\0') break LINE_LOOP;
                        if(*parsePtr == '\n')
                        {
                            lineNumber++;
                            parsePtr++;
                            break;
                        }
                        if(*parsePtr != ' ')
                        {
                            if(*parsePtr == '\r')
                                throw fatal("upi files cannot contain carriage returns '\\r'");
                            throw fatal("expected a space ' ' to seperate properties but got \"%s\"", CStringEscaped!"\n"(parsePtr));
                        }
                        parsePtr++;
                        auto property = parseProperty(&parsePtr);
                        if(property.length == 0)
                        {
                            throw fatal("expected an alpha-numeric property but got \"%s\"", CStringEscaped!"\n"(parsePtr));
                        }
                        handler(&this, UpiParserEvent.property, UpiParseEventArg(property));
                    }
                }
            }

            // if we are at the top level,
            if(currentDirectiveChildDepth == 0)
            {
                if(directiveDepth)
                {
                    handler(&this, UpiParserEvent.endDirectives, UpiParseEventArg(directiveDepth));
                }
            }
            else
            {
                // restore the original depth
                auto extraDepth = directiveDepth - currentDirectiveChildDepth;
                if(extraDepth)
                {
                    handler(&this, UpiParserEvent.endDirectives, UpiParseEventArg(extraDepth));
                }
                directiveDepth = currentDirectiveChildDepth - 1;
            }
        }
    }
}

class UpiNodeClass
{
    string name;
    string[] properties;
    UpiNodeClass[] children;
    this(string name = null, string[] properties = null, UpiNodeClass[] children = null)
    {
        this.name = name;
        this.properties = properties;
        this.children = children;
    }
    bool equals(UpiNodeClass other)
    {
        if(this is other) return true;
        if(this.properties.length != other.properties.length) return false;
        if(this.children.length != other.children.length) return false;
        if(name != other.name) return false;
        foreach(i; 0..properties.length)
        {
            if(properties[i] != other.properties[i]) return false;
        }
        foreach(i; 0..children.length)
        {
            if(!children[i].equals(other.children[i])) return false;
        }
        return true;
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        if(name)
        {
            sink(name);
        }
        else
        {
            sink("<no-name>");
        }
        foreach(prop; properties)
        {
            sink(" ");
            sink(prop);
        }
        if(children.length)
        {
            sink("{");
            foreach(child; children)
            {
                child.toString(sink);
            }
            sink("}");
        }
    }
}

struct UpiSimpleGCBuilder(CharType)
{
    Appender!(UpiNodeClass[]) nodes;

    Appender!(UpiNodeClass[]) currentNodeStack;
    UpiNodeClass currentNode;

    void handle(UpiDelegateParser!CharType* parser, UpiParserEvent event, UpiParseEventArg arg)
    {
        final switch(event)
        {
            case UpiParserEvent.startDirective:
                writefln("[DEBUG] startDirective \"%s\"", arg.string);
                if(currentNode) currentNodeStack.put(currentNode);
                currentNode = new UpiNodeClass(arg.string.idup);
                break;
            case UpiParserEvent.property:
                writefln("[DEBUG] property \"%s\"", arg.string);
                assert(currentNode !is null);
                currentNode.properties ~= arg.string.idup;
                break;
            case UpiParserEvent.endDirectives:
                for(int i = 0; i < arg.count; i++)
                {
                    writefln("[DEBUG] endDirective");
                    assert(currentNode !is null);
                    if(currentNodeStack.data.length == 0)
                    {
                        nodes.put(currentNode);
                        currentNode = null;
                    }
                    else
                    {
                        auto newLength = currentNodeStack.data.length-1;
                        auto popNode = currentNodeStack.data[newLength];
                        currentNodeStack.shrinkTo(newLength);
                        popNode.children ~= currentNode;
                        currentNode = popNode;
                    }
                }
                break;
        }
    }
    void enforceDone()
    {
        if(currentNode !is null)
            throw new Exception("parser has finished but there is still directive that has not been ended");
        if(currentNodeStack.data.length > 0)
            throw new Exception("code bug: currentNode is null but there are nodes on the stack");
    }
    /*
    static void handleFunction(void* parser, UpiParserEvent event, UpiParseEventArg arg)
    {
        (cast(UpiSimpleGCBuilder*)parser.handlerObject).handle(cast(UpiDelegateParser)parser, event, arg);
    }
    */
}
struct UpiRecursiveGCBuilder(CharType)
{
    Appender!(UpiNodeClass[]) nodes;
    UpiNodeClass currentNode;

    void handle(UpiDelegateParser!CharType* parser, UpiParserEvent event, UpiParseEventArg arg)
    {
        final switch(event)
        {
            case UpiParserEvent.startDirective:
                writefln("[DEBUG] startDirective \"%s\"", arg.string);
                {
                    auto parentNode = this.currentNode;
                    scope(exit) this.currentNode = parentNode;

                    auto node = new UpiNodeClass(arg.string.idup);
                    this.currentNode = node;

                    parser.parse();
                    if(parentNode is null)
                    {
                        nodes.put(node);
                    }
                    else
                    {
                        parentNode.children ~= node;
                    }
                }
                break;
            case UpiParserEvent.property:
                writefln("[DEBUG] property \"%s\"", arg.string);
                assert(currentNode !is null);
                currentNode.properties ~= arg.string.idup;
                // TODO: use the stack to make a linked-list of properties
                break;
            case UpiParserEvent.endDirectives:
                assert(0, format("did not expect to get an endDirectives(%s) event", arg.count));
        }
    }
    void enforceDone()
    {
        if(currentNode !is null)
            throw new Exception("parser has finished but there is still directive that has not been ended");
    }
}

version(unittest)
{
    // shorthand to create a node.  useful to keep test code SMALL
    UpiNodeClass u(string name = null, string[] properties = null, UpiNodeClass[] children = null)
    {
        return new UpiNodeClass(name, properties, children);
    }
}

unittest
{
    void test(string upi, UpiNodeClass[] expectedNodes, size_t testLine = __LINE__)
    {
        writefln("[DEBUG-TEST] testing \"%s\"", upi);

        void checkNodes(UpiNodeClass[] actualNodes)
        {
            if(actualNodes.length != expectedNodes.length) {
                writefln("Error: expected %s nodes but got %s", expectedNodes.length, actualNodes.length);
                assert(0);
            }
            foreach(i; 0..expectedNodes.length)
            {
                if(!expectedNodes[i].equals(actualNodes[i]))
                {
                    writefln("mismatch at index %s", i);
                    writefln("expected: %s", expectedNodes[i]);
                    writefln("actual  : %s", actualNodes[i]);
                    assert(0);
                }
            }
        }

        string filenameForErrors =  format("test_line_%s", testLine);
        // test using UpiSimpleGCBuilder
        {
            auto builder = UpiSimpleGCBuilder!(immutable(char))();
            {
                auto parser = UpiDelegateParser!(immutable(char))();

                parser.reader = &stringReader(upi).readLines;
                parser.handler = &builder.handle;
                parser.filenameForErrors = filenameForErrors;

                parser.parse();
            }
            builder.enforceDone();
            checkNodes(builder.nodes.data);
        }

        writefln("[DEBUG-TEST] ------------ Using RecursiveBuilder", upi);
        // test using UpiRecursiveGCBuilder
        {
            auto builder = UpiRecursiveGCBuilder!(immutable(char))();
            {
                auto parser = UpiDelegateParser!(immutable(char))();

                parser.reader = &stringReader(upi).readLines;
                parser.handler = &builder.handle;
                parser.filenameForErrors = filenameForErrors;

                parser.parse();
            }
            builder.enforceDone();
            checkNodes(builder.nodes.data);
        }
    }

    test("first", [u("first")]);
    test("first prop1", [u("first", ["prop1"])]);
    test("first prop1 prop2", [u("first", ["prop1", "prop2"])]);


    test("first.ext\n\tchild", [u("first.ext", null, [u("child")])]);
    test("first\n\tchild", [u("first", null, [u("child")])]);
    test("first prop1\n\tchild", [u("first", ["prop1"], [u("child")])]);
    test("first prop1 prop2\n\tchild", [u("first", ["prop1", "prop2"], [u("child")])]);
    test("first prop1 prop2\n\tchild cprop1", [u("first", ["prop1", "prop2"], [u("child", ["cprop1"])])]);
    test("first prop1 prop2\n\tchild cprop1 cprop2", [u("first", ["prop1", "prop2"], [u("child", ["cprop1", "cprop2"])])]);

    test("first\nsecond", [u("first"), u("second")]);
    test("first prop1 prop2\nsecond sprop1 sprop2", [u("first",["prop1","prop2"]), u("second", ["sprop1","sprop2"])]);

    test("first\n\tchild1\n\t\tgchild1\n\t\tgchild2", [u("first",null,[u("child1",null,[u("gchild1"),u("gchild2")])])]);
    test("first\n\tchild1\n\t\tgchild1 gcprop1 gcprop2\n\t\tgchild2 gcprop1 gcprop2",
        [u("first",null,[u("child1",null,[u("gchild1",["gcprop1","gcprop2"]),u("gchild2",["gcprop1","gcprop2"])])])]);

    //test("first prop1\n\tchild\n\t\tgchild1 gprop1\n\t\tgchild2 gprop2",

}

uint parseTabDepth(inout(char)** ptr)
{
    uint depthCounter = 0;
    auto cachedPtr = *ptr;
    for(; *cachedPtr == '\t'; cachedPtr++, depthCounter++) { }
    *ptr = cachedPtr;
    return depthCounter;
}
inout(char)[] parseAlphaNumeric(inout(char)** ptr)
{
    auto start = *ptr;
    auto localPtr = *ptr;
    for(;; localPtr++)
    {
        char c = *localPtr;
        // allow "-", ".", "/"
        if(c < '-' || (c > '9' && c < 'A') || (c > 'Z' && c < 'a') || c > 'z')
        {
            break;
        }
    }
    *ptr = localPtr;
    return start[0..localPtr-start];
}
inout(char)[] parseProperty(inout(char)** ptr)
{
    auto start = *ptr;
    char c = *start;
    if(c == '"')
    {
        auto localPtr = *ptr + 1;
        for(;; localPtr++)
        {
            c = *localPtr;
            if(c == '\0' || c == '\n') break;
            if(c == '"' && *(localPtr-1) != '"')
            {
                localPtr++;
                break;
            }
        }
        *ptr = localPtr;
        return start[0..localPtr-start];
    }
    else
    {
        return parseAlphaNumeric(ptr);
    }
}
inout(char)[] parseFileSpecifier(inout(char)** ptr)
{
    inout(char)* start = *ptr;
    inout(char)* localPtr = *ptr;

    if(*localPtr == '"')
    {
        throw new Exception("quoted not implemented");
    }
    else
    {
        for(;; localPtr++)
        {
            char c = *localPtr;
            if(c < '(' || c== '\\' || c == '`' || c > '}')
            {
                break;
            }
        }
    }
    *ptr = localPtr;
    return start[0..localPtr-start];
}
