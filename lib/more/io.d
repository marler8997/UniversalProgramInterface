module more.io;

import core.memory   : GC;
import std.format    : format;
import std.algorithm : copy;

// NOTE: this is a c std library call, but D doesn't seem to have it right now
inout(char)* strchrnul(inout(char)* str, char c)
{
    for(; *str != c && *str != '\0';str++)
    {
    }
    return str;
}

alias ExpandDelegate = void* delegate(void* buffer, size_t preserveSize, size_t newSize);
alias ExpandFunction = void* function(void* buffer, size_t preserveSize, size_t newSize);

void* gcExpander(void* gcBuffer, size_t preserveSize, size_t newSize)
{
    size_t result = GC.extend(gcBuffer, newSize, newSize);
    if(result != 0)
    {
        //writefln("[DEBUG] gcExtender (extended gc buffer to %s)", newSize);
        return gcBuffer;
    }

    auto newBuffer = GC.malloc(newSize);
    if(newBuffer == null)
    {
        assert(0, "out of memory");
    }
    if(preserveSize > 0)
    {
        newBuffer[0..preserveSize] = gcBuffer[0..preserveSize];
    }
    GC.free(gcBuffer);
    // writefln("[DEBUG] gcExtender allocated new buffer");
    return newBuffer;
}
ExpandableGCBuffer!T expandable(T)(T[] buffer)
{
    return ExpandableGCBuffer!T(buffer);
}
struct ExpandableGCBuffer(T)
{
    T[] buffer;
    this(T[] buffer)
    {
        this.buffer = buffer;
    }
    void* expand(void* gcBuffer, size_t preserveSize, size_t newSize)
    {
        assert(gcBuffer == buffer.ptr);
        this.buffer = (cast(T*)gcExpander(gcBuffer, preserveSize, newSize))[0..newSize/T.sizeof];
        return cast(ubyte*)this.buffer.ptr;
    }
}


/**
Returns one or more lines of text as a character slice.

All lines returned MUST be complete, it MUST not return partial lines.

The preceding character after the returned slice must be a valid part of the
array and must be set to '\0'.  This allows code to determine the end of
the lines without needing to pass around the length of all the slice.

The template parameter $(D T) is used to define the return type, i.e.
  char            => function will return char[]
  const(char)     => function will return const(char)[]
  immutable(char) => function will return immutable(char)[] or string

*/
template LinesReaderDelegate(T)
{
    alias LinesReaderDelegate = T[] delegate();
}
struct LinesReaderDelegateRange(CharType)
{
    LinesReaderDelegate!CharType linesReaderDelegate;
    CharType[] nextLine;
    this(LinesReaderDelegate!CharType linesReaderDelegate) in { assert(linesReaderDelegate); } body
    {
        this.linesReaderDelegate = linesReaderDelegate;
        popFront();
    }
    @property bool empty()
    {
        return nextLine.ptr == null;
    }
    @property CharType[] front()
    {
        return nextLine;
    }
    void popFront()
    {
        auto nextPtr = nextLine.ptr;

        if(nextPtr != null)
        {
            nextPtr += nextLine.length;
            if(*nextPtr == '\0')
            {
                nextPtr = null;
            }
        }
        if(nextPtr == null)
        {
            auto chunk = linesReaderDelegate();
            if(chunk.length == 0)
            {
                nextLine = null; // empty
                return;
            }
            assert(chunk.ptr[chunk.length] == '\0',
                "this LinesReaderDelegate returned an chunk that was not NULL terminated");
            nextPtr = chunk.ptr;
        }

        auto endOfLine = strchrnul(nextPtr, '\n');
        if(*endOfLine == '\n')
        {
            endOfLine++;
        }
        nextLine = nextPtr[0..endOfLine-nextPtr];
    }
}

alias ReaderDelegate = size_t delegate(char[]);
alias DelegateLinesReader = LinesReaderTemplate!(ReaderDelegate, ExpandDelegate);

