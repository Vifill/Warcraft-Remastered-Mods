/* Windows installer for the Warcraft I: Remastered mods.
 * Finds the game, lets the user pick mods, and writes VERSION.dll + w1r_mods.ini next to
 * x86\Warcraft.exe. Uninstall removes them. No runtime needed; the mod DLL is embedded.
 */
#include "mod_dll.h"
#include "crt.h"

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef void *HANDLE;
typedef int BOOL;
typedef long LRESULT;
typedef u32 WPARAM;
typedef long LPARAM;
#define WINAPI __stdcall

typedef LRESULT(WINAPI *WNDPROC)(HANDLE, u32, WPARAM, LPARAM);
typedef struct { u32 cbSize, style; WNDPROC lpfnWndProc; int cbClsExtra, cbWndExtra;
    HANDLE hInstance, hIcon, hCursor, hbrBackground; const char *lpszMenuName, *lpszClassName;
    HANDLE hIconSm; } WNDCLASSEXA;
typedef struct { HANDLE hwnd; u32 message; WPARAM wParam; LPARAM lParam; u32 time; int x, y; } MSG;
typedef struct { HANDLE hwndOwner; void *pidlRoot; char *pszDisplayName; const char *lpszTitle;
    u32 ulFlags; void *lpfn; LPARAM lParam; int iImage; } BROWSEINFOA;

__declspec(dllimport) HANDLE WINAPI GetModuleHandleA(const char *);
__declspec(dllimport) void WINAPI ExitProcess(u32);
__declspec(dllimport) HANDLE WINAPI CreateFileA(const char *, u32, u32, void *, u32, u32, HANDLE);
__declspec(dllimport) BOOL WINAPI WriteFile(HANDLE, const void *, u32, u32 *, void *);
__declspec(dllimport) BOOL WINAPI CloseHandle(HANDLE);
__declspec(dllimport) BOOL WINAPI DeleteFileA(const char *);
__declspec(dllimport) u32 WINAPI GetFileAttributesA(const char *);
__declspec(dllimport) BOOL WINAPI WritePrivateProfileStringA(const char *, const char *, const char *, const char *);
__declspec(dllimport) u32 WINAPI GetPrivateProfileIntA(const char *, const char *, int, const char *);
__declspec(dllimport) u32 WINAPI GetPrivateProfileStringA(const char *, const char *, const char *, char *, u32, const char *);
__declspec(dllimport) u32 WINAPI GetLastError(void);
__declspec(dllimport) int WINAPI MessageBoxA(HANDLE, const char *, const char *, u32);
__declspec(dllimport) HANDLE WINAPI CreateWindowExA(u32, const char *, const char *, u32, int, int, int, int, HANDLE, HANDLE, HANDLE, void *);
__declspec(dllimport) LRESULT WINAPI DefWindowProcA(HANDLE, u32, WPARAM, LPARAM);
__declspec(dllimport) u16 WINAPI RegisterClassExA(const WNDCLASSEXA *);
__declspec(dllimport) BOOL WINAPI GetMessageA(MSG *, HANDLE, u32, u32);
__declspec(dllimport) BOOL WINAPI TranslateMessage(const MSG *);
__declspec(dllimport) LRESULT WINAPI DispatchMessageA(const MSG *);
__declspec(dllimport) void WINAPI PostQuitMessage(int);
__declspec(dllimport) LRESULT WINAPI SendMessageA(HANDLE, u32, WPARAM, LPARAM);
__declspec(dllimport) BOOL WINAPI SetWindowTextA(HANDLE, const char *);
__declspec(dllimport) int WINAPI GetWindowTextA(HANDLE, char *, int);
__declspec(dllimport) BOOL WINAPI ShowWindow(HANDLE, int);
__declspec(dllimport) BOOL WINAPI UpdateWindow(HANDLE);
__declspec(dllimport) HANDLE WINAPI LoadCursorA(HANDLE, u32);
__declspec(dllimport) HANDLE WINAPI LoadIconA(HANDLE, u32);
__declspec(dllimport) int WINAPI GetSystemMetrics(int);
__declspec(dllimport) BOOL WINAPI IsDialogMessageA(HANDLE, MSG *);
__declspec(dllimport) HANDLE WINAPI GetSysColorBrush(int);
__declspec(dllimport) HANDLE WINAPI GetStockObject(int);
__declspec(dllimport) long WINAPI RegOpenKeyExA(HANDLE, const char *, u32, u32, HANDLE *);
__declspec(dllimport) long WINAPI RegQueryValueExA(HANDLE, const char *, u32 *, u32 *, u8 *, u32 *);
__declspec(dllimport) long WINAPI RegEnumKeyExA(HANDLE, u32, char *, u32 *, u32 *, char *, u32 *, void *);
__declspec(dllimport) long WINAPI RegCloseKey(HANDLE);
__declspec(dllimport) void *WINAPI SHBrowseForFolderA(BROWSEINFOA *);
__declspec(dllimport) BOOL WINAPI SHGetPathFromIDListA(void *, char *);
__declspec(dllimport) long WINAPI CoInitialize(void *);
__declspec(dllimport) void WINAPI CoTaskMemFree(void *);

