import zipfile,struct,json,pathlib
class Dex:
 def __init__(self,b):
  self.b=b; self.ss=[]
  n,o=self.pair(56)
  for i in range(n):
   p=self.u32(o+4*i); _,p=self.uleb(p); self.ss.append(b[p:b.index(0,p)].decode('utf-8','replace'))
  n,o=self.pair(64);self.ts=[self.ss[self.u32(o+4*i)] for i in range(n)]
  n,o=self.pair(88);self.ms=[]
  for i in range(n):
   c,pr,s=struct.unpack_from('<HHI',b,o+i*8);self.ms.append((self.ts[c],self.ss[s]))
 def u32(self,p):return struct.unpack_from('<I',self.b,p)[0]
 def pair(self,p):return struct.unpack_from('<II',self.b,p)
 def uleb(self,p):
  v=0;s=0
  while True:
   c=self.b[p];p+=1;v|=(c&127)<<s;s+=7
   if c<128:return v,p
 def val(self,p):
  h=self.b[p];p+=1;t=h&31;n=(h>>5)+1
  if t==0x1c:
   k,p=self.uleb(p);a=[]
   for _ in range(k):v,p=self.val(p);a.append(v)
   return a,p
  if t==0x1d:return self.ann(p)
  if t==0x1e:return None,p
  if t==0x1f:return bool(h>>5),p
  v=int.from_bytes(self.b[p:p+n],'little');p+=n
  if t==0x17:v=self.ss[v]
  elif t==0x18:v=self.ts[v]
  return v,p
 def ann(self,p):
  t,p=self.uleb(p);n,p=self.uleb(p);a={'type':self.ts[t]}
  for _ in range(n):
   s,p=self.uleb(p);v,p=self.val(p);a[self.ss[s]]=v
  return a,p
 def aset(self,p):
  if not p:return []
  return [self.ann(self.u32(p+4+i*4)+1)[0] for i in range(self.u32(p))]
 def methods(self):
  n,o=self.pair(96)
  for i in range(n):
   p=o+i*32; c=self.ts[self.u32(p)];a=self.u32(p+20)
   if not a:continue
   ca,nf,nm,np=struct.unpack_from('<IIII',self.b,a);p=a+16+nf*8
   for j in range(nm):
    mi,ao=self.pair(p+j*8);anns=self.aset(ao)
    if not any(x['type'] in HTTP_TYPES for x in anns):continue
    params=[];pp=p+nm*8
    for k in range(np):
     pi,po=self.pair(pp+k*8)
     if pi==mi:params=[self.aset(self.u32(po+4+r*4)) for r in range(self.u32(po))]
    yield {'class':c,'method':self.ms[mi][1],'annotations':anns,'parameters':params}
HTTP_TYPES={'Lk7c;':'GET','Lgrk;':'POST','Lis7;':'DELETE','Lzqk;':'PATCH','Ljrk;':'PUT'}
z=zipfile.ZipFile('Lidl.Plus.ver.17.11.6.build.1470410092.apk');rs=[]
for name in z.namelist():
 if name.endswith('.dex'):
  for r in Dex(z.read(name)).methods():r['dex']=name; r['http']=[{'method':HTTP_TYPES[a['type']], 'path':a.get('value','')} for a in r['annotations'] if a['type'] in HTTP_TYPES]; rs.append(r)
pathlib.Path('analysis/http-methods.json').write_text(json.dumps(rs,indent=2))
print('Extracted HTTP method definitions:',len(rs))
