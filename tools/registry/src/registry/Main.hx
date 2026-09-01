package registry;
import registry.Platform;
import registry.Platform.Fs;
import registry.Platform.NodeProcess;
import registry.Platform.Console;
import registry.Platform.Path;
import registry.Json.JsonValue;
import registry.Json.JsonException;
import registry.Json.JsonField;

enum RegistryFault { Message(text:String); }
typedef JsonBox = { value:JsonValue };

class RegistryException extends haxe.Exception { public final error:RegistryFault; public function new(error:RegistryFault) { this.error=error; super(RegistryException.describeError(error)); } static function describeError(error:RegistryFault):String { var result=""; switch(error) { case Message(text): result=text; } return result; } }
class Main {
 static final USAGE="usage: generate --tree <dir> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>]";
 static function fail(x:String):Void throw new RegistryException(Message(x));
 static function S(x:String):JsonValue return JString(x); static function O(x:Array<JsonField>):JsonValue return JObject(x); static function A(x:Array<JsonValue>):JsonValue return JArray(x);
 static function find(fs:Array<JsonField>,n:String):JsonValue {for(i in 0...fs.length)if(fs[i].name==n)return fs[i].value;return JNull;}
 static function get(o:JsonValue,n:String):JsonValue return Json.getField(o,n);
 static function str(o:JsonValue,n:String):String { var v=get(o,n); return switch(v) { case JString(x): x; case JObject(_): fail("missing or invalid "+n); ""; case JArray(_): fail("missing or invalid "+n); ""; case JNumber(_): fail("missing or invalid "+n); ""; case JBool(_): fail("missing or invalid "+n); ""; case JNull: fail("missing or invalid "+n); ""; }; }
 static function opt(o:JsonValue,n:String):Null<String> { var v=get(o,n); return switch(v) { case JNull: null; case JString(x): x; case JObject(_): fail("invalid "+n); null; case JArray(_): fail("invalid "+n); null; case JNumber(_): fail("invalid "+n); null; case JBool(_): fail("invalid "+n); null; }; }
 static function readArtifacts(v:JsonValue,r:Release,pp:String):Bool return switch(v) {
  case JArray(xs): readArtifactArray(xs,r,pp);
  case JString(_): fail(pp+": artifacts must be array"); false;
  case JObject(_): fail(pp+": artifacts must be array"); false;
  case JNumber(_): fail(pp+": artifacts must be array"); false;
  case JBool(_): fail(pp+": artifacts must be array"); false;
  case JNull: fail(pp+": artifacts must be array"); false;
 };
 static function readArtifactArray(xs:Array<JsonValue>,r:Release,pp:String):Bool {
  for(xi in 0...xs.length) readArtifact(xs[xi],r,pp);
  return true;
 }
 static function readArtifact(v:JsonValue,r:Release,pp:String):Bool return switch(v) {
  case JObject(x): r.artifacts.push(str(O(x),"file")); r.artifactUrls.push(str(O(x),"url")); true;
  case JArray(_): fail(pp+": invalid artifact"); false;
  case JString(_): fail(pp+": invalid artifact"); false;
  case JNumber(_): fail(pp+": invalid artifact"); false;
  case JBool(_): fail(pp+": invalid artifact"); false;
  case JNull: fail(pp+": invalid artifact"); false;
 };
 static function mkdir(p:String):Void { Fs.mkdirSync(p,{recursive:true}); }
 static function put(root:String,rel:String,data:String):Void {var p=Path.join(root,rel);mkdir(Path.dirname(p));Fs.writeFileSync(p,data,"utf8");}
 static function urlOk(u:String):Bool return registry.StringTools.startsWith(u,"http://") || registry.StringTools.startsWith(u,"https://");
 static function sortStrings(a:Array<String>):Void {for(i in 1...a.length){var x=a[i],j=i-1;while(j>=0&&a[j]>x){a[j+1]=a[j];j=j-1;}a[j+1]=x;}}
 static function sortReleases(a:Array<Release>):Void {for(i in 1...a.length){var x=a[i],j=i-1;while(j>=0&&Semver.compare(a[j].version,x.version)>0){a[j+1]=a[j];j=j-1;}a[j+1]=x;}}
 static function names(a:Array<Release>,p:String):Array<String>{var o:Array<String>=[];for(i in 0...a.length){var r=a[i];if(r.platform==p&&o.indexOf(r.name)<0)o.push(r.name);}sortStrings(o);return o;}
 static function group(a:Array<Release>,p:String,n:String):Array<Release>{var o:Array<Release>=[];for(i in 0...a.length){var r=a[i];if(r.platform==p&&r.name==n)o.push(r);}sortReleases(o);return o;}
 static function latest(g:Array<Release>):String{var b:Null<Release>=null;for(i in 0...g.length){var r=g[i];if(!Semver.isPrerelease(r.version)&&(b==null||Semver.compare(r.version,b.version)>0))b=r;}if(b==null)b=g[g.length-1];return b.version;}
 static function fields(r:Release):Array<JsonField>{var a:Array<JsonField>=[{name:"name",value:S(r.name)},{name:"version",value:S(r.version)}];if(r.license!=null)a.push({name:"license",value:S(r.license)});return a;}
 static function scan(root:String):Array<Release>{var out:Array<Release>=[];if(!Fs.existsSync(root))fail(root+": missing tree");var owners=Fs.readdirSync(root);sortStrings(owners);for(oi in 0...owners.length){var owner=owners[oi],op=Path.join(root,owner);if(!Fs.statSync(op).isDirectory())fail(op+": stray file");var repos=Fs.readdirSync(op);sortStrings(repos);for(ri in 0...repos.length){var repo=repos[ri],rp=Path.join(op,repo),readme=Path.join(rp,"README.md");if(!Fs.statSync(rp).isDirectory()||!Fs.existsSync(readme))fail(rp+": missing README.md");var versions=Fs.readdirSync(rp),count=0;for(vi in 0...versions.length){var v=versions[vi];if(v=="README.md")continue;count=count+1;var vp=Path.join(rp,v);if(!Fs.statSync(vp).isDirectory())fail(vp+": stray file");var platforms=Fs.readdirSync(vp);for(pi in 0...platforms.length){var p=platforms[pi],pp=Path.join(vp,p);if(["npm","cargo","pub","swift","maven"].indexOf(p)<0)fail(pp+": unknown platform");var files=Fs.readdirSync(pp);if(!Fs.statSync(pp).isDirectory()||files.length!=1||files[0]!="metadata.json")fail(pp+": expected metadata.json");var j:JsonValue=JNull;try j=Json.read(Fs.readFileSync(Path.join(pp,"metadata.json"),"utf8"))catch(e:JsonException){fail(pp+": invalid JSON");j=JNull;}var q=get(j,p);var r=new Release(owner,repo,v,p,str(j,"name"),opt(j,"license"),Fs.readFileSync(readme,"utf8"));if(str(j,"version")!=v)fail(pp+": version disagreement");var qn=opt(q,"name");if(qn!=null&&qn!=r.name)fail(pp+": platform disagreement");Semver.require(v,pp);if(p=="npm"){r.url=str(q,"url");r.digest=str(q,"sha512");}else if(p=="cargo"||p=="pub"){r.url=str(q,"url");r.digest=str(q,"sha256");if(p=="pub")r.pubspec=get(q,"pubspec");}else if(p=="swift"){r.archive=str(q,"archive");r.digest=str(q,"sha256");r.packageSwift=str(q,"packageSwift");}else{r.groupId=str(q,"groupId");readArtifacts(get(q,"artifacts"),r,pp);}if(r.url!=null&&!urlOk(r.url))fail(pp+": invalid URL");out.push(r);}}if(count==0)fail(rp+": repository has no versions");}}return out;}
 static function writeNpm(root:String,a:Array<Release>):Void {var ns=names(a,"npm");for(ni in 0...ns.length){var n=ns[ni],g=group(a,"npm",n),vs:Array<JsonField>=[];for(i in 0...g.length){var r=g[i],f=fields(r);f.push({name:"dist",value:O([{name:"tarball",value:S(r.url)},{name:"integrity",value:S("sha512-"+r.digest)}])});vs.push({name:r.version,value:O(f)});}put(root,"npm/"+n.split("/").join("%2f"),Json.write(O([{name:"name",value:S(n)},{name:"dist-tags",value:O([{name:"latest",value:S(latest(g))}])},{name:"versions",value:O(vs)},{name:"readme",value:S(g[0].readme)}])));}}
 static function writePub(root:String,a:Array<Release>):Void {var ns=names(a,"pub");for(ni in 0...ns.length){var n=ns[ni],g=group(a,"pub",n),vs:Array<JsonValue>=[];for(i in 0...g.length){var r=g[i];vs.push(O([{name:"version",value:S(r.version)},{name:"archive_url",value:S(r.url)},{name:"archive_sha256",value:S(r.digest)},{name:"pubspec",value:r.pubspec}]));}var rev:Array<JsonValue>=[];var vi2=g.length-1;while(vi2>=0){rev.push(vs[vi2]);vi2=vi2-1;}put(root,"pub/api/packages/"+n,Json.write(O([{name:"name",value:S(n)},{name:"latest",value:S(latest(g))},{name:"versions",value:A(rev)}])));}}
 static function writeCargo(root:String,base:String,a:Array<Release>):Void {put(root,"cargo/index/config.json",Json.write(O([{name:"dl",value:S(base+"/cargo/dl/{crate}-{version}.crate")}])));var ns=names(a,"cargo");for(ni in 0...ns.length){var n=ns[ni];var g=group(a,"cargo",n),lines:Array<String>=[];for(ri in 0...g.length){var r=g[ri];lines.push(Json.writeCompact(O([{name:"name",value:S(n)},{name:"vers",value:S(r.version)},{name:"deps",value:A([])},{name:"cksum",value:S(r.digest)},{name:"features",value:O([])},{name:"yanked",value:JBool(false)},{name:"v",value:JNumber(2)}])));}var path=n.length==1?"1/":n.length==2?"2/":n.length==3?"3/"+n.charAt(0)+"/":n.substr(0,2)+"/"+n.substr(2,2)+"/";put(root,"cargo/index/"+path+n,lines.join("\n")+"\n");}}
 static function writeSwift(root:String,scope:String,a:Array<Release>):Void {
  var ns=names(a,"swift");
  for(ni in 0...ns.length) { var n=ns[ni],g=group(a,"swift",n),rs:Array<JsonField>=[];
   for(i in 0...g.length) rs.push({name:g[i].version,value:O([])});
   put(root,"swift/"+scope+"/"+n+".json",Json.write(O([{name:"releases",value:O(rs)}])));
   for(i in 0...g.length) { var r=g[i]; put(root,"swift/"+scope+"/"+n+"/"+r.version+".json",Json.write(O([{name:"id",value:S(scope+"."+n)},{name:"version",value:S(r.version)},{name:"resources",value:A([O([{name:"name",value:S("source-archive")},{name:"type",value:S("application/zip")},{name:"checksum",value:S(r.digest)}])])},{name:"metadata",value:O([])}]))); put(root,"swift/"+scope+"/"+n+"/"+r.version+"/Package.swift",r.packageSwift); }
  }
 }
 static function writeMaven(root:String,a:Array<Release>):Void {
  var ns=names(a,"maven");
  for(ni in 0...ns.length) { var n=ns[ni],g=group(a,"maven",n),groupId=g[0].groupId, versions:Array<String>=[];
   for(ri in 0...g.length) { var r=g[ri]; if(versions.indexOf(r.version)<0) versions.push(r.version); } sortStrings(versions);
   var path=groupId.split(".").join("/")+"/"+n, xml="<metadata>\n  <groupId>"+groupId+"</groupId>\n  <artifactId>"+n+"</artifactId>\n  <versioning>\n    <latest>"+latest(g)+"</latest>\n    <release>"+latest(g)+"</release>\n    <versions>\n";
   for(vi in 0...versions.length) { var v=versions[vi]; xml += "      <version>"+v+"</version>\n"; }
   xml += "    </versions>\n  </versioning>\n</metadata>\n"; put(root,"maven/"+path+"/maven-metadata.xml",xml); put(root,"maven/"+path+"/maven-metadata.xml.sha1",Sha1.hex(xml)+"\n");
  }
 }
 static function redirects(scope:String,archiveBase:String,a:Array<Release>):String {
  var lines:Array<String>=["/swift/:scope/:name/*.zip  "+archiveBase+"/swift/:scope/:name/:splat.zip  303"];
  var sn=names(a,"swift"); for(ni in 0...sn.length) { var n=sn[ni]; lines.push("/swift/"+scope+"/"+n+"  /swift/"+scope+"/"+n+".json  200"); var sg=group(a,"swift",n); for(ri in 0...sg.length) { var r=sg[ri]; lines.push("/swift/"+scope+"/"+n+"/"+r.version+"  /swift/"+scope+"/"+n+"/"+r.version+".json  200"); } }
  var cn=names(a,"cargo"); for(ni in 0...cn.length) { var n=cn[ni]; var r=group(a,"cargo",n)[0]; lines.push("/cargo/dl/"+n+"-:version.crate  https://github.com/"+r.owner+"/"+r.repo+"/releases/download/v:version/"+n+"-:version.crate  302"); }
  for(ai in 0...a.length) { var r=a[ai]; if(r.platform=="maven") for(fi in 0...r.artifacts.length) { var file=r.artifacts[fi]; lines.push("/maven/"+r.groupId.split(".").join("/")+"/"+r.name+"/:version/"+file+"  https://github.com/"+r.owner+"/"+r.repo+"/releases/download/v:version/"+file+"  302"); } }
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
 public static function main():Void {try{var av=NodeProcess.argv;if(av.length==3&&(av[2]=="--help"||av[2]=="-h")){Console.error(USAGE);NodeProcess.exit(0);}var t:Null<String>=null,o:Null<String>=null,b:Null<String>=null,s:Null<String>=null,ar:Null<String>=null,i=2;while(i<av.length){if(i+1>=av.length)fail(USAGE);var flag=av[i];if(flag=="--tree")t=av[i+1];else if(flag=="--output")o=av[i+1];else if(flag=="--base-url")b=av[i+1];else if(flag=="--swift-scope")s=av[i+1];else if(flag=="--archive-base")ar=av[i+1];else fail("unknown flag "+flag);i+=2;}if(t==null||o==null||b==null)fail("required flags missing\n"+USAGE);if(!urlOk(b))fail("invalid base URL (http or https required)");if(Fs.existsSync(o)&&Fs.readdirSync(o).length>0)fail("output directory is not empty");var all=scan(t);if(names(all,"swift").length>0&&(s==null||s==""))fail("Swift requires --swift-scope");if(names(all,"swift").length>0&&(ar==null||ar==""))fail("Swift requires --archive-base");if(ar!=null&&!urlOk(ar))fail("invalid archive-base URL (http or https required)");validate(all,s==null?"":s);mkdir(o);writeNpm(o,all);writePub(o,all);writeCargo(o,b,all);if(names(all,"swift").length>0)writeSwift(o,s,all);writeMaven(o,all);put(o,"swift/identifiers",Json.write(A([])));put(o,"_headers",headers());put(o,"_redirects",redirects(s==null?"":s,ar==null?"":ar,all));}catch(e:RegistryException){Console.error(e.message);NodeProcess.exit(1);}}
}
