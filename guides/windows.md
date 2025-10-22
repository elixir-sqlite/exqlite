# Windows users

> Exqlite uses an [Erlang NIF](https://erlang.org/doc/tutorial/nif.html) under the hood.  
> Means calling a native implementation in C.

For Windows users this means compiling Exqlite does not magically just work,  
in case it's not able to use the precompiled versions of SQLite (using advanced configuration - compile flags).  
Under the hood mix will try to compile the library with NMAKE on Windows.  
For this, NMAKE and C++ build tools needs to be available.

Of course, using **WSL 2** can be an alternative if things below doesn't work.

## Requirements

### Install Microsoft C++ Build Tools

Download page:  
[visualstudio.microsoft.com/visual-cpp-build-tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)

Alternative direct download link:  
[aka.ms/vs/17/release/vs_buildtools.exe](https://aka.ms/vs/17/release/vs_buildtools.exe)  
_(aligned with Visual Studio 2022 - version 17)_

You need to install the **Desktop development with C++** workload with probably the default optional components.

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

> Assuming you have _latest_ version of Build Tools, aligned with Visual Studio **2022**,  
installed in its default installation path.

```powershell
cmd /k "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
```

## Visual Studio Code users using ElixirLS

> Assuming you have _latest_ version of Build Tools, aligned with Visual Studio **2022**.

Start Visual Studio Code from a PowerShell prompt within your project folder.

```powershell
cmd /k '"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" && code .'
```

With starting Visual Studio Code this way, ElixirLS should work  
and even your integrated terminal should be aware of the build tools.

Probably make yourself a shortcut for this.

**Integrated terminal only**

Within your global `settings.json` or your workspace `.vscode\settings.json` add:

```json
{
    "terminal.integrated.defaultProfile.windows": "PowerShell for VS2022",
    // You can select one you like.
    "terminal.integrated.profiles.windows": {
        "Command Prompt for VS2022": {
            "path": [
                "${env:windir}\\Sysnative\\cmd.exe",
                "${env:windir}\\System32\\cmd.exe"
            ],
            "args": [
                // Please note that you need to change the directory to YOURS and translate the backslashes(`\` => `\\`).
                "/k","D:\\VisualStudio\\VS2022\\Community\\Common7\\Tools\\VsDevCmd.bat",
                "-startdir=none",
                "-arch=x64",
                "-host_arch=x64"
                // In you have not installed whole VisualStudio, only use
                // "D:\\VisualStudio\\VS2022\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat"
                // or some directory you installed is better.
            ],
            "icon": "terminal-cmd"
        },
        "PowerShell for VS2022": {
            "source": "PowerShell",
            "args": [
                "-NoExit",
                "-Command",
                // Don't forget let `"""` into `\"` in module part during copy.
                "&{Import-Module \"D:\\VisualStudio\\VS2022\\Community\\Common7\\Tools\\Microsoft.VisualStudio.DevShell.dll\"; Enter-VsDevShell e182031c -SkipAutomaticLocation -DevCmdArguments \"-arch=x64 -host_arch=x64\"}"
            ],
            "icon": "terminal-powershell",
            "env": {}
        }
    }
}
```

> **How arguments come?**
>
> If you have Windows Terminal, after VS2022 installed, your Windows Terminal app should include `Developer Command Prompt for VS2022` and `Developer PowerShell for VS2022`.
>
> Next you just need to switch to "Configuration" and scroll down to "Profiles" and choose the one you prefer.
>
> After copy and paste, simply do like `~w()` sigil does in `args` part above, replacing the paths with your actual Visual Studio installation directory.
