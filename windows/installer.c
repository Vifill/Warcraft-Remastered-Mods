/* Windows installer for the Warcraft I: Remastered and Warcraft II: Remastered mods.
 * Finds the game, lets the user pick mods, and writes VERSION.dll + w1r_mods.ini (W1) or
 * w2r_mods.ini (W2) next to the game's exe in its x86 folder. Uninstall removes them. No
 * runtime needed; the mod DLL (the same one for both games) is embedded.
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
#define BS_AUTORADIOBUTTON 9
#define BS_DEFPUSHBUTTON 1
#define WS_GROUP 0x00020000
#define BN_CLICKED 0
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

enum { ID_PATH = 100, ID_BROWSE, ID_GHOST, ID_PAN, ID_ASTAR, ID_INSTALL, ID_UNINSTALL, ID_STATUS,
       ID_W1, ID_W2 };
static const char *TITLE = "Warcraft Remastered Mods " MOD_VERSION;

typedef struct {
    const char *name;                       /* shown to the user */
    const char *exe, *ini, *log;            /* in the x86 folder */
    const char *display, *display_not;      /* matched against installed programs */
    const char *guesses[3];
    int has_ghost;                          /* ghost_fix exists for this game */
} Game;

static const Game games[2] = {
    {"Warcraft I: Remastered", "Warcraft.exe", "w1r_mods.ini", "w1r_mods.log", "Warcraft I", "Warcraft II",
     {"C:\\Program Files (x86)\\Warcraft I Remastered", "C:\\Program Files\\Warcraft I Remastered",
      "D:\\Games\\Warcraft I Remastered"}, 1},
    {"Warcraft II: Remastered", "Warcraft II.exe", "w2r_mods.ini", "w2r_mods.log", "Warcraft II", "Warcraft III",
     {"C:\\Program Files (x86)\\Warcraft II Remastered", "C:\\Program Files\\Warcraft II Remastered",
      "D:\\Games\\Warcraft II Remastered"}, 0},
};

static HANDLE g_wnd, g_path, g_ghost, g_pan, g_astar, g_status, g_font, g_label, g_w1, g_w2;
static int g_cur;                           /* index into games[] */
static char g_paths[2][600];                /* folder per game, kept while switching */

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
static int x86_dir(const Game *g, const char *game, char *out)
{
    char t[600];
    scpy(out, game); strip_slash(out);
    scpy(t, out); scat(t, "\\x86\\"); scat(t, g->exe);
    if (exists(t)) { scat(out, "\\x86"); return 1; }
    scpy(t, out); scat(t, "\\"); scat(t, g->exe);
    return exists(t);
}

/* Look through installed programs (both registry views) for the game. */
static int find_game(const Game *g, char *out)
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
            if (contains_ci(disp, g->display) && !(g->display_not && contains_ci(disp, g->display_not)) &&
                loc[0] && x86_dir(g, loc, x)) {
                scpy(out, loc); strip_slash(out); RegCloseKey(root); return 1;
            }
        }
        RegCloseKey(root);
    }
    for (int i = 0; i < 3; i++) {
        char x[600];
        if (x86_dir(g, g->guesses[i], x)) { scpy(out, g->guesses[i]); return 1; }
    }
    return 0;
}

static void status(const char *s) { SetWindowTextA(g_status, s); }
static int checked(HANDLE h) { return SendMessageA(h, BM_GETCHECK, 0, 0) == 1; }

