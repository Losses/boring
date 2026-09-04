package tests;

import haxe.Int64;
import haxe.crypto.Xxh128;
import haxe.io.Bytes;
import std.Test;

class Xxh128Tests {
	@:test("xxh128 vectors") public static function vectors():Void {
		final names = ["empty","abc","digits","bytes0to255","len1","len16","len17","len63","len64","len65","len127","len128","len129","len239","len240","len241","len1003","len1004"];
		final zeros = ["99aa06d3014798d86001c324468d497f","06b05ab6733a618578af5f94892f3950","33119477ede5dcd5e9716427681d5860","f1f8a93f50849ac39408a4433b952d71","495b62073ef70ca44c5cca45d0f4811f","650fe308c566747df853dd94614dfa07","18217300b5132d5a78c349fe81b2f26c","44e1980eb144e6c887e6bb29553b8e31","f9bfa77da0891a9636c5f7e547426bc4","5642c5d38e6e787dd0d1d7884590a330","3117b681087b4ef48a02b1f75c556ac3","b4f87b99d2db8a511e04fad9f0cacb4d","6881633650cd8924c51bc887976aef63","75acb2ecd970b3996df5c761356a5057","de57aab31e77a2ff93e173833f75ab66","92b991a7192f3f080b3b630948ce4a00","bafed907a8f0a7fc3b04366922cb2092","8e59ee35f0bfba41615323259915e8d0"];
		final seeds = ["45ef6ddc7afb225af9ece1036ecbb2ed","bb4cc72753e031f87dea5da88765fa10","5fecf8195a8aab7bb430dbfd0dcc4dbf","52939522310167f94cde6a4cced14c30","0a5cf80e139619eb69f37fe502a5ce84","3409282a2e6b552577e70831c44fa8ed","c151ba2dce26996928dd000337d05c67","177626058d93d40a4da834bde7b7a5cd","09f0ffea80895e7a54d1df42ab670f66","d7a6a1b1fe5a2bde28ea12793da74abe","b784e11e111e0588a12596a770134ca3","e3cabc8eb05e6d55b200e7defab492b1","772b3efa7395f15a49af531b849119ae","01b544d556827049ea1ea4e65c5b6fe5","5fd4ae3ed0b81ce4e01fb769d86c4a6b","9aaa3aebc66693bd69954910e268d78e","516e0784e679411e62dcc6c0c4d07c64","077b20a97d095d75f5a84cc411e1b87e"];
		for(i in 0...names.length){final d=CryptoTestSupport.data(names[i]); final z=Xxh128.make(d,Int64.ofInt(0)); final q=Xxh128.make(d,Int64.make(0x9E3779B1,0x85EBCA87)); Test.equals(zeros[i].substr(0,16),CryptoTestSupport.i64Hex(z.high)); Test.equals(zeros[i].substr(16),CryptoTestSupport.i64Hex(z.low)); Test.equals(seeds[i].substr(0,16),CryptoTestSupport.i64Hex(q.high)); Test.equals(seeds[i].substr(16),CryptoTestSupport.i64Hex(q.low));}
	}
}
