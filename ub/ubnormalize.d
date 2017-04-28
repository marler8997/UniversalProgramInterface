module ubnormalize;

import core.stdc.string : memmove;

import std.stdio   : writefln, File;
import std.file    : exists, rename, remove;
import std.format  : format, sformat;
import std.algorithm : swap;
import std.path      : extension;
import std.typecons  : Flag;

import more.io;
import more.format : Escaped;

import ub : SilentException, DummyFileType, extensionDelegate;

alias FileMoveCallback = void function(const(char)[] src, const(char)[] dest);

/**
   Moves $(D tempFilename) to $(D filename) and then rools $(D backupCount) backup files.
*/
void rollFiles(const(char)[] tempFilename, const(char)[] filename, ubyte backupCount, FileMoveCallback moveCallback)
{
    if(backupCount >= 1)
    {
        size_t backupMaxFileLength =
            ".".length +       // the "." prefix
            filename.length +  // length of the orignal filename
            4 +                // the backup number 1 - 255
            ".backup".length + // the ".backup" postfix
            1;                 // terminating null
        char[] filenameBuffer1 = new char[backupMaxFileLength];
        char[] fileToOverwrite = sformat(filenameBuffer1, ".%s.%s.backup", filename, backupCount);

        if(backupCount >= 2)
        {
            char[] filenameBuffer2 = new char[backupMaxFileLength];

            backupCount--;
            char[] fileToRoll = sformat(filenameBuffer2, ".%s.%s.backup", filename, backupCount);
            size_t backupPostixOffset = 2 + filename.length;

            for(;;)
            {
                moveCallback(fileToRoll, fileToOverwrite);
                swap(fileToRoll, fileToOverwrite);
                backupCount--;
                if(backupCount == 0) break;
                fileToRoll = fileToRoll.ptr[0.. backupPostixOffset +
                    sformat(fileToRoll.ptr[backupPostixOffset..backupMaxFileLength], "%s.backup", backupCount).length];
            }
        }

        moveCallback(filename, fileToOverwrite);
    }
    moveCallback(tempFilename, filename);
}

uint decimalDigitCount(size_t value)
{
    uint valueLimit = 10;
    for(uint digitCount = 1; ; digitCount++)
    {
        if(value < valueLimit) return digitCount;
        valueLimit *= 10;
    }
}

alias DelegateWriter = void delegate(const(char[]));
struct NormalizedInfo
{
    Flag!"printModifications" printModifications;
    size_t lineCount;
    size_t modifiedLineCount;
    size_t lastLineModified;
    @property bool currentLineModified()
    {
        return this.lastLineModified == lineCount;
    }
    void aboutToModify(const(char)[] line)
    {
        if(lineCount != lastLineModified)
        {
            if(printModifications)
            {
                writefln("line %s \"%s\"", lineCount, Escaped(line));
            }
            modifiedLineCount++;
            lastLineModified = lineCount;
        }
    }
    void modifiedLineFinished(const(char)[] newLine)
    {
        if(printModifications && currentLineModified)
        {
            writefln("     %*s \"%s\"", lineCount.decimalDigitCount, " ", Escaped(newLine));
        }
    }
}
void doNormalize(bool printLines, NormalizedInfo* normalizedInfo, DelegateLinesReader reader, DelegateWriter writer)
{
    foreach(line; reader.byLine())
    {
        normalizedInfo.lineCount++;
        if(line.length == 0)
        {
            // this would only happen if we were at the end of the
            // file and the file ended with a blank newline
            continue;
        }
        size_t setIndex = 0;
        // convert 4 spaces to tab
        size_t readIndex = 0;
        for(; readIndex + 3 < line.length; readIndex += 4)
        {
            if(    line[readIndex  ] != ' ' || line[readIndex+1] != ' '
                || line[readIndex+2] != ' ' || line[readIndex+3] != ' ')
            {
                break;
            }
            normalizedInfo.aboutToModify(line);
            line[setIndex++] = '\t';
            // modified will be set at the next block
        }


        size_t restOfLineLength = line.length - readIndex;

        // check if the rest of the line is whitespace

        if(readIndex > setIndex)
        {
            if(restOfLineLength > 0)
            {
                memmove(line.ptr + setIndex, line.ptr + readIndex, restOfLineLength);
            }
        }
        setIndex += restOfLineLength;

        // remove trailing ' ', '\t' and '\r'
        {
            bool haveNewline;
            size_t indexOfNewlineOrEOF;
            if(setIndex > 0 && line[setIndex-1] == '\n')
            {
                haveNewline = true;
                indexOfNewlineOrEOF = setIndex-1;
            }
            else
            {
                haveNewline = false;
                indexOfNewlineOrEOF = setIndex;
            }

            {
                size_t contentLimit = indexOfNewlineOrEOF;
                for(;contentLimit > 0; contentLimit--)
                {
                    char c = line[contentLimit - 1];
                    if(c != ' ' && c != '\t' && c != '\r')
                    {
                        break;
                    }
                }
                if(contentLimit < indexOfNewlineOrEOF)
                {
                    normalizedInfo.aboutToModify(line);
                    size_t whitespaceCount = indexOfNewlineOrEOF - contentLimit;
                    setIndex -= whitespaceCount;
                    if(haveNewline)
                    {
                        line[setIndex-1] = '\n';
                    }
                }
            }
        }
        normalizedInfo.modifiedLineFinished(line[0..setIndex]);
        writer(line[0..setIndex]);
    }
}

