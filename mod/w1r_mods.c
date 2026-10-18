/* Warcraft I: Remastered mods, loaded as a stand-in VERSION.dll next to x86\Warcraft.exe.
 *
 *   ghost_fix         Fixes a crash after loading saves: map tiles flagged "unit here" whose
 *                     unit is gone. The first reader clears the stale flag.
 *   middle_mouse_pan  Hold the middle mouse button and drag to pan the map.
 *   pathfinding=astar Units plan routes with A* instead of straight line + wall following.
 *
 * Built for game build 1.0.0.2762 (x86). Every patch site is checked byte for byte before
 * it is changed; a mismatch (e.g. a newer game build) skips that mod and the game runs as is.
 * The game checks its own executable at startup, so patches are applied in memory a few
 * seconds after launch instead of on disk.
 *
 * Settings: w1r_mods.ini next to this DLL. Log: w1r_mods.log.
 */
#include <stdarg.h>

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef signed char s8;
typedef short s16;
typedef void *HANDLE;
typedef int BOOL;

#define WINAPI __stdcall
__declspec(dllimport) HANDLE WINAPI LoadLibraryA(const char *);
__declspec(dllimport) void *WINAPI GetProcAddress(HANDLE, const char *);
__declspec(dllimport) HANDLE WINAPI GetModuleHandleA(const char *);
__declspec(dllimport) u32 WINAPI GetModuleFileNameA(HANDLE, char *, u32);
__declspec(dllimport) u32 WINAPI GetSystemDirectoryA(char *, u32);
__declspec(dllimport) HANDLE WINAPI CreateThread(void *, u32, u32(WINAPI *)(void *), void *, u32, u32 *);
__declspec(dllimport) BOOL WINAPI CloseHandle(HANDLE);
__declspec(dllimport) void WINAPI Sleep(u32);
__declspec(dllimport) BOOL WINAPI VirtualProtect(void *, u32, u32, u32 *);
__declspec(dllimport) BOOL WINAPI FlushInstructionCache(HANDLE, const void *, u32);
__declspec(dllimport) HANDLE WINAPI GetCurrentProcess(void);
__declspec(dllimport) u32 WINAPI GetPrivateProfileIntA(const char *, const char *, int, const char *);
__declspec(dllimport) u32 WINAPI GetPrivateProfileStringA(const char *, const char *, const char *, char *, u32, const char *);
__declspec(dllimport) HANDLE WINAPI CreateFileA(const char *, u32, u32, void *, u32, u32, HANDLE);
__declspec(dllimport) BOOL WINAPI WriteFile(HANDLE, const void *, u32, u32 *, void *);
__declspec(dllimport) BOOL WINAPI DisableThreadLibraryCalls(HANDLE);
__declspec(dllimport) s16 WINAPI GetAsyncKeyState(int);

#define GAME_BASE 0x400000u
#define PAGE_EXECUTE_READWRITE 0x40

/* ---- addresses in the game, filled in at startup from its actual base ---------------- */
static u8 *g_base;
#define REL(va) (g_base + ((u32)(va) - GAME_BASE))

u8 *g_ghost_ret, *g_ghost_free;            /* used by handlers.s */
u16 **g_tile_flags_pp;
u8 *g_pan_ret;
s16 *g_mouse_x, *g_mouse_y;
int *g_cam_x;
int g_pan_scale = 256;                      /* 256 = 1.0 */
int g_pan_last_x, g_pan_last_y;
u8 g_pan_held;
u8 *g_astar_cleanup, *g_astar_resume;
void *g_GetAsyncKeyState;

extern void ghost_handler(void), pan_handler(void), astar_handler(void);

/* ---- settings and log ----------------------------------------------------------------- */
static char g_dir[260], g_ini[300], g_logpath[300];
static HANDLE g_log = (HANDLE)-1;

static void str_copy(char *d, const char *s) { while ((*d++ = *s++)) ; }
static void str_cat(char *d, const char *s) { while (*d) d++; str_copy(d, s); }

