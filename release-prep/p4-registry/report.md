# P4 registry availability

## Conclusion

The registry path is available for every dependency boring pulls. The two
libraries that come from lib.haxe.org (format, formatter) install cleanly.
The reflaxe dependency resolves from lib.haxe.org to the same 3.0.0 release
the flake pins. Both reflaxe and boring install from github through the
haxelib git command. One item is blocked: boring itself is not published on
lib.haxe.org, so it can only be installed with haxelib git or haxelib dev.

## Evidence

Environment: haxe 4.3.7, haxelib 4.1.1, network reachable to lib.haxe.org
and github. Each install below ran into a clean haxelib repository.

| Dependency | Source | Result |
| --- | --- | --- |
| format 3.8.0 | lib.haxe.org | installed, 312.85 KB download |
| formatter 1.18.0 | lib.haxe.org | installed, 326.62 KB download |
| reflaxe (latest stable) | lib.haxe.org | resolves to 3.0.0 |
| reflaxe v3.0.0 | github SomeRanDev/reflaxe | installed with haxelib git |
| boring @ 766361a1 | github Losses/boring | installed with haxelib git, pulled format as a declared dependency |

The reflaxe metadata on lib.haxe.org matches the flake pin
(github:SomeRanDev/reflaxe/v3.0.0). A newer 4.0.0-beta release exists but
haxelib does not select a pre-release when the version is left empty.

## Blocking list

1. boring is not on lib.haxe.org. haxelib info boring returns
   "No such Project". There is no haxelib install boring path. The only
   install paths are haxelib git boring https://github.com/Losses/boring
   and haxelib dev boring. This blocks a plain registry install and must be
   called out in the install document.
2. haxelib 4.1.1 prefers a repository-local .haxelib directory over the
   HAXELIB_PATH environment variable when the current directory or an
   ancestor holds one. A consumer that runs haxelib install from a checkout
   with a local .haxelib must expect the local repository to win. This is a
   documentation note with no release impact.
