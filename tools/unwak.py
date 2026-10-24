#!/usr/bin/env python3
# Unpack Noita data.wak natively on Linux (no Proton needed).
# Usage: python3 -I tools/unwak.py <Noita>/data/data.wak <out_dir>   -> files land in <out_dir>/data/...
import struct, sys, os
src, out = sys.argv[1], sys.argv[2]
with open(src, 'rb') as f:
    data = f.read()
_, count, hdr_end, _ = struct.unpack_from('<iiii', data, 0)
pos = 16
n = 0
for _ in range(count):
    off, size, plen = struct.unpack_from('<iii', data, pos); pos += 12
    path = data[pos:pos+plen].decode('utf-8'); pos += plen
    path = path.replace('\\', '/')
    if '..' in path.split('/'):
        continue
    dst = os.path.join(out, path)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'wb') as g:
        g.write(data[off:off+size])
    n += 1
print(count, n)
