# Windows Users

> Exqlite uses an [Erlang NIF](https://erlang.org/doc/tutorial/nif.html) under the hood.  
> Means calling a native implementation in C.  
> For Windows users this means compiling Exqlite does not magically just work.  

## Requirements

### Install Microsoft Visual C++ Build Tools

Download page:  
[visualstudio.microsoft.com/visual-cpp-build-tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)

Alternative direct download link:  
[aka.ms/vs/16/release/vs_buildtools.exe](https://aka.ms/vs/16/release/vs_buildtools.exe)  
_for Visual Studio 2019 - version 16_

## Building

### Start command prompt with necessary environment

> Assuming you want to build for Windows x64.

Within Windows Start menu search for:  
x64 Native Tools Command Prompt

Starting this command prompt all necessary environment variables for compiling should be ready.

Means ready to run:
```cmd
mix deps.compile exqlite

# or
mix compile
mix test
```

**Alternative way to start prompt**

Assuming you have _latest_ version of Build Tools (Visual Studio 2019) installed.

```
cmd /k "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
```