/* Show the current game's folder and mod settings (from its ini if the mods are installed). */
static void show_game(void)
{
    const Game *g = &games[g_cur];
    char label[100], x86[600], ini[700], msg[200];
    scpy(label, g->name); scat(label, " folder:");
    SetWindowTextA(g_label, label);
    SetWindowTextA(g_path, g_paths[g_cur]);
    ShowWindow(g_ghost, g->has_ghost ? 5 : 0);
    SendMessageA(g_w1, BM_SETCHECK, g_cur == 0, 0);
    SendMessageA(g_w2, BM_SETCHECK, g_cur == 1, 0);

    int ghost = 1, pan = 1, astar = 1, have_ini = 0;
    if (g_paths[g_cur][0] && x86_dir(g, g_paths[g_cur], x86)) {
        scpy(ini, x86); scat(ini, "\\"); scat(ini, g->ini);
        have_ini = exists(ini);
    }
    if (!g_paths[g_cur][0]) {
        scpy(msg, "Couldn't find "); scat(msg, g->name); scat(msg, " automatically. Click Browse... and pick its folder.");
        status(msg);
    } else if (have_ini) {
        char pf[32];
        ghost = (int)GetPrivateProfileIntA("mods", "ghost_fix", 1, ini);
        pan = (int)GetPrivateProfileIntA("mods", "middle_mouse_pan", 1, ini);
        GetPrivateProfileStringA("mods", "pathfinding", "astar", pf, sizeof pf, ini);
        astar = pf[0] == 'a' || pf[0] == 'A';
        status("Mods are installed. Change options and click Install to update, or Uninstall.");
    } else {
        status("Found the game. Pick your mods and click Install.");
    }
    SendMessageA(g_ghost, BM_SETCHECK, ghost, 0);
    SendMessageA(g_pan, BM_SETCHECK, pan, 0);
    SendMessageA(g_astar, BM_SETCHECK, astar, 0);
}

static void switch_game(int to)
{
    if (to == g_cur) return;
    GetWindowTextA(g_path, g_paths[g_cur], sizeof g_paths[0]);
    g_cur = to;
    show_game();
}

static void do_install(int install)
{
    const Game *g = &games[g_cur];
    char game[600], x86[600], dll[700], ini[700], log[700], msg[400];
    GetWindowTextA(g_path, game, sizeof game);
    if (!game[0] || !x86_dir(g, game, x86)) {
        scpy(msg, g->exe); scat(msg, " was not found in that folder.\n\nPick the folder where Battle.net installed ");
        scat(msg, g->name); scat(msg, " (it contains an x86 folder).");
        MessageBoxA(g_wnd, msg, TITLE, MB_OK | MB_ICONWARN);
        return;
    }
    scpy(dll, x86); scat(dll, "\\VERSION.dll");
    scpy(ini, x86); scat(ini, "\\"); scat(ini, g->ini);
    scpy(log, x86); scat(log, "\\"); scat(log, g->log);

    if (!install) {
        int had = exists(dll);
        if (had && !DeleteFileA(dll)) {
            scpy(msg, "Could not remove VERSION.dll. Close "); scat(msg, g->name); scat(msg, " and try again.");
            MessageBoxA(g_wnd, msg, TITLE, MB_OK | MB_ICONERROR);
            return;
        }
        DeleteFileA(ini); DeleteFileA(log);
        status(had ? "Mods removed. The game is back to normal." : "Mods were not installed.");
        return;
    }

    HANDLE f = CreateFileA(dll, 0x40000000, 0, 0, 2, 0x80, 0);
    if (f == (HANDLE)-1) {
        scpy(msg, "Could not write VERSION.dll.\n\nClose "); scat(msg, g->name);
        scat(msg, ", then try again. If the game is in Program Files, run this installer as administrator.");
        MessageBoxA(g_wnd, msg, TITLE, MB_OK | MB_ICONERROR);
        return;
    }
    u32 w = 0;
    BOOL ok = WriteFile(f, mod_dll, sizeof mod_dll, &w, 0) && w == sizeof mod_dll;
    CloseHandle(f);
    if (!ok) { MessageBoxA(g_wnd, "Writing VERSION.dll failed.", TITLE, MB_OK | MB_ICONERROR); return; }

    WritePrivateProfileStringA("mods", "enabled", "1", ini);
    if (g->has_ghost) WritePrivateProfileStringA("mods", "ghost_fix", checked(g_ghost) ? "1" : "0", ini);
    WritePrivateProfileStringA("mods", "middle_mouse_pan", checked(g_pan) ? "1" : "0", ini);
    WritePrivateProfileStringA("mods", "pan_speed_percent", "100", ini);
    WritePrivateProfileStringA("mods", "pathfinding", checked(g_astar) ? "astar" : "original", ini);
    WritePrivateProfileStringA("mods", "patch_delay_ms", "8000", ini);
    status("Installed! Start the game from Battle.net as usual.");
    scpy(msg, "Mods installed.\n\nStart "); scat(msg, g->name);
    scat(msg, " from Battle.net as usual. The mods switch on a few seconds after the game starts.\n\n"
              "Run this installer again to change options or uninstall.");
    MessageBoxA(g_wnd, msg, TITLE, MB_OK | MB_ICONINFO);
}