static void log_line(const char *fmt, ...)
{
    if (g_log == (HANDLE)-1) return;
    char buf[512], *o = buf;
    va_list ap;
    va_start(ap, fmt);
    for (const char *p = fmt; *p && o < buf + 480; p++) {
        if (*p != '%') { *o++ = *p; continue; }
        p++;
        if (*p == 's') { const char *s = va_arg(ap, const char *); while (*s && o < buf + 480) *o++ = *s++; }
        else if (*p == 'x') {
            u32 v = va_arg(ap, u32);
            for (int i = 28; i >= 0; i -= 4) *o++ = "0123456789abcdef"[(v >> i) & 15];
        } else if (*p == 'd') {
            int v = va_arg(ap, int); char t[12]; int n = 0;
            if (v < 0) { *o++ = '-'; v = -v; }
            do t[n++] = (char)('0' + v % 10); while ((v /= 10) && n < 11);
            while (n) *o++ = t[--n];
        }
    }
    va_end(ap);
    *o++ = '\r'; *o++ = '\n';
    u32 w;
    WriteFile(g_log, buf, (u32)(o - buf), &w, 0);
}

/* ---- A* pathfinder -------------------------------------------------------------------- */
#define W 64
#define N (W * W)
#define GOAL_FLAG 0x8000
#define UNIT_FLAG 0x100
#define MAX_STEPS 20
#define HEAP_CAP 16384

static u16 as_g[N], as_seen[N], as_done[N], as_gen;
static u8 as_pdir[N], as_trail[N];
static u32 as_heap[HEAP_CAP];
static u32 as_found, as_fallback;           /* counters, logged on exit */

static int passable(int idx)
{
    u16 f = (*g_tile_flags_pp)[idx];
    if (f & UNIT_FLAG) {
        u8 *u = (*(u8 ***)REL(0x735324))[idx];
        u8 *ally = *(u8 **)REL(0x747894);
        s16(__cdecl *moving)(u8 *) = (s16(__cdecl *)(u8 *))REL(0x4EE3C0);
        if (!u || ally[u[0x1E]] || moving(u))
            f &= ~UNIT_FLAG;
    }
    return (f & *(u16 *)REL(0x74788C)) == 0;
}

static u32 heur(int x, int y, int gx, int gy)
{
    int dx = x > gx ? x - gx : gx - x, dy = y > gy ? y - gy : gy - y;
    int lo = dx < dy ? dx : dy, hi = dx < dy ? dy : dx;
    return 10 * hi + 4 * lo;                /* octile: straight 10, diagonal 14 */
}

/* Called from astar_handler with the unit (edi in the game's findPath). Returns 1 when it
 * wrote a path, 0 to let the original search run. */