#define HKLM ((HANDLE)(unsigned long)0x80000002)
#define WS_OVERLAPPEDWINDOW_FIXED 0x00CA0000   /* caption | sysmenu | minimizebox */
#define WS_CHILD_VISIBLE 0x50000000
#define WS_TABSTOP 0x00010000
#define BS_AUTOCHECKBOX 3
#define BS_DEFPUSHBUTTON 1
#define ES_AUTOHSCROLL 0x80
#define WS_EX_CLIENTEDGE 0x200
#define BM_GETCHECK 0xF0
#define BM_SETCHECK 0xF1
#define WM_SETFONT 0x30
#define WM_COMMAND 0x111
#define WM_DESTROY 2
#define MB_OK 0
#define MB_ICONINFO 0x40
#define MB_ICONWARN 0x30
#define MB_ICONERROR 0x10

enum { ID_PATH = 100, ID_BROWSE, ID_GHOST, ID_PAN, ID_ASTAR, ID_INSTALL, ID_UNINSTALL, ID_STATUS };
static const char *TITLE = "Warcraft I: Remastered Mods " MOD_VERSION;

static HANDLE g_wnd, g_path, g_ghost, g_pan, g_astar, g_status, g_font;

static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
static void scpy(char *d, const char *s) { while ((*d++ = *s++)) ; }
static void scat(char *d, const char *s) { scpy(d + slen(d), s); }
static int contains_ci(const char *h, const char *n)
{
    for (; *h; h++) {
        int i = 0;
        for (; n[i]; i++) {
            char a = h[i], b = n[i];
            if (a >= 'A' && a <= 'Z') a = (char)(a + 32);
            if (b >= 'A' && b <= 'Z') b = (char)(b + 32);
            if (a != b) break;
        }
        if (!n[i]) return 1;
    }
    return 0;
}
static int exists(const char *p) { return GetFileAttributesA(p) != 0xFFFFFFFFu; }

static void strip_slash(char *p) { int n = slen(p); while (n > 3 && (p[n - 1] == '\\' || p[n - 1] == '/')) p[--n] = 0; }

/* Accept either the game folder or its x86 subfolder; return 1 and write the x86 folder. */
static int x86_dir(const char *game, char *out)
{
    char t[600];
    scpy(out, game); strip_slash(out);
    scpy(t, out); scat(t, "\\x86\\Warcraft.exe");
    if (exists(t)) { scat(out, "\\x86"); return 1; }
    scpy(t, out); scat(t, "\\Warcraft.exe");
    return exists(t);
}

/* Look through installed programs (both registry views) for Warcraft I Remastered. */
static int find_game(char *out)
{
    static const u32 views[] = {0x200 /* KEY_WOW64_32KEY */, 0x100 /* KEY_WOW64_64KEY */};
    for (int v = 0; v < 2; v++) {
        HANDLE root;
        if (RegOpenKeyExA(HKLM, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", 0,
                          0x20019 | views[v], &root)) continue;
        char name[256];
        for (u32 i = 0;; i++) {
            u32 nl = sizeof name;
            if (RegEnumKeyExA(root, i, name, &nl, 0, 0, 0, 0)) break;
            HANDLE k;
            if (RegOpenKeyExA(root, name, 0, 0x20019 | views[v], &k)) continue;
            char disp[256] = {0}, loc[400] = {0};
            u32 dl = sizeof disp - 1, ll = sizeof loc - 1;
            RegQueryValueExA(k, "DisplayName", 0, 0, (u8 *)disp, &dl);
            RegQueryValueExA(k, "InstallLocation", 0, 0, (u8 *)loc, &ll);
            RegCloseKey(k);
            char x[600];
            if (contains_ci(disp, "Warcraft I") && !contains_ci(disp, "Warcraft II") && loc[0] && x86_dir(loc, x)) {
                scpy(out, loc); strip_slash(out); RegCloseKey(root); return 1;
            }
        }
        RegCloseKey(root);
    }
    static const char *guesses[] = {"C:\\Program Files (x86)\\Warcraft I Remastered",
                                    "C:\\Program Files\\Warcraft I Remastered",
                                    "D:\\Games\\Warcraft I Remastered"};
    for (int i = 0; i < 3; i++) {
        char x[600];
        if (x86_dir(guesses[i], x)) { scpy(out, guesses[i]); return 1; }
    }
    return 0;
}