static void browse(void)
{
    char path[600], title[100];
    scpy(title, "Select the "); scat(title, games[g_cur].name); scat(title, " folder");
    BROWSEINFOA bi = {0};
    bi.hwndOwner = g_wnd;
    bi.lpszTitle = title;
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
        case ID_W1: if ((wp >> 16) == BN_CLICKED) switch_game(0); return 0;
        case ID_W2: if ((wp >> 16) == BN_CLICKED) switch_game(1); return 0;
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

    int W = 470, H = 330;
    g_wnd = CreateWindowExA(0, wc.lpszClassName, TITLE, WS_OVERLAPPEDWINDOW_FIXED,
                            (GetSystemMetrics(0) - W) / 2, (GetSystemMetrics(1) - H) / 2, W, H, 0, 0, inst, 0);

    ctl("STATIC", "Game:", 0, 16, 16, 50, 18, 0, 0);
    g_w1 = ctl("BUTTON", "Warcraft I", WS_TABSTOP | WS_GROUP | BS_AUTORADIOBUTTON, 70, 14, 110, 20, ID_W1, 0);
    g_w2 = ctl("BUTTON", "Warcraft II", BS_AUTORADIOBUTTON, 184, 14, 110, 20, ID_W2, 0);
    g_label = ctl("STATIC", "", WS_GROUP, 16, 44, 420, 18, 0, 0);
    g_path = ctl("EDIT", "", WS_TABSTOP | ES_AUTOHSCROLL, 16, 64, 340, 22, ID_PATH, WS_EX_CLIENTEDGE);
    ctl("BUTTON", "Browse...", WS_TABSTOP, 362, 63, 80, 24, ID_BROWSE, 0);
    ctl("STATIC", "Mods:", 0, 16, 100, 420, 18, 0, 0);
    g_pan = ctl("BUTTON", "Hold the middle mouse button and drag to pan the map", WS_TABSTOP | BS_AUTOCHECKBOX,
                24, 120, 420, 20, ID_PAN, 0);
    g_astar = ctl("BUTTON", "Smarter pathfinding (A*) instead of the original", WS_TABSTOP | BS_AUTOCHECKBOX,
                  24, 144, 420, 20, ID_ASTAR, 0);
    g_ghost = ctl("BUTTON", "Fix the crash after loading some saves (ghost units)", WS_TABSTOP | BS_AUTOCHECKBOX,
                  24, 168, 420, 20, ID_GHOST, 0);
    ctl("BUTTON", "Install", WS_TABSTOP | BS_DEFPUSHBUTTON, 16, 208, 130, 30, ID_INSTALL, 0);
    ctl("BUTTON", "Uninstall", WS_TABSTOP, 156, 208, 100, 30, ID_UNINSTALL, 0);
    g_status = ctl("STATIC", "", 0, 16, 252, 430, 36, ID_STATUS, 0);

    /* start on whichever game is installed (Warcraft I if both or neither) */
    int found1 = find_game(&games[0], g_paths[0]), found2 = find_game(&games[1], g_paths[1]);
    g_cur = (!found1 && found2) ? 1 : 0;
    show_game();

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
