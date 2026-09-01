package registry;
import registry.Platform.Fs;
import registry.Platform.NodeProcess;
import registry.Platform.Console;
class Flag { public var k:String; public var v:String; public function new(k:String,v:String) { this.k=k; this.v=v; } }
class Main {
 static final USAGE = "usage: generate --repos <file> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>] [--api-base <url>] [--token <token>] [--cache <dir>]";
 static function stop(message:String, usage:Bool):Void { Console.error(usage ? message + "\n" + USAGE : message); NodeProcess.exit(1); }
 static function val(args:Array<String>, i:Int):String { if(i+1>=args.length) { stop(USAGE,false); return ""; } return args[i+1]; }
 public static function main():Void {
  var flags:Array<Flag> = new Array<Flag>();
  while(i<args.length) {
   final raw=args[i]; if(!StringTools.startsWith(raw,"--")) { stop(USAGE,false); return; }
   var name = raw == "--repos" ? "repos" : raw == "--output" ? "output" : raw == "--token" ? "token" : raw == "--cache" ? "cache" : raw == "--base-url" ? "baseUrl" : raw == "--swift-scope" ? "swiftScope" : raw == "--archive-base" ? "archiveBase" : raw == "--api-base" ? "apiBase" : "";
   final known=["repos","output","baseUrl","swiftScope","archiveBase","apiBase","token","cache"];
   var recognized=false; for(k in 0...known.length) if(known[k]==name) recognized=true;
   if(!recognized) { stop("unknown flag "+raw+"\n"+USAGE,false); return; }
   flags.push(new Flag(name,val(args,i))); i=i+2;
  }
  function get(name:String):Null<String> { for(j in 0...flags.length) if(flags[j].k==name) return flags[j].v; return null; }
  function req(name:String,label:String):String { final x=get(name); if(x==null||x.length==0) { stop(label+" is required\n"+USAGE,false); return ""; } return x; }
  function origin(x:String,label:String):String { final y=StringTools.endsWith(x,"/")?x.substr(0,x.length-1):x; if(!StringTools.startsWith(y,"http://")&&!StringTools.startsWith(y,"https://")) { stop(label+" "+x+" must start with http:// or https://",false); return ""; } return y; }
  final repos=req("repos","--repos"); final output=req("output","--output"); origin(req("baseUrl","--base-url"),"base URL");
  final env=NodeProcess.githubToken; if((token==null||token.length==0)&&(env==null||env.length==0)) { stop("the scan requires a token: pass --token or set GITHUB_TOKEN",false); return; }
  if(!Fs.existsSync(repos)) { stop("cannot read the repository list "+repos,false); return; }
  final lines=Fs.readFileSync(repos,"utf8").split("\n"); var count=0; for(j in 0...lines.length) { final line=StringTools.trim(lines[j]); if(line.length>0&&!StringTools.startsWith(line,"#")) count=count+1; }
  if(count==0) { stop("the repository list "+repos+" holds no entry",false); return; }
  if(Fs.existsSync(output)) { if(!Fs.statSync(output).isDirectory()) { stop("the output path "+output+" is not a directory",false); return; } if(Fs.readdirSync(output).length>0) { stop("the output directory "+output+" is not empty",false); return; } }
 }
}