static void status(const char *s) { SetWindowTextA(g_status, s); }
static int checked(HANDLE h) { return SendMessageA(h, BM_GETCHECK, 0, 0) == 1; }

static void do_install(int install)
{
    char game[600], x86[600], dll[700], ini[700], log[700];
    GetWindowTextA(g_path, game, sizeof game);
    if (!game[0] || !x86_dir(game, x86)) {
        MessageBoxA(g_wnd, "Warcraft.exe was not found in that folder.\n\nPick the folder where Battle.net "
                    "installed Warcraft I: Remastered (it contains an x86 folder).", TITLE, MB_OK | MB_ICONWARN);
        return;
    }
    scpy(dll, x86); scat(dll, "\\VERSION.dll");
    scpy(ini, x86); scat(ini, "\\w1r_mods.ini");
    scpy(log, x86); scat(log, "\\w1r_mods.log");

    if (!install) {
        int had = exists(dll);
        if (had && !DeleteFileA(dll)) {
            MessageBoxA(g_wnd, "Could not remove VERSION.dll. Close Warcraft I and try again.", TITLE, MB_OK | MB_ICONERROR);
            return;
        }
        DeleteFileA(ini); DeleteFileA(log);
        status(had ? "Mods removed. The game is back to normal." : "Mods were not installed.");
        return;
    }

    HANDLE f = CreateFileA(dll, 0x40000000, 0, 0, 2, 0x80, 0);
    if (f == (HANDLE)-1) {
        MessageBoxA(g_wnd, "Could not write VERSION.dll.\n\nClose Warcraft I, then try again. If the game is "
                    "in Program Files, run this installer as administrator.", TITLE, MB_OK | MB_ICONERROR);
        return;
    }
    u32 w = 0;
    BOOL ok = WriteFile(f, mod_dll, sizeof mod_dll, &w, 0) && w == sizeof mod_dll;
    CloseHandle(f);
    if (!ok) { MessageBoxA(g_wnd, "Writing VERSION.dll failed.", TITLE, MB_OK | MB_ICONERROR); return; }

    WritePrivateProfileStringA("mods", "enabled", "1", ini);
    WritePrivateProfileStringA("mods", "ghost_fix", checked(g_ghost) ? "1" : "0", ini);
    WritePrivateProfileStringA("mods", "middle_mouse_pan", checked(g_pan) ? "1" : "0", ini);
    WritePrivateProfileStringA("mods", "pan_speed_percent", "100", ini);
    WritePrivateProfileStringA("mods", "pathfinding", checked(g_astar) ? "astar" : "original", ini);
    WritePrivateProfileStringA("mods", "patch_delay_ms", "8000", ini);
    status("Installed! Start Warcraft I from Battle.net as usual.");
    MessageBoxA(g_wnd, "Mods installed.\n\nStart Warcraft I: Remastered from Battle.net as usual. The mods switch on "
                "a few seconds after the game starts.\n\nRun this installer again to change options or uninstall.",
                TITLE, MB_OK | MB_ICONINFO);
}

static void browse(void)
{
    char path[600];
    BROWSEINFOA bi = {0};
    bi.hwndOwner = g_wnd;
    bi.lpszTitle = "Select the Warcraft I Remastered folder";
    bi.ulFlags = 0x41;                      /* BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE */
    void *pidl = SHBrowseForFolderA(&bi);
    if (pidl) {
        if (SHGetPathFromIDListA(pidl, path)) SetWindowTextA(g_path, path);
        CoTaskMemFree(pidl);
    }
}

static HANDLE ctl(const char *cls, const char *text, u32 style, int x, int y, int w, int h, int id, u32 ex)
{
    HANDLE c = CreateWindowExA(ex, cls, text, WS_CHILD_VISIBLE | style, x, y, w, h, g_wnd,
                               (HANDLE)(unsigned long)id, GetModuleHandleA(0), 0);
    SendMessageA(c, WM_SETFONT, (WPARAM)g_font, 1);
    return c;
}

