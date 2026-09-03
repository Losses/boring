package registry;
import registry.Json.JsonValue;
import registry.Json.JsonField;

typedef InputRecord = { path:String, content:String, inputRecord:Int };
typedef OutputFile = { path:String, content:String, outputFile:Int };
typedef RegistryConfig = { tree:String, output:String, baseUrl:String, swiftScope:String, archiveBase:String, configRecord:Int };

@:keep
class Core {
 static final USAGE="usage: generate --tree <dir> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>]";
 static function fail(x:String):Void throw new CoreException(Tree(x));
 static function configFail(x:String):Void throw new CoreException(Config(x));
 static function S(x:String):JsonValue return JString(x); static function O(x:Array<JsonField>):JsonValue return JObject(x); static function A(x:Array<JsonValue>):JsonValue return JArray(x);
 static function find(fs:Array<JsonField>,n:String):JsonValue {for(i in 0...fs.length)if(fs[i].name==n)return fs[i].value;return JNull;}
 static function get(o:JsonValue,n:String):JsonValue return Json.getField(o,n);
 /** Shape probes as return-position switches; every target lowers a
 variant switch only at return position. */
 static function jsonKind(v:JsonValue):Int return switch(v) { case JNull: 0; case JString(_): 1; case JObject(_): 2; case JArray(_): 3; case JNumber(_): 4; case JBool(_): 5; };
 static function jstring(v:JsonValue):String return switch(v) { case JString(x): x; case JObject(_): ""; case JArray(_): ""; case JNumber(_): ""; case JBool(_): ""; case JNull: ""; };
 static function jarray(v:JsonValue):Array<JsonValue> return switch(v) { case JArray(a): a; case JObject(_): []; case JString(_): []; case JNumber(_): []; case JBool(_): []; case JNull: []; };
 static function jobject(v:JsonValue):Array<JsonField> return switch(v) { case JObject(x): x; case JArray(_): []; case JString(_): []; case JNumber(_): []; case JBool(_): []; case JNull: []; };
 static function str(o:JsonValue,n:String):String {
  var v=get(o,n);
  if(jsonKind(v)!=1) { fail("missing or invalid "+n); return ""; }
  return jstring(v);
 }
 static function opt(o:JsonValue,n:String):Null<String> {
  var v=get(o,n);
  var k=jsonKind(v);
  if(k!=0&&k!=1) { fail("invalid "+n); return null; }
  if(k==0) return null;
  return jstring(v);
 }
  static function nullValue():JsonValue return JNull;
 static function readMetadata(text:String,pp:String):JsonValue {
  var result=nullValue();
  try { result=Json.read(text); }
  catch(e:JsonException) { fail(pp+": invalid JSON"); }
  return result;
 }
 static function readArtifacts(v:JsonValue,r:Release,pp:String):Bool {
  if(jsonKind(v)!=3) { fail(pp+": artifacts must be array"); return false; }
  return readArtifactArray(jarray(v),r,pp);
 }
 static function readArtifactArray(xs:Array<JsonValue>,r:Release,pp:String):Bool {
  for(xi in 0...xs.length) readArtifact(xs[xi],r,pp);
  return true;
 }
 static function readArtifact(v:JsonValue,r:Release,pp:String):Bool {
  if(jsonKind(v)!=2) { fail(pp+": invalid artifact"); return false; }
  var fs=jobject(v);
  r.artifacts.push(str(O(fs),"file"));
  r.artifactUrls.push(str(O(fs),"url"));
  return true;
 }
 static function urlOk(u:String):Bool return registry.StringTools.startsWith(u,"http://") || registry.StringTools.startsWith(u,"https://");
 static function sortStrings(a:Array<String>):Void {for(i in 1...a.length){var x=a[i],j=i-1;while(j>=0&&registry.StringTools.compare(a[j],x)>0){a[j+1]=a[j];j=j-1;}a[j+1]=x;}}
 /** Semver comparison wrapped for the Rust lowering: catching the Semver
 fault keeps every Core function on the single CoreFault error enum. */
 static function compareVersions(a:String,b:String):Int {
  var out:Null<Int>;
  try { out=Semver.compare(a,b); }
  catch(e:SemverException) { throw new CoreException(Config("invalid version in sort order")); }
  return out==null?0:out;
 }
 static function sortReleases(a:Array<Release>):Void {for(i in 1...a.length){var x=a[i],j=i-1;while(j>=0&&compareVersions(a[j].version,x.version)>0){a[j+1]=a[j];j=j-1;}a[j+1]=x;}}
 static function names(a:Array<Release>,p:String):Array<String>{var o:Array<String>=[];for(i in 0...a.length){var r=a[i];if(r.platform==p&&!registry.StringTools.has(o,r.name))o.push(r.name);}sortStrings(o);return o;}
 static function group(a:Array<Release>,p:String,n:String):Array<Release>{var o:Array<Release>=[];for(i in 0...a.length){var r=a[i];if(r.platform==p&&r.name==n)o.push(r);}sortReleases(o);return o;}
 static function latest(g:Array<Release>):String{var b:Null<Release>=null;for(i in 0...g.length){var r=g[i];if(!Semver.isPrerelease(r.version)&&(b==null||compareVersions(r.version,b.version)>0))b=r;}if(b==null)b=g[g.length-1];return b.version;}
 static function fields(r:Release):Array<JsonField>{var a:Array<JsonField>=[{name:"name",value:S(r.name)},{name:"version",value:S(r.version)}];var lic=r.license; if(lic!=null)a.push({name:"license",value:S(lic)});return a;}
 static function contentOf(records:Array<InputRecord>, path:String):String { var r=record(records,path); if(r!=null) return r.content; fail(path+": missing record"); return ""; }
 static function record(records:Array<InputRecord>, path:String):Null<InputRecord> { for (ri in 0...records.length) { var r=records[ri]; if (r.path==path) return r; } return null; }
 static function children(records:Array<InputRecord>, path:String):Array<String> { var out:Array<String>=[]; var prefix=path==""?"":path+"/"; for(ri in 0...records.length) { var r=records[ri]; if(!registry.StringTools.startsWith(r.path,prefix)) continue; var rest=r.path.substring(prefix.length), part=registry.StringTools.split(rest,"/")[0]; if(!registry.StringTools.has(out,part)) out.push(part); } sortStrings(out); return out; }
 static function scan(tree:String, records:Array<InputRecord>):Array<Release> {
  var out:Array<Release>=[]; if(records.length==0) fail(tree+": missing tree");
  var owners=children(records,""); for(oi in 0...owners.length) { var owner=owners[oi]; var op=owner; if(record(records,op)!=null) fail(tree+"/"+op+": stray file");
   var repos=children(records,op); for(repi in 0...repos.length) { var repo=repos[repi]; var rp=op+"/"+repo; if(record(records,rp)!=null || record(records,rp+"/README.md")==null) fail(tree+"/"+rp+": missing README.md"); var count=0;
    var versions=children(records,rp); for(vi in 0...versions.length) { var v=versions[vi]; if(v=="README.md") continue; count=count+1; var vp=rp+"/"+v; if(record(records,vp)!=null) fail(tree+"/"+vp+": stray file");
     var platforms=children(records,vp); for(pi in 0...platforms.length) { var p=platforms[pi]; var pp=vp+"/"+p; if(!registry.StringTools.has(["npm","cargo","pub","swift","maven"],p)) fail(tree+"/"+pp+": unknown platform"); var files=children(records,pp); if(record(records,pp)!=null || files.length!=1 || files[0]!="metadata.json") fail(tree+"/"+pp+": expected metadata.json"); var j:JsonValue=readMetadata(contentOf(records,pp+"/metadata.json"),tree+"/"+pp); var r=new Release(owner,repo,v,p,str(j,"name"),opt(j,"license"),contentOf(records,rp+"/README.md")); if(str(j,"version")!=v) fail(tree+"/"+pp+": version disagreement"); if(Semver.parse(v)==null) fail(tree+"/"+pp+": invalid version");
      if(p=="npm"){r.url=str(j,"url");r.digest=str(j,"sha512");} else if(p=="cargo"||p=="pub"){r.url=str(j,"url");r.digest=str(j,"sha256");if(p=="pub")r.pubspec=get(j,"pubspec");} else if(p=="swift"){r.archive=str(j,"archive");r.digest=str(j,"sha256");r.packageSwift=str(j,"packageSwift");} else {r.groupId=str(j,"groupId");readArtifacts(get(j,"artifacts"),r,tree+"/"+pp);} var ru2=r.url; if(ru2!=null&&!urlOk(ru2)) fail(tree+"/"+pp+": invalid URL"); out.push(r);
     }
    } if(count==0) fail(tree+"/"+rp+": repository has no versions");
   }
  } return out;
 }
 static function writeNpm(root:String,a:Array<Release>):Void {var ns=names(a,"npm");for(ni in 0...ns.length){var n=ns[ni],g=group(a,"npm",n),vs:Array<JsonField>=[];for(i in 0...g.length){var r=g[i],f=fields(r),ru=r.url,u:String=ru==null?"":ru;f.push({name:"dist",value:O([{name:"tarball",value:S(u)},{name:"integrity",value:S("sha512-"+r.digest)}])});vs.push({name:r.version,value:O(f)});}emit(root,"npm/"+registry.StringTools.split(n,"/").join("%2f"),Json.write(O([{name:"name",value:S(n)},{name:"dist-tags",value:O([{name:"latest",value:S(latest(g))}])},{name:"versions",value:O(vs)},{name:"readme",value:S(g[0].readme)}])));}}
 static function writePub(root:String,a:Array<Release>):Void {var ns=names(a,"pub");for(ni in 0...ns.length){var n=ns[ni],g=group(a,"pub",n),vs:Array<JsonValue>=[];for(i in 0...g.length){var r=g[i],ru=r.url,u:String=ru==null?"":ru,rpp=r.pubspec;vs.push(O([{name:"version",value:S(r.version)},{name:"archive_url",value:S(u)},{name:"archive_sha256",value:S(r.digest)},{name:"pubspec",value:rpp==null?JNull:rpp}]));}var rev:Array<JsonValue>=[];var vi2=g.length-1;while(vi2>=0){rev.push(vs[vi2]);vi2=vi2-1;}emit(root,"pub/api/packages/"+n,Json.write(O([{name:"name",value:S(n)},{name:"latest",value:S(latest(g))},{name:"versions",value:A(rev)}])));}}
 @:noinline static function cargoPath(n:String):String { return n.length==1 ? "1/" : n.length==2 ? "2/" : n.length==3 ? "3/"+n.substring(0,1)+"/" : n.substring(0,2)+"/"+n.substring(2,4)+"/"; }
 static function writeCargo(root:String,base:String,a:Array<Release>):Void { emit(root,"cargo/index/config.json",Json.write(O([{name:"dl",value:S(base+"/cargo/dl/{crate}-{version}.crate")}])));var ns=names(a,"cargo");for(ni in 0...ns.length){var n=ns[ni];var g=group(a,"cargo",n),lines:Array<String>=[];for(ri in 0...g.length){var r=g[ri];lines.push(Json.writeCompact(O([{name:"name",value:S(n)},{name:"vers",value:S(r.version)},{name:"deps",value:A([])},{name:"cksum",value:S(r.digest)},{name:"features",value:O([])},{name:"yanked",value:JBool(false)},{name:"v",value:JNumber(2.0)}])));}emit(root,"cargo/index/"+(n.length==1?"1/":n.length==2?"2/":n.length==3?"3/"+n.substring(0,1)+"/":n.substring(0,2)+"/"+n.substring(2,4)+"/")+n,lines.join("\n")+"\n");}}
 static function writeSwift(root:String,scope:String,a:Array<Release>):Void {
  var ns=names(a,"swift");
  for(ni in 0...ns.length) { var n=ns[ni],g=group(a,"swift",n),rs:Array<JsonField>=[];
   for(i in 0...g.length) rs.push({name:g[i].version,value:O([])});
   emit(root,"swift/"+scope+"/"+n+".json",Json.write(O([{name:"releases",value:O(rs)}])));
   for(i in 0...g.length) { var r=g[i],rps=r.packageSwift,ps:String=rps==null?"":rps; emit(root,"swift/"+scope+"/"+n+"/"+r.version+".json",Json.write(O([{name:"id",value:S(scope+"."+n)},{name:"version",value:S(r.version)},{name:"resources",value:A([O([{name:"name",value:S("source-archive")},{name:"type",value:S("application/zip")},{name:"checksum",value:S(r.digest)}])])},{name:"metadata",value:O([])}]))); emit(root,"swift/"+scope+"/"+n+"/"+r.version+"/Package.swift",ps); }
  }
 }
 static function writeMaven(root:String,a:Array<Release>):Void {
  var ns=names(a,"maven");
  for(ni in 0...ns.length) { var n=ns[ni],g=group(a,"maven",n),first=g[0],fg=first.groupId,groupId:String=fg==null?"":fg, versions:Array<String>=[];
   for(ri in 0...g.length) { var r=g[ri]; if(!registry.StringTools.has(versions,r.version)) versions.push(r.version); } sortStrings(versions);
   var path=registry.StringTools.split(groupId,".").join("/")+"/"+n, xml="<metadata>\n  <groupId>"+groupId+"</groupId>\n  <artifactId>"+n+"</artifactId>\n  <versioning>\n    <latest>"+latest(g)+"</latest>\n    <release>"+latest(g)+"</release>\n    <versions>\n";
   for(vi in 0...versions.length) { var v=versions[vi]; xml += "      <version>"+v+"</version>\n"; }
   xml += "    </versions>\n  </versioning>\n</metadata>\n"; emit(root,"maven/"+path+"/maven-metadata.xml",xml); emit(root,"maven/"+path+"/maven-metadata.xml.sha1",Sha1.hex(xml)+"\n");
  }
 }
 static function redirects(scope:String,archiveBase:String,a:Array<Release>):String {
  var lines:Array<String>=["/swift/:scope/:name/*.zip  "+archiveBase+"/swift/:scope/:name/:splat.zip  303"];
  var sn=names(a,"swift"); for(ni in 0...sn.length) { var n=sn[ni]; lines.push("/swift/"+scope+"/"+n+"  /swift/"+scope+"/"+n+".json  200"); var sg=group(a,"swift",n); for(ri in 0...sg.length) { var r=sg[ri]; lines.push("/swift/"+scope+"/"+n+"/"+r.version+"  /swift/"+scope+"/"+n+"/"+r.version+".json  200"); } }
  var cn=names(a,"cargo"); for(ni in 0...cn.length) { var n=cn[ni]; var r=group(a,"cargo",n)[0]; lines.push("/cargo/dl/"+n+"-:version.crate  https://github.com/"+r.owner+"/"+r.repo+"/releases/download/v:version/"+n+"-:version.crate  302"); }
  for(ai in 0...a.length) { var r=a[ai]; if(r.platform=="maven") for(fi in 0...r.artifacts.length) { var file=r.artifacts[fi],rg=r.groupId,gid:String=rg==null?"":rg; lines.push("/maven/"+registry.StringTools.split(gid,".").join("/")+"/"+r.name+"/:version/"+file+"  https://github.com/"+r.owner+"/"+r.repo+"/releases/download/v:version/"+file+"  302"); } }
  var moving=0; var fixed=0;
  for(li in 0...lines.length) { if(registry.StringTools.endsWith(lines[li],"303")||registry.StringTools.endsWith(lines[li],"302")) moving=moving+1; else fixed=fixed+1; }
  if(moving>100) fail("too many dynamic redirects (Cloudflare allows 100)");
  if(fixed>2000) fail("too many static redirects (Cloudflare allows 2000)");
  return lines.join("\n")+"\n";
 }
 static function validate(a:Array<Release>,scope:String):Void {
  for(i in 0...a.length) { var x=a[i]; if(x.platform=="cargo"&&x.name!=x.name.toLowerCase()) fail(x.name+": cargo name must be lowercase"); }
  for(i in 0...a.length) { var x=a[i]; for(j in 0...i) { var y=a[j]; if(x.owner==y.owner&&x.repo==y.repo&&x.version==y.version&&(x.name!=y.name||x.license!=y.license)) fail(x.owner+"/"+x.repo+"/"+x.version+": platform disagreement"); } }
  for(i in 0...a.length) { var x=a[i]; if(x.platform=="swift" && x.archive!="swift/"+scope+"/"+x.name+"/"+x.version+".zip") fail(x.owner+"/"+x.repo+"/"+x.version+": invalid Swift archive"); }
  for(i in 0...a.length) { var x=a[i]; for(j in 0...i) { var y=a[j]; if(x.platform==y.platform&&x.name==y.name&&x.version==y.version&&x.digest!=y.digest) fail(x.owner+"/"+x.repo+"/"+x.version+": digest conflict with "+y.owner+"/"+y.repo); } }
 }
 static function headers():String return "/*\n  Content-Version: 1\n/swift/:scope/:name\n  Content-Type: application/json\n/swift/:scope/:name/:version\n  Content-Type: application/json\n/swift/:scope/:name/:version/Package.swift\n  Content-Type: text/x-swift\n/pub/api/packages/*\n  Content-Type: application/vnd.pub.v2+json\n/swift/identifiers\n  Content-Type: application/json\n";
 public static var files:Array<OutputFile>=[];
 static function emit(root:String,rel:String,data:String):Void { var file:OutputFile={path:rel,content:data,outputFile:1}; files.push(file); }
 public static function parseArgs(argv:Array<String>):RegistryConfig {
  var t="",o="",b="",s="",ar="",i=0;
  while(i<argv.length){ if(i+1>=argv.length) configFail(USAGE); var flag=argv[i], value=argv[i+1]; if(value=="") configFail("empty value for "+flag); if(flag=="--tree")t=value;else if(flag=="--output")o=value;else if(flag=="--base-url")b=value;else if(flag=="--swift-scope")s=value;else if(flag=="--archive-base")ar=value;else if(flag=="--help"||flag=="-h") configFail(USAGE); else configFail("unknown flag "+flag); i+=2; }
  if(t==""||o==""||b=="") configFail("required flags missing\n"+USAGE); var treeStr:String=t, outputStr:String=o, baseUrlStr:String=b; if(!urlOk(baseUrlStr)) configFail("invalid base URL (http or https required)"); var swiftStr:String=s, archiveStr:String=ar; if(ar!=""&&!urlOk(archiveStr)) configFail("invalid archive-base URL (http or https required)"); var config:RegistryConfig={tree:treeStr,output:outputStr,baseUrl:baseUrlStr,swiftScope:swiftStr,archiveBase:archiveStr,configRecord:1}; return config;
 }
 public static function generate(records:Array<InputRecord>, config:RegistryConfig):Array<OutputFile> { files=[]; var all=scan(config.tree,records); if(names(all,"swift").length>0&&config.swiftScope=="") fail("Swift requires --swift-scope"); if(names(all,"swift").length>0&&config.archiveBase=="") fail("Swift requires --archive-base"); validate(all,config.swiftScope); writeNpm(config.output,all); writePub(config.output,all); writeCargo(config.output,config.baseUrl,all); if(names(all,"swift").length>0)writeSwift(config.output,config.swiftScope,all); writeMaven(config.output,all); emit(config.output,"swift/identifiers",Json.write(A([]))); emit(config.output,"_headers",headers()); emit(config.output,"_redirects",redirects(config.swiftScope,config.archiveBase,all)); return files; }

}