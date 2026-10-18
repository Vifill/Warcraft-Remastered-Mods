#!/usr/bin/env python3
"""Build 32-bit Windows import libraries without the Windows SDK.

For each DLL listed in IMPORTS, generate stub functions with the right stdcall decoration
(Name@<argbytes>), link a throwaway DLL with lld-link and keep its import library.

Usage: python3 mkimplib.py <outdir>
"""
import os
import subprocess
import sys

# dll -> {function: argument bytes}
IMPORTS = {
    'kernel32': {
        'LoadLibraryA': 4, 'GetProcAddress': 8, 'GetModuleHandleA': 4, 'GetModuleFileNameA': 12,
        'GetSystemDirectoryA': 8, 'CreateThread': 24, 'CloseHandle': 4, 'Sleep': 4,
        'VirtualProtect': 16, 'FlushInstructionCache': 12, 'GetCurrentProcess': 0,
        'GetPrivateProfileIntA': 16, 'GetPrivateProfileStringA': 24, 'WritePrivateProfileStringA': 16,
        'CreateFileA': 28, 'WriteFile': 20, 'SetFilePointer': 16, 'DisableThreadLibraryCalls': 4,
        'GetLocalTime': 4, 'DeleteFileA': 4, 'GetFileAttributesA': 4, 'CreateDirectoryA': 8,
        'GetLastError': 0, 'ExitProcess': 4, 'GetCommandLineA': 0, 'lstrlenA': 4,
    },
    'user32': {
        'MessageBoxA': 16, 'CreateWindowExA': 48, 'DefWindowProcA': 16, 'RegisterClassExA': 4,
        'GetMessageA': 16, 'TranslateMessage': 4, 'DispatchMessageA': 4, 'PostQuitMessage': 4,
        'SendMessageA': 16, 'GetDlgItem': 8, 'SetWindowTextA': 8, 'GetWindowTextA': 12,
        'EnableWindow': 8, 'ShowWindow': 8, 'UpdateWindow': 4, 'LoadCursorA': 8, 'LoadIconA': 8,
        'GetSystemMetrics': 4, 'DestroyWindow': 4, 'IsDialogMessageA': 8, 'GetSysColorBrush': 4,
        'SetFocus': 4, 'GetAsyncKeyState': 4,
    },
    'advapi32': {'RegOpenKeyExA': 20, 'RegQueryValueExA': 24, 'RegCloseKey': 4, 'RegEnumKeyExA': 32},
    'shell32': {'SHBrowseForFolderA': 4, 'SHGetPathFromIDListA': 8},
    'gdi32': {'GetStockObject': 4},
    'ole32': {'CoTaskMemFree': 4, 'CoInitialize': 4},
}


def main():
    out = os.path.abspath(sys.argv[1])
    os.makedirs(out, exist_ok=True)
    for dll, funcs in IMPORTS.items():
        c = os.path.join(out, f'{dll}_stub.c')
        d = os.path.join(out, f'{dll}.def')
        with open(c, 'w') as f:
            for name, nbytes in funcs.items():
                args = ', '.join(f'int a{i}' for i in range(nbytes // 4)) or 'void'
                f.write(f'int __stdcall {name}({args}) {{ return 0; }}\n')
        with open(d, 'w') as f:
            f.write(f'LIBRARY {dll}.dll\nEXPORTS\n')
            for name in funcs:
                f.write(f'  {name}\n')
        obj = os.path.join(out, f'{dll}_stub.obj')
        subprocess.run(['clang', '-target', 'i386-pc-windows-msvc', '-c', c, '-o', obj], check=True)
        subprocess.run(['lld-link', '/dll', '/noentry', '/machine:x86', f'/def:{d}',
                        f'/out:{os.path.join(out, dll + "_stub.dll")}',
                        f'/implib:{os.path.join(out, dll + ".lib")}', obj], check=True)
        for ext in ('_stub.c', '_stub.obj', '_stub.dll', '.def'):
            os.remove(os.path.join(out, dll + ext))
        print('built', dll + '.lib')


if __name__ == '__main__':
    main()
