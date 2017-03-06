# ShimmySham
ShimmySham is a script that can generate source code for shim DLLs automatically. It was orignally based on the article [here](http://www.hulver.com/scoop/story/2006/2/18/125521/185), but
everything has been completely rewritten in Ruby, updated for 64-bit compatability, and improved for cleanliness and clarity.

# Configuration
This is a standalone script with no dependancies on other gems, however it does require the file "dumpbin.exe" in order to work correctly. This file is included with Microsoft Visual Studio, which you will also need to compile the generated source code. Before using the script, edit the first line so that the DUMPBIN variable points to "dumpbin.exe" in your Visual Studio installation. Additionally, you will need to install an assembler (prefferably nasm) and add it to your path variable to compile the .asm files.

# Usage
To generate source files, simply run "ruby shimmysham.rb file.dll". This will produce a .cpp, .asm, and a .def file. To compile these files, first create an empty DLL project and add all the files to the source folder. Then go to Project->Properties->Linker->Input. Change the configuration at the top to "All Configurations" and the platform to "All Platforms", and then enter the name of the of the .def file in the "Module Definition File" field. Now find the .asm file in the solution explorer, right click on it, and open it's properties. Again, change the configuration to "All Configurations" and change the value of the "Item Type" field to "Custom Build Tool". Apply the settings, and open the "Custom Build Tool" page on the left. Depending on whether you want to do a 32-bit build or 64-bit build, change the platform to the apprpriate setting and enter:

* Command Line (32-bit): `nasm.exe -f win32 -o "$(IntDir)\file.asm.obj" file.asm`
* Command Line (64-bit): `nasm.exe -f win64 -o "$(IntDir)\file.asm.obj" file.asm`
* Outputs: `$(IntDir)\file.asm.obj`

Make sure the replace all instances of "file.asm" with the name of the .asm file from your project. If your project now builds, you are ready to go!

To override a function, you will need to edit the .asm file to use the override macro, and add your override to a .cpp file, making sure to match the original function prototype exactly. For example, here is user32.asm modified to override GetMessage:

```
*snip*
shim GetMenuStringA
shim GetMenuStringW
override GetMessageA, @16
shim GetMessageExtraInfo
shim GetMessagePos
shim GetMessageTime
override GetMessageW, @16
shim GetMonitorInfoA
shim GetMonitorInfoW
*snip*
```

Note the use of the second argument to the override macro to specify a suffix for the function name. This is only required for 32-bit builds, because Visual C++'s compiler adds a suffix the the function symbols to indicate the number of bytes in the stack frame. @16 should be replaced with a suffix corresponding to the total size in bytes of the arguments to the function. So for example, a function whoose argument types were, byte, short, and long would have the suffix @7 (always use the 32-bit sizes since the suffix is not used in 64-bit builds).

Then in a new file called overrides.cpp add:

```
#include <windows.h>
#include <stdio.h>
#include <tchar.h>

extern "C"
{

	BOOL WINAPI I_GetMessageA(_Out_ LPMSG lpMsg, _In_opt_ HWND hWnd, _In_ UINT wMsgFilterMin, _In_ UINT wMsgFilterMax)
	{
		BOOL result = GetMessageA(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax);

		//if (lpMsg->message == WM_INPUT)
			wprintf(_T("Message: %lu, Window: %p\n"), lpMsg->message, lpMsg->hwnd);

		return result;
	}

	BOOL WINAPI I_GetMessageW(_Out_ LPMSG lpMsg, _In_opt_ HWND hWnd, _In_ UINT wMsgFilterMin, _In_ UINT wMsgFilterMax)
	{
		BOOL result = GetMessageW(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax);

		//if (lpMsg->message == WM_INPUT)
			wprintf(_T("Message: %lu, Window: %p\n"), lpMsg->message, lpMsg->hwnd);

		return result;
	}

}
```

Note the prefix "I_" must be added the the name to differentiate from the original function. If you wish to change the prefix used for some reason you can simply edit the macros at the start of the .asm file.

If you now do a debug build, you should generate a file called user32.dll. When loaded by an application, this .dll file should open a console window and print a string indicating when GetMessage is called and the first two parameters is was called with. Now you are free to modify those parameters, and see what happens. ;)

Note that generally speaking Windows will not allow a process to automatically load a file recognized as a system .dll from it's own folder, so some trickery (modyfying the .exe's import table), or .dll injection may be neccessary.