static LRESULT WINAPI wndproc(HANDLE h, u32 msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_COMMAND) {
        switch (wp & 0xFFFF) {
        case ID_BROWSE: browse(); return 0;
        case ID_INSTALL: do_install(1); return 0;
        case ID_UNINSTALL: do_install(0); return 0;
        }
    } else if (msg == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(h, msg, wp, lp);
}

void __cdecl start(void)
{
    HANDLE inst = GetModuleHandleA(0);
    CoInitialize(0);
    g_font = GetStockObject(17);            /* DEFAULT_GUI_FONT */

    WNDCLASSEXA wc = {0};
    wc.cbSize = sizeof wc;
    wc.lpfnWndProc = wndproc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursorA(0, 32512);
    wc.hIcon = LoadIconA(0, 32512);
    wc.hbrBackground = GetSysColorBrush(15);
    wc.lpszClassName = "W1RModsInstaller";
    RegisterClassExA(&wc);

    int W = 470, H = 300;
    g_wnd = CreateWindowExA(0, wc.lpszClassName, TITLE, WS_OVERLAPPEDWINDOW_FIXED,
                            (GetSystemMetrics(0) - W) / 2, (GetSystemMetrics(1) - H) / 2, W, H, 0, 0, inst, 0);

    ctl("STATIC", "Warcraft I: Remastered folder:", 0, 16, 14, 420, 18, 0, 0);
    g_path = ctl("EDIT", "", WS_TABSTOP | ES_AUTOHSCROLL, 16, 34, 340, 22, ID_PATH, WS_EX_CLIENTEDGE);
    ctl("BUTTON", "Browse...", WS_TABSTOP, 362, 33, 80, 24, ID_BROWSE, 0);
    ctl("STATIC", "Mods:", 0, 16, 70, 420, 18, 0, 0);
    g_ghost = ctl("BUTTON", "Fix the crash after loading some saves (ghost units)", WS_TABSTOP | BS_AUTOCHECKBOX,
                  24, 90, 420, 20, ID_GHOST, 0);
    g_pan = ctl("BUTTON", "Hold the middle mouse button and drag to pan the map", WS_TABSTOP | BS_AUTOCHECKBOX,
                24, 114, 420, 20, ID_PAN, 0);
    g_astar = ctl("BUTTON", "Smarter pathfinding (A*) instead of the original", WS_TABSTOP | BS_AUTOCHECKBOX,
                  24, 138, 420, 20, ID_ASTAR, 0);
    ctl("BUTTON", "Install", WS_TABSTOP | BS_DEFPUSHBUTTON, 16, 178, 130, 30, ID_INSTALL, 0);
    ctl("BUTTON", "Uninstall", WS_TABSTOP, 156, 178, 100, 30, ID_UNINSTALL, 0);
    g_status = ctl("STATIC", "", 0, 16, 222, 430, 36, ID_STATUS, 0);

    char game[600], x86[600], ini[700];
    if (find_game(game)) {
        SetWindowTextA(g_path, game);
        status("Found the game. Pick your mods and click Install.");
    } else {
        status("Couldn't find the game automatically. Click Browse... and pick its folder.");
    }
    /* reflect current settings if already installed */
    int ghost = 1, pan = 1, astar = 1;
    if (game[0] && x86_dir(game, x86)) {
        scpy(ini, x86); scat(ini, "\\w1r_mods.ini");
        if (exists(ini)) {
            char pf[32];
            ghost = (int)GetPrivateProfileIntA("mods", "ghost_fix", 1, ini);
            pan = (int)GetPrivateProfileIntA("mods", "middle_mouse_pan", 1, ini);
            GetPrivateProfileStringA("mods", "pathfinding", "astar", pf, sizeof pf, ini);
            astar = pf[0] == 'a' || pf[0] == 'A';
            status("Mods are installed. Change options and click Install to update, or Uninstall.");
        }
    }
    SendMessageA(g_ghost, BM_SETCHECK, ghost, 0);
    SendMessageA(g_pan, BM_SETCHECK, pan, 0);
    SendMessageA(g_astar, BM_SETCHECK, astar, 0);

    ShowWindow(g_wnd, 1);
    UpdateWindow(g_wnd);
    MSG m;
    while (GetMessageA(&m, 0, 0, 0) > 0) {
        if (IsDialogMessageA(g_wnd, &m)) continue;
        TranslateMessage(&m);
        DispatchMessageA(&m);
    }
    ExitProcess(0);
}