void normalizeUpiFile(const(char)[] filename, ExpandableGCBuffer!char* sharedBuffer)
{
    // forbid files that don't have the extension upi
    // this is to prevent mistakenly normalizing a non-upi file.
    if(extension(filename) != ".upi")
    {
        writefln("Error: \"%s\" does not have the \".upi\" file extension", filename);
        throw new SilentException();
    }
    if(!exists(filename))
    {
        writefln("Error: \"%s\" does not exist", filename);
        throw new SilentException();
    }
    NormalizedInfo normalizedInfo = NormalizedInfo(Flag!"printModifications".yes);
    string normalizedFilename = format("%s.normalized", filename);
    {
        auto inputFile = File(filename, "rb");
        scope(exit) inputFile.close();

        auto outputFile = File(normalizedFilename, "wb");
        scope(exit) outputFile.close();

        auto reader = DelegateLinesReader((&inputFile).extensionDelegate!(DummyFileType, q{rawReadReturnSize!char}), sharedBuffer.buffer, &sharedBuffer.expand, 150);

        doNormalize(true, &normalizedInfo, reader, &outputFile.rawWrite!char);
    }

    if(normalizedInfo.modifiedLineCount == 0)
    {
        writefln("%s: already normalized", filename);
        remove(normalizedFilename);
    }
    else
    {
        writefln("%s: %s/%s lines modified", filename, normalizedInfo.modifiedLineCount, normalizedInfo.lineCount);

        // double check that normalization worked
        {
            NormalizedInfo recursiveNormalizedInfo = NormalizedInfo(Flag!"printModifications".no);

            auto inputFile = File(normalizedFilename, "rb");
            scope(exit) inputFile.close();

            auto reader = DelegateLinesReader((&inputFile).extensionDelegate!(DummyFileType, q{rawReadReturnSize!char}),
                sharedBuffer.buffer, &sharedBuffer.expand, 150);
            doNormalize(false, &recursiveNormalizedInfo, reader, delegate void(const(char[]) line)
            {
                // do nothing
            });
            if(recursiveNormalizedInfo.modifiedLineCount > 0)
            {
                writefln("Error: normalized file \"%s\" was not actually normalized", normalizedFilename);
                throw new SilentException();
            }
        }
        rollFiles(normalizedFilename, filename, 3, function void (const(char)[] src, const(char)[]dst)
        {
            if(exists(src))
            {
                writefln("Moving \"%s\" to \"%s\"", src, dst);
                rename(src, dst);
            }
        });
    }
}
