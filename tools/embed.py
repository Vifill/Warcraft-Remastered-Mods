#!/usr/bin/env python3
"""Emit a C header embedding a file as a byte array: embed.py <file> <name>"""
import sys
data = open(sys.argv[1], 'rb').read()
name = sys.argv[2]
print(f'static const unsigned char {name}[{len(data)}] = {{')
for i in range(0, len(data), 20):
    print('  ' + ', '.join(str(b) for b in data[i:i + 20]) + ',')
print('};')