int __cdecl w1r_astar(u8 *unit)
{
    const s8 *ddx = (const s8 *)REL(0x70914C), *ddy = (const s8 *)REL(0x709154);
    u16 *flags = *g_tile_flags_pp;
    u16 gen = (u16)(as_gen + 1);
    if (gen == 0) {
        for (int i = 0; i < N; i++) as_seen[i] = as_done[i] = 0;
        gen = 1;
    }
    as_gen = gen;

    int sx = *(u16 *)(unit + 0x0A), sy = *(u16 *)(unit + 0x0C);
    int gx = *(u16 *)REL(0x747888), gy = *(u16 *)REL(0x74788A);
    if (sx >= W || sy >= W) { as_fallback++; return 0; }
    int start = sy * W + sx, hn = 0, found = -1, pops = 0;
    as_g[start] = 0; as_seen[start] = gen;
    as_heap[hn++] = (heur(sx, sy, gx, gy) << 12) | start;

    while (hn > 0 && pops < N) {
        u32 top = as_heap[0], last = as_heap[--hn];
        int i = 0;
        for (;;) {
            int c = 2 * i + 1;
            if (c >= hn) break;
            if (c + 1 < hn && as_heap[c + 1] < as_heap[c]) c++;
            if (as_heap[c] >= last) break;
            as_heap[i] = as_heap[c]; i = c;
        }
        if (hn > 0) as_heap[i] = last;

        int cur = top & 0xFFF;
        if (as_done[cur] == gen) continue;
        as_done[cur] = gen;
        pops++;
        if (cur != start && (flags[cur] & GOAL_FLAG)) { found = cur; break; }

        int cx = cur & (W - 1), cy = cur >> 6;
        for (int d = 0; d < 8; d++) {
            int nx = cx + ddx[d], ny = cy + ddy[d];
            if ((unsigned)nx >= W || (unsigned)ny >= W) continue;
            int n = ny * W + nx;
            if (as_done[n] == gen || !passable(n)) continue;
            u32 ng = as_g[cur] + ((d & 1) ? 14 : 10);
            if (ng > 0xFFFF || (as_seen[n] == gen && ng >= as_g[n])) continue;
            as_seen[n] = gen; as_g[n] = (u16)ng; as_pdir[n] = (u8)d;
            if (hn >= HEAP_CAP) continue;
            u32 key = ((ng + heur(nx, ny, gx, gy)) << 12) | n;
            int j = hn++;
            while (j > 0) {
                int p = (j - 1) >> 1;
                if (as_heap[p] <= key) break;
                as_heap[j] = as_heap[p]; j = p;
            }
            as_heap[j] = key;
        }
    }
    if (found < 0) { as_fallback++; return 0; }

    int len = 0, cur = found;
    while (cur != start && len < N) {
        u8 d = as_pdir[cur];
        as_trail[len++] = d;
        cur -= ddy[d] * W + ddx[d];
    }
    if (cur != start) { as_fallback++; return 0; }

    u8 *path = unit + 0x22;
    int k = 0;
    for (; k < MAX_STEPS && k < len; k++) path[k] = as_trail[len - 1 - k];
    for (; k < MAX_STEPS; k++) path[k] = 0xFE;
    unit[0x50] = 0;
    as_found++;
    return 1;
}

