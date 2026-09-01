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
 static function str(o:JsonValue,n:String):String return "";
 static function opt(o:JsonValue,n:String):Null<String> return null;
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
 static function scan(root:String):Array<Release>{var out:Array<Release>=[];if(!Fs.existsSync(root))fail(root+": missing tree");var owners=Fs.readdirSync(root);sortStrings(owners);for(oi in 0...owners.length){var owner=owners[oi],op=Path.join(root,owner);if(!Fs.statSync(op).isDirectory())fail(op+": stray file");var repos=Fs.readdirSync(op);sortStrings(repos);for(ri in 0...repos.length){var repo=repos[ri],rp=Path.join(op,repo),readme=Path.join(rp,"README.md");if(!Fs.statSync(rp).isDirectory()||!Fs.existsSync(readme))fail(rp+": missing README.md");var versions=Fs.readdirSync(rp),count=0;for(vi in 0...versions.length){var v=versions[vi];if(v=="README.md")continue;count=count+1;var vp=Path.join(rp,v);if(!Fs.statSync(vp).isDirectory())fail(vp+": stray file");var platforms=Fs.readdirSync(vp);for(pi in 0...platforms.length){var p=platforms[pi],pp=Path.join(vp,p);if(["npm","cargo","pub","swift","maven"].indexOf(p)<0)fail(pp+": unknown platform");var files=Fs.readdirSync(pp);if(!Fs.statSync(pp).isDirectory()||files.length!=1||files[0]!="metadata.json")fail(pp+": expected metadata.json");var j:JsonValue=JNull;try j=Json.read(Fs.readFileSync(Path.join(pp,"metadata.json"),"utf8"))catch(e:JsonException){fail(pp+": invalid JSON");j=JNull;}var r=new Release(owner,repo,v,p,str(j,"name"),opt(j,"license"),Fs.readFileSync(readme,"utf8"));if(str(j,"version")!=v)fail(pp+": version disagreement");Semver.require(v,pp);if(p=="npm"){r.url=str(j,"url");r.digest=str(j,"sha512");}else if(p=="cargo"||p=="pub"){r.url=str(j,"url");r.digest=str(j,"sha256");if(p=="pub")r.pubspec=get(j,"pubspec");}else if(p=="swift"){r.archive=str(j,"archive");r.digest=str(j,"sha256");r.packageSwift=str(j,"packageSwift");}else{r.groupId=str(j,"groupId");readArtifacts(get(j,"artifacts"),r,pp);}if(r.url!=null&&!urlOk(r.url))fail(pp+": invalid URL");out.push(r);}}if(count==0)fail(rp+": repository has no versions");}}return out;}
 static function writeNpm(root:String,a:Array<Release>):Void {var ns=names(a,"npm");for(ni in 0...ns.length){var n=ns[ni],g=group(a,"npm",n),vs:Array<JsonField>=[];for(i in 0...g.length){var r=g[i],f=fields(r);f.push({name:"dist",value:O([{name:"tarball",value:S(r.url)},{name:"integrity",value:S("sha512-"+r.digest)}])});vs.push({name:r.version,value:O(f)});}put(root,"npm/"+n.split("/").join("%2f"),Json.write(O([{name:"name",value:S(n)},{name:"dist-tags",value:O([{name:"latest",value:S(latest(g))}])},{name:"versions",value:O(vs)},{name:"readme",value:S(g[0].readme)}])));}}
 static function writePub(root:String,a:Array<Release>):Void {var ns=names(a,"pub");for(ni in 0...ns.length){var n=ns[ni],g=group(a,"pub",n),vs:Array<JsonValue>=[];for(i in 0...g.length){var r=g[i];vs.push(O([{name:"version",value:S(r.version)},{name:"archive_url",value:S(r.url)},{name:"archive_sha256",value:S(r.digest)},{name:"pubspec",value:r.pubspec}]));}var rev=vs.copy();rev.reverse();put(root,"pub/api/packages/"+n,Json.write(O([{name:"name",value:S(n)},{name:"latest",value:S(latest(g))},{name:"versions",value:A(rev)}])));}}
 static function writeCargo(root:String,base:String,a:Array<Release>):Void {put(root,"cargo/index/config.json",Json.write(O([{name:"dl",value:S(base+"/cargo/dl/{crate}-{version}.crate")}])));var ns=names(a,"cargo");for(ni in 0...ns.length){var n=ns[ni];if(n!=n.toLowerCase())fail(n+": uppercase cargo name");var g=group(a,"cargo",n),lines:Array<String>=[];for(ri in 0...g.length){var r=g[ri];lines.push(registry.StringTools.trim(Json.write(O([{name:"name",value:S(n)},{name:"vers",value:S(r.version)},{name:"deps",value:A([])},{name:"cksum",value:S(r.digest)},{name:"features",value:O([])},{name:"yanked",value:JBool(false)},{name:"v",value:JNumber(2)}]))));}var path=n.length==1?"1/":n.length==2?"2/":n.length==3?"3/"+n.charAt(0)+"/":n.substr(0,2)+"/"+n.substr(2,2)+"/";put(root,"cargo/index/"+path+n,lines.join("\n")+"\n");}}
 static function headers():String return "/*\n  Content-Version: 1\n/swift/:scope/:name\n  Content-Type: application/json\n/swift/:scope/:name/:version\n  Content-Type: application/json\n/swift/:scope/:name/:version/Package.swift\n  Content-Type: text/x-swift\n/pub/api/packages/*\n  Content-Type: application/vnd.pub.v2+json\n/swift/identifiers\n  Content-Type: application/json\n";
 public static function main():Void {try{var av=NodeProcess.argv,t:Null<String>=null,o:Null<String>=null,b:Null<String>=null,s:Null<String>=null,ar:Null<String>=null,i=2;while(i<av.length){if(i+1>=av.length)fail(USAGE);var flag=av[i];if(flag=="--tree")t=av[i+1];else if(flag=="--output")o=av[i+1];else if(flag=="--base-url")b=av[i+1];else if(flag=="--swift-scope")s=av[i+1];else if(flag=="--archive-base")ar=av[i+1];else fail("unknown flag "+flag);i+=2;}if(t==null||o==null||b==null)fail("required flags missing\n"+USAGE);if(!urlOk(b))fail("invalid base URL");if(Fs.existsSync(o)&&Fs.readdirSync(o).length>0)fail("output directory is not empty");var all=scan(t);if(names(all,"swift").length>0&&(s==null||ar==null))fail("Swift requires --swift-scope and --archive-base");mkdir(o);writeNpm(o,all);writePub(o,all);writeCargo(o,b,all);put(o,"swift/identifiers",Json.write(A([])));put(o,"_headers",headers());put(o,"_redirects","");}catch(e:RegistryException){Console.error(e.message);NodeProcess.exit(1);}}
}
