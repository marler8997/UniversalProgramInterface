UPI Schemas
================================================================================

### Example Schema
```
Define identifier [_a-zA-Z][_a-zA-Z]*
Define file-specifier [a-zA-Z_\.\*]+(/[a-zA-Z_\.\*]+)*

Directive Files <file-specifier>...

Directive Language <identifier>
	Optional Version <identifier>

Directive SourceCode
	Multiple <Files>
	Optional <Language>

Directive ConsoleProgram <identifier>
	Multiple <SourceCode>
	Optional FileName # Defaults to the ConsoleProgram <identifier> if missing
	Multiple NeedsLibrary <identifier>

Directive Library <identifier>
	Multiple <SourceCode>
```