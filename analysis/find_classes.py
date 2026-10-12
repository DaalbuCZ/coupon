exec(open('analysis/inspect_dex.py').read().split('z=zipfile')[0])
import sys
terms=sys.argv[1:]
z=zipfile.ZipFile('Lidl.Plus.ver.17.11.6.build.1470410092.apk')
for name in z.namelist():
 if not name.endswith('.dex'):continue
 d=Dex(z.read(name)); targets={i:s for i,s in enumerate(d.ss) if any(t==s or t in s for t in terms)}
 n,o=d.pair(96)
 for i in range(n):
  p=o+i*32;co=d.u32(p+24)
  if not co:continue
  sf,co=d.uleb(co);inf,co=d.uleb(co);dm,co=d.uleb(co);vm,co=d.uleb(co)
  for j in range(sf+inf):_,co=d.uleb(co);_,co=d.uleb(co)
  for count in [dm,vm]:
   mi=0
   for j in range(count):
    delta,co=d.uleb(co);mi+=delta;_,co=d.uleb(co);code,co=d.uleb(co)
    if not code:continue
    nc=d.u32(code+12);ins=d.b[code+16:code+16+nc*2];found=set()
    for r in range(0,len(ins)-3,2):
     if ins[r]==0x1a:
      si=struct.unpack_from('<H',ins,r+2)[0]
      if si in targets:found.add(targets[si])
    if found:print(name,*d.ms[mi],json.dumps(sorted(found)))
