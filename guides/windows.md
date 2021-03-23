# Windows users

> Exqlite uses an [Erlang NIF](https://erlang.org/doc/tutorial/nif.html) under the hood.  
> Means calling a native implementation in C.

For Windows users this means compiling Exqlite does not magically just work.  
Of course, using **WSL 2** can be an alternative.

## Requirements

### Install Microsoft Visual C++ build tools

Download page:  
[visualstudio.microsoft.com/visual-cpp-build-tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)

Alternative direct download link:  
[aka.ms/vs/16/release/vs_buildtools.exe](https://aka.ms/vs/16/release/vs_buildtools.exe)  
_(aligned with Visual Studio 2019 - version 16)_

You need to install the **C++ build tools** workload with the default optional components.

## Building environment

### Start command prompt with necessary environment

> Assuming you are building for Windows x64.

Within Windows start menu search for:  
x64 Native Tools Command Prompt

Starting this command prompt all necessary environment variables  
for compiling should be ready within the prompt.

Ready to run:
```powershell
mix deps.compile exqlite

# or
mix compile
mix test
...
```

**Alternative way to start prompt**

> Assuming you have _latest_ version of Build Tools, aligned with Visual Studio **2019**,  
installed in its default installation path.

```powershell
cmd /k "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
```

## Visual Studio Code users using ElixirLS

> Assuming you have _latest_ version of Build Tools, aligned with Visual Studio **2019**,  
installed in its default installation path.

Start Visual Studio Code from a PowerShell prompt within your project folder.

```powershell
cmd /k '"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" && code .'
```

With starting Visual Studio Code this way, ElixirLS should work  
and even your integrated terminal should be aware or the build tools.

Probably make yourself a shortcut for this.

**Integrated terminal only**

Within your global `settings.json` or your workspace `.vscode\settings.json` add:

```json
{
  "terminal.integrated.shell.windows": "cmd.exe",
  "terminal.integrated.shellArgs.windows": [
     "/k",
     "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat",
  ]
}
```
