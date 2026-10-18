/* Minimal C runtime pieces the compiler may call implicitly (no CRT is linked). */
void *__cdecl memset(void *d, int c, unsigned n);
void *__cdecl memset(void *d, int c, unsigned n)
{
    volatile unsigned char *p = (volatile unsigned char *)d;
    while (n--) *p++ = (unsigned char)c;
    return d;
}
void *__cdecl memcpy(void *d, const void *s, unsigned n);
void *__cdecl memcpy(void *d, const void *s, unsigned n)
{
    volatile unsigned char *p = (volatile unsigned char *)d;
    const unsigned char *q = (const unsigned char *)s;
    while (n--) *p++ = *q++;
    return d;
}
