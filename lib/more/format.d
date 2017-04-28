module more.format;

import core.stdc.string : strlen;

char hexchar(ubyte b) in { assert(b <= 0x0F); } body
{
    return cast(char)(b + ((b <= 9) ? '0' : ('A'-10)));
}

struct Escaped
{
    const(char)* str;
    const char* limit;
    this(const(char)[] str)
    {
        this.str = str.ptr;
        this.limit = str.ptr + str.length;
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        const(char) *print = str;
        const(char) *ptr = str;
      CHUNK_LOOP:
        for(;ptr < limit;ptr++)
        {
            char c = *ptr;
            if(c < ' ' || c > '~') // if not human readable
            {
                if(ptr > print)
                {
                    sink(print[0..ptr-print]);
                }
                if(c == '\r') sink("\\r");
                else if(c == '\t') sink("\\t");
                else if(c == '\n') sink("\\n");
                else {
                    char[4] buffer;
                    buffer[0] = '\\';
                    buffer[1] = 'x';
                    buffer[2] = hexchar(c>>4);
                    buffer[3] = hexchar(c&0xF);
                    sink(buffer);
                }
                print = ptr + 1;
            }
        }
        if(ptr > print)
        {
            sink(print[0..ptr-print]);
        }
    }
}


// used to print null-terminated c strings with d's writefln/format.
// it uses strlen to calculate the length of the string to convert
// it to a d-slice
struct CString
{
    char* cstr;
    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink(cstr[0..strlen(cstr)]);
    }
}

struct CharEscaped
{
    char c;
    void toString(scope void delegate(const(char)[]) sink) const
    {
        if(c >= ' ' && c <= '~') { // if char is human readable
            sink((&c)[0..1]);
        } else if(c == '\0') {
            sink("\\0");
        } else if(c == '\r') {
            sink("\\r");
        } else if(c == '\t') {
            sink("\\t");
        } else if(c == '\n') {
            sink("\\n");
        } else {
            char[4] buffer;
            buffer[0] = '\\';
            buffer[1] = 'x';
            buffer[2] = hexchar(c>>4);
            buffer[3] = hexchar(c&0xF);
            sink(buffer);
        }
    }
}
CStringEscapedStruct!extraTerminators CStringEscaped(string extraTerminators = null)(const(char)* ptr)
{
    return CStringEscapedStruct!extraTerminators(ptr);
}
struct CStringEscapedStruct(string extraTerminators = null)
{
    const(char)* cstr;
    /*
    this(const(char)* cstr)
    {
        this.cstr = cstr;
    }
    */
    void toString(scope void delegate(const(char)[]) sink) const
    {
        const(char) *print = cstr;
        const(char) *ptr = cstr;
      CHUNK_LOOP:
        for(;;ptr++)
        {
            char c = *ptr;

            static if(extraTerminators.length > 0)
            {
                foreach(extraTerminator; extraTerminators)
                {
                    if(c == extraTerminator)
                    {
                        break CHUNK_LOOP;
                    }
                }
            }

            if(c < ' ' || c > '~') // if not human readable
            {
                if(c == '\0') break;
                if(ptr > print)
                {
                    sink(print[0..ptr-print]);
                }
                if(c == '\r') sink("\\r");
                else if(c == '\t') sink("\\t");
                else if(c == '\n') sink("\\n");
                else {
                    char[4] buffer;
                    buffer[0] = '\\';
                    buffer[1] = 'x';
                    buffer[2] = hexchar(c>>4);
                    buffer[3] = hexchar(c&0xF);
                    sink(buffer);
                }
                print = ptr + 1;
            }
        }
        if(ptr > print)
        {
            sink(print[0..ptr-print]);
        }
    }
}