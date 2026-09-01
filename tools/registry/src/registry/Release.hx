package registry;
import registry.Json.JsonValue;
class Release {
 public var owner:String; public var repo:String; public var version:String; public var name:String; public var license:Null<String>; public var readme:String; public var platform:String; public var url:Null<String>; public var digest:String; public var archive:Null<String>; public var packageSwift:Null<String>; public var pubspec:Null<JsonValue>; public var groupId:Null<String>; public var artifacts:Array<String>; public var artifactUrls:Array<String>;
 public function new(o:String,r:String,v:String,p:String,n:String,l:Null<String>,read:String){owner=o;repo=r;version=v;platform=p;name=n;license=l;readme=read;url=null;digest="";archive=null;packageSwift=null;pubspec=null;groupId=null;artifacts=[];artifactUrls=[];}
}
