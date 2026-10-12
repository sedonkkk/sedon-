#!/usr/bin/env python3
"""Create the small Pink loader ONLY after verifying a real fixed-commit Raw."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import urllib.parse
import urllib.request

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-url',required=True)
    args=parser.parse_args()
    url=urllib.parse.urlsplit(args.raw_url)
    if url.scheme!='https' or url.netloc!='raw.githubusercontent.com' or url.query or url.fragment:
        raise ValueError('Expected public HTTPS raw.githubusercontent.com URL without credentials/query')
    if not re.fullmatch(r'/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[0-9a-f]{40}/PinkDotLock\.lua',url.path):
        raise ValueError('Expected real fixed-commit URL ending in PinkDotLock.lua')
    local=(ROOT/'PinkDotLock.lua').read_bytes()
    request=urllib.request.Request(args.raw_url,headers={'Accept':'text/plain','User-Agent':'PinkDotLock-byte-verification'})
    with urllib.request.urlopen(request,timeout=30) as response:
        if response.status!=200: raise ValueError('Raw did not return HTTP 200')
        if urllib.parse.urlsplit(response.geturl()).netloc!='raw.githubusercontent.com':
            raise ValueError('Unexpected cross-domain redirect')
        remote=response.read(2*1024*1024+1)
    if remote!=local: raise ValueError('Remote payload differs from tested PinkDotLock.lua')
    loader='\n'.join((
        '-- SEDWARE: verified public payload pinned to a specific commit.',
        'local rawURL = '+json.dumps(args.raw_url),
        'print("[SEDWARE][Loader][START] Retrieving the verified payload")',
        'assert(type(loadstring)=="function", "[SEDWARE][Loader][FAIL] Host must provide a Luau-compatible loadstring")',
        'local ok, source = pcall(function() return game:HttpGet(rawURL) end)',
        'assert(ok, "[SEDWARE][Loader][HTTP FAIL] "..tostring(source))',
        'assert(type(source)=="string", "[SEDWARE][Loader][HTTP FAIL] Expected script text")',
        'local chunk, problem = loadstring(source, "PinkDotLock")',
        'assert(chunk, "[SEDWARE][Loader][COMPILE FAIL] "..tostring(problem))',
        'local ran, result = xpcall(chunk,function(err) return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err) end)',
        'assert(ran, "[SEDWARE][Loader][EXECUTION FAIL] "..tostring(result))',
        'return result', '',
    ))
    (ROOT/'PinkLoader.lua').write_text(loader,encoding='utf-8')
    output=ROOT/'build/pink-publication.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps({'rawURL':args.raw_url,'bytes':len(local),'sha256':hashlib.sha256(local).hexdigest(),
        'httpStatus':200,'remoteBytesMatch':True},indent=2)+'\n')
    line='loadstring(game:HttpGet('+json.dumps(args.raw_url)+'))()'
    (ROOT/'build/PINK_LOADSTRING.txt').write_text(line+'\n')
    print(json.dumps({'verified':True,'bytes':len(local),'sha256':hashlib.sha256(local).hexdigest()}))
    print(line)


if __name__=='__main__': main()