/* ---- patching ------------------------------------------------------------------------- */
static int bytes_equal(const u8 *a, const u8 *b, int n)
{
    for (int i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

/* Replace `len` bytes at game address `va` (which must equal `expect`) with a jump to `to`. */
static int install_jump(const char *name, u32 va, const u8 *expect, int len, void (*to)(void))
{
    u8 *site = REL(va);
    if (!bytes_equal(site, expect, len)) {
        log_line("%s: unexpected bytes at %x, skipped (different game build?)", name, va);
        return 0;
    }
    u32 old;
    if (!VirtualProtect(site, len, PAGE_EXECUTE_READWRITE, &old)) {
        log_line("%s: VirtualProtect failed, skipped", name);
        return 0;
    }
    for (int i = 5; i < len; i++) site[i] = 0x90;
    *(u32 *)(site + 1) = (u32)((u8 *)to - (site + 5));
    site[0] = 0xE9;
    VirtualProtect(site, len, old, &old);
    FlushInstructionCache(GetCurrentProcess(), site, len);
    log_line("%s: installed", name);
    return 1;
}

static int is_on(const char *key, int def) { return (int)GetPrivateProfileIntA("mods", key, def, g_ini); }

static u32 WINAPI patch_thread(void *arg)
{
    (void)arg;
    u32 delay = GetPrivateProfileIntA("mods", "patch_delay_ms", 8000, g_ini);
    Sleep(delay);                           /* let the game's startup self-check finish */

    g_base = (u8 *)GetModuleHandleA(0);
    log_line("game base %x, patching after %d ms", (u32)g_base, (int)delay);
    g_tile_flags_pp = (u16 **)REL(0x735318);

    if (is_on("ghost_fix", 1)) {
        static const u8 ghost[] = {0x0f, 0xb6, 0x4a, 0x1e, 0x80, 0x3c, 0x01, 0x00};
        g_ghost_ret = REL(0x508C93);
        g_ghost_free = REL(0x508CA3);
        install_jump("ghost_fix", 0x508C8B, ghost, sizeof ghost, ghost_handler);
    }
    if (is_on("middle_mouse_pan", 1)) {
        u8 pan[9] = {0x0f, 0xbf, 0xce, 0x01, 0x0d};   /* movsx ecx,si; add [cam_x],ecx */
        *(u32 *)(pan + 5) = (u32)REL(0x747698);
        g_mouse_x = (s16 *)REL(0x743CC8);
        g_mouse_y = (s16 *)REL(0x743CCA);
        g_cam_x = (int *)REL(0x747698);
        g_pan_ret = REL(0x4F247D);
        g_GetAsyncKeyState = (void *)GetAsyncKeyState;
        int speed = (int)GetPrivateProfileIntA("mods", "pan_speed_percent", 100, g_ini);
        if (speed < 10) speed = 10;
        if (speed > 500) speed = 500;
        g_pan_scale = speed * 256 / 100;
        install_jump("middle_mouse_pan", 0x4F2474, pan, sizeof pan, pan_handler);
    }
    char pf[32];
    GetPrivateProfileStringA("mods", "pathfinding", "astar", pf, sizeof pf, g_ini);
    if (pf[0] == 'a' || pf[0] == 'A') {
        static const u8 astar[] = {0x8d, 0x45, 0x08, 0x68, 0xff, 0xff, 0x00, 0x00};
        g_astar_cleanup = REL(0x508AD2);
        g_astar_resume = REL(0x50897A);
        install_jump("pathfinding_astar", 0x508972, astar, sizeof astar, astar_handler);
    } else {
        log_line("pathfinding: original");
    }
    return 0;
}

/* ---- VERSION.dll forwarding ----------------------------------------------------------- */
#define VERSION_FUNCS(X) X(GetFileVersionInfoA) X(GetFileVersionInfoByHandle) X(GetFileVersionInfoExA) \
    X(GetFileVersionInfoExW) X(GetFileVersionInfoSizeA) X(GetFileVersionInfoSizeExA)                    \
    X(GetFileVersionInfoSizeExW) X(GetFileVersionInfoSizeW) X(GetFileVersionInfoW) X(VerFindFileA)     \
    X(VerFindFileW) X(VerInstallFileA) X(VerInstallFileW) X(VerLanguageNameA) X(VerLanguageNameW)      \
    X(VerQueryValueA) X(VerQueryValueW)

#define DECLARE_PTR(n) void *p_##n;
VERSION_FUNCS(DECLARE_PTR)

static void load_real_version(void)
{
    char path[300];
    u32 n = GetSystemDirectoryA(path, 260);
    if (!n || n >= 260) return;
    str_cat(path, "\\version.dll");
    HANDLE h = LoadLibraryA(path);
    if (!h) return;
#define RESOLVE(n) p_##n = GetProcAddress(h, #n);
    VERSION_FUNCS(RESOLVE)
}

BOOL WINAPI DllMain(HANDLE inst, u32 reason, void *reserved)
{
    (void)reserved;
    if (reason != 1) return 1;              /* DLL_PROCESS_ATTACH */
    DisableThreadLibraryCalls(inst);
    load_real_version();

    u32 n = GetModuleFileNameA(inst, g_dir, 260);
    while (n && g_dir[n - 1] != '\\' && g_dir[n - 1] != '/') n--;
    g_dir[n] = 0;
    str_copy(g_ini, g_dir); str_cat(g_ini, "w1r_mods.ini");
    str_copy(g_logpath, g_dir); str_cat(g_logpath, "w1r_mods.log");

    /* only patch the game itself, not other programs that happen to load this DLL */
    char exe[260];
    u32 m = GetModuleFileNameA(0, exe, 260);
    const char *base = exe + m;
    while (base > exe && base[-1] != '\\' && base[-1] != '/') base--;
    const char *want = "warcraft.exe";
    int match = 1;
    for (int i = 0; ; i++) {
        char c = base[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
        if (c != want[i]) { match = 0; break; }
        if (!c) break;
    }
    if (!match || !GetPrivateProfileIntA("mods", "enabled", 1, g_ini)) return 1;

    g_log = CreateFileA(g_logpath, 0x40000000 /* GENERIC_WRITE */, 1, 0, 2 /* CREATE_ALWAYS */, 0x80, 0);
    log_line("Warcraft I Remastered mods v%s loaded", MOD_VERSION);
    HANDLE t = CreateThread(0, 0, patch_thread, 0, 0, 0);
    if (t) CloseHandle(t);
    return 1;
}