// LinesReader provides an interface to read data that
// is returned in chunks of lines.  It does not return
// partial lines.  It also make sure that the data
// returned is ALWAYS terminated by a NULL character.
//
// The reason for this is that this interface is greate
// for parsers, and parsers can be written more efficiently
// when they are checking for a NULL character rather than
// keeping an extra variable that indicates the end of the text.
//
// Note: since some IO streams may have NULL has a valid character,
//       it might make sense to make this terminating charater configurable
//       or even optional
//
struct LinesReaderTemplate(Reader,Expander)
{
    // TODO: make this a delegate (or better yet a template parameter)
    //       if a big project wants to prevent template bloat, they can
    //       make the template parameter a delegate.
    Reader reader;

    char[] buffer;
    const Expander expander;

    char[] leftOver;
    char leftOverSaveFirstChar; // Need to save because it will be overwritten with '\0' temporarily
    const size_t sizeToTriggerResize; // when the free size of the buffer reaches this value, a resize will be triggered

    this(Reader reader, char[] buffer, Expander expander, size_t sizeToTriggerResize)
    {
        this.reader = reader;
        this.buffer = buffer;
        this.expander = expander;
        this.sizeToTriggerResize = sizeToTriggerResize;
    }
    private void resize(size_t currentDataLength)
    {
        if(expander == null)
        {
            if(currentDataLength >= (buffer.length-1))
            {
                throw new Exception(format("the file contains a line that cannot fit in the given buffer (%s bytes) and no resize function was provided",
                    buffer.length));
            }
        }
        else
        {
            size_t newSize;
            if(buffer.length < sizeToTriggerResize)
            {
                newSize = buffer.length + sizeToTriggerResize;
            }
            else
            {
                newSize = buffer.length * 2;
            }
            //writefln("[DEBUG] expanding read buffer from %s to %s (currentDataLength=%s)",
            //    buffer.length, newSize, currentDataLength);
            buffer = (cast(char*)(expander(buffer.ptr, currentDataLength, newSize)))[0..newSize];
        }
    }
    char[] readLines()
    {
        //writeln("[DEBUG] readLines: enter");
        //scope(exit) writeln("[DEBUG] readLines: exit");

        auto currentDataLength = leftOver.length;

        // Shift left over data to start of buffer to prepare for next read
        if(currentDataLength)
        {
            leftOver[0] = leftOverSaveFirstChar;
            // TODO: check performance of copy vs memmove
            copy(leftOver, buffer[0..currentDataLength]);
            leftOver = null;
        }

        // Expand buffer if too small
        if(currentDataLength + sizeToTriggerResize > (buffer.length-1))
        {
            resize(currentDataLength);
        }

        while(true)
        {
            // Read the next chunk of lines
            size_t readLength = (buffer.length-1) - currentDataLength;
            auto readResult = reader(buffer[currentDataLength..$-1]);
            //writefln("[DEBUG] read %s bytes", readResult);
            auto chunkSize = currentDataLength + readResult;
            if(readResult != readLength)
            {
                buffer[chunkSize] = '\0';
                return buffer[0..chunkSize];
            }

            // search for the end of the last line
            for(size_t i = chunkSize - 1; ; i--)
            {
                if(buffer[i] == '\n')
                {
                    leftOver = buffer[i + 1..chunkSize];
                    leftOverSaveFirstChar = buffer[i + 1];
                    buffer[i + 1] = '\0';
                    return buffer[0..i+1];
                }
                // the line must be too long, need to resize the buffer
                if(i == 0)
                {
                    currentDataLength = chunkSize;
                    resize(chunkSize);
                    break;
                }
            }
        }
    }
    auto byLine()
    {
        return LinesReaderDelegateRange!char(&readLines);
    }
}

// implements the linesReader interface but for a single string
struct StringReader(CharType)
{
    CharType[] data;
    CharType[] readLines()
    {
        string currentData = this.data;
        this.data = null;
        return currentData;
    }
}
StringReader!CharType stringReader(CharType)(CharType[] str)
{
    return StringReader!CharType(str);
}