package tests;

import haxe.crypto.Crc;
import std.Test;

class CrcTests {
    @:test("crc1 vectors")
    public static function crc1Vectors():Void {
        Test.equals(0, Crc.crc1(CryptoTestSupport.data("empty")));
        Test.equals(38, Crc.crc1(CryptoTestSupport.data("abc")));
        Test.equals(221, Crc.crc1(CryptoTestSupport.data("digits")));
        Test.equals(128, Crc.crc1(CryptoTestSupport.data("bytes0to255")));
        Test.equals(7, Crc.crc1(CryptoTestSupport.data("len1")));
        Test.equals(248, Crc.crc1(CryptoTestSupport.data("len16")));
        Test.equals(239, Crc.crc1(CryptoTestSupport.data("len17")));
        Test.equals(56, Crc.crc1(CryptoTestSupport.data("len63")));
        Test.equals(224, Crc.crc1(CryptoTestSupport.data("len64")));
        Test.equals(167, Crc.crc1(CryptoTestSupport.data("len65")));
        Test.equals(88, Crc.crc1(CryptoTestSupport.data("len127")));
        Test.equals(192, Crc.crc1(CryptoTestSupport.data("len128")));
        Test.equals(71, Crc.crc1(CryptoTestSupport.data("len129")));
        Test.equals(144, Crc.crc1(CryptoTestSupport.data("len239")));
        Test.equals(136, Crc.crc1(CryptoTestSupport.data("len240")));
        Test.equals(159, Crc.crc1(CryptoTestSupport.data("len241")));
        Test.equals(102, Crc.crc1(CryptoTestSupport.data("len1003")));
        Test.equals(226, Crc.crc1(CryptoTestSupport.data("len1004")));
    }

    @:test("crc8 vectors")
    public static function crc8Vectors():Void {
        Test.equals(0, Crc.crc8(CryptoTestSupport.data("empty")));
        Test.equals(95, Crc.crc8(CryptoTestSupport.data("abc")));
        Test.equals(244, Crc.crc8(CryptoTestSupport.data("digits")));
        Test.equals(20, Crc.crc8(CryptoTestSupport.data("bytes0to255")));
        Test.equals(21, Crc.crc8(CryptoTestSupport.data("len1")));
        Test.equals(166, Crc.crc8(CryptoTestSupport.data("len16")));
        Test.equals(176, Crc.crc8(CryptoTestSupport.data("len17")));
        Test.equals(79, Crc.crc8(CryptoTestSupport.data("len63")));
        Test.equals(187, Crc.crc8(CryptoTestSupport.data("len64")));
        Test.equals(115, Crc.crc8(CryptoTestSupport.data("len65")));
        Test.equals(121, Crc.crc8(CryptoTestSupport.data("len127")));
        Test.equals(119, Crc.crc8(CryptoTestSupport.data("len128")));
        Test.equals(222, Crc.crc8(CryptoTestSupport.data("len129")));
        Test.equals(186, Crc.crc8(CryptoTestSupport.data("len239")));
        Test.equals(201, Crc.crc8(CryptoTestSupport.data("len240")));
        Test.equals(20, Crc.crc8(CryptoTestSupport.data("len241")));
        Test.equals(21, Crc.crc8(CryptoTestSupport.data("len1003")));
        Test.equals(24, Crc.crc8(CryptoTestSupport.data("len1004")));
    }

    @:test("crc81wire vectors")
    public static function crc81wireVectors():Void {
        Test.equals(0, Crc.crc81wire(CryptoTestSupport.data("empty")));
        Test.equals(66, Crc.crc81wire(CryptoTestSupport.data("abc")));
        Test.equals(161, Crc.crc81wire(CryptoTestSupport.data("digits")));
        Test.equals(24, Crc.crc81wire(CryptoTestSupport.data("bytes0to255")));
        Test.equals(131, Crc.crc81wire(CryptoTestSupport.data("len1")));
        Test.equals(12, Crc.crc81wire(CryptoTestSupport.data("len16")));
        Test.equals(84, Crc.crc81wire(CryptoTestSupport.data("len17")));
        Test.equals(191, Crc.crc81wire(CryptoTestSupport.data("len63")));
        Test.equals(30, Crc.crc81wire(CryptoTestSupport.data("len64")));
        Test.equals(203, Crc.crc81wire(CryptoTestSupport.data("len65")));
        Test.equals(211, Crc.crc81wire(CryptoTestSupport.data("len127")));
        Test.equals(18, Crc.crc81wire(CryptoTestSupport.data("len128")));
        Test.equals(46, Crc.crc81wire(CryptoTestSupport.data("len129")));
        Test.equals(143, Crc.crc81wire(CryptoTestSupport.data("len239")));
        Test.equals(123, Crc.crc81wire(CryptoTestSupport.data("len240")));
        Test.equals(198, Crc.crc81wire(CryptoTestSupport.data("len241")));
        Test.equals(157, Crc.crc81wire(CryptoTestSupport.data("len1003")));
        Test.equals(183, Crc.crc81wire(CryptoTestSupport.data("len1004")));
    }

    @:test("crc8dvbs2 vectors")
    public static function crc8dvbs2Vectors():Void {
        Test.equals(0, Crc.crc8dvbs2(CryptoTestSupport.data("empty")));
        Test.equals(90, Crc.crc8dvbs2(CryptoTestSupport.data("abc")));
        Test.equals(188, Crc.crc8dvbs2(CryptoTestSupport.data("digits")));
        Test.equals(202, Crc.crc8dvbs2(CryptoTestSupport.data("bytes0to255")));
        Test.equals(84, Crc.crc8dvbs2(CryptoTestSupport.data("len1")));
        Test.equals(86, Crc.crc8dvbs2(CryptoTestSupport.data("len16")));
        Test.equals(158, Crc.crc8dvbs2(CryptoTestSupport.data("len17")));
        Test.equals(25, Crc.crc8dvbs2(CryptoTestSupport.data("len63")));
        Test.equals(204, Crc.crc8dvbs2(CryptoTestSupport.data("len64")));
        Test.equals(131, Crc.crc8dvbs2(CryptoTestSupport.data("len65")));
        Test.equals(217, Crc.crc8dvbs2(CryptoTestSupport.data("len127")));
        Test.equals(204, Crc.crc8dvbs2(CryptoTestSupport.data("len128")));
        Test.equals(30, Crc.crc8dvbs2(CryptoTestSupport.data("len129")));
        Test.equals(79, Crc.crc8dvbs2(CryptoTestSupport.data("len239")));
        Test.equals(77, Crc.crc8dvbs2(CryptoTestSupport.data("len240")));
        Test.equals(153, Crc.crc8dvbs2(CryptoTestSupport.data("len241")));
        Test.equals(84, Crc.crc8dvbs2(CryptoTestSupport.data("len1003")));
        Test.equals(141, Crc.crc8dvbs2(CryptoTestSupport.data("len1004")));
    }

    @:test("crc16 vectors")
    public static function crc16Vectors():Void {
        Test.equals(0, Crc.crc16(CryptoTestSupport.data("empty")));
        Test.equals(38712, Crc.crc16(CryptoTestSupport.data("abc")));
        Test.equals(47933, Crc.crc16(CryptoTestSupport.data("digits")));
        Test.equals(47827, Crc.crc16(CryptoTestSupport.data("bytes0to255")));
        Test.equals(49729, Crc.crc16(CryptoTestSupport.data("len1")));
        Test.equals(37011, Crc.crc16(CryptoTestSupport.data("len16")));
        Test.equals(60305, Crc.crc16(CryptoTestSupport.data("len17")));
        Test.equals(30238, Crc.crc16(CryptoTestSupport.data("len63")));
        Test.equals(46839, Crc.crc16(CryptoTestSupport.data("len64")));
        Test.equals(5302, Crc.crc16(CryptoTestSupport.data("len65")));
        Test.equals(30174, Crc.crc16(CryptoTestSupport.data("len127")));
        Test.equals(46836, Crc.crc16(CryptoTestSupport.data("len128")));
        Test.equals(58871, Crc.crc16(CryptoTestSupport.data("len129")));
        Test.equals(35666, Crc.crc16(CryptoTestSupport.data("len239")));
        Test.equals(32523, Crc.crc16(CryptoTestSupport.data("len240")));
        Test.equals(51582, Crc.crc16(CryptoTestSupport.data("len241")));
        Test.equals(41759, Crc.crc16(CryptoTestSupport.data("len1003")));
        Test.equals(10723, Crc.crc16(CryptoTestSupport.data("len1004")));
    }

    @:test("crc16ccitt vectors")
    public static function crc16ccittVectors():Void {
        Test.equals(65535, Crc.crc16ccitt(CryptoTestSupport.data("empty")));
        Test.equals(20810, Crc.crc16ccitt(CryptoTestSupport.data("abc")));
        Test.equals(10673, Crc.crc16ccitt(CryptoTestSupport.data("digits")));
        Test.equals(16317, Crc.crc16ccitt(CryptoTestSupport.data("bytes0to255")));
        Test.equals(37143, Crc.crc16ccitt(CryptoTestSupport.data("len1")));
        Test.equals(26429, Crc.crc16ccitt(CryptoTestSupport.data("len16")));
        Test.equals(48825, Crc.crc16ccitt(CryptoTestSupport.data("len17")));
        Test.equals(19714, Crc.crc16ccitt(CryptoTestSupport.data("len63")));
        Test.equals(44939, Crc.crc16ccitt(CryptoTestSupport.data("len64")));
        Test.equals(26286, Crc.crc16ccitt(CryptoTestSupport.data("len65")));
        Test.equals(60210, Crc.crc16ccitt(CryptoTestSupport.data("len127")));
        Test.equals(37867, Crc.crc16ccitt(CryptoTestSupport.data("len128")));
        Test.equals(47541, Crc.crc16ccitt(CryptoTestSupport.data("len129")));
        Test.equals(44799, Crc.crc16ccitt(CryptoTestSupport.data("len239")));
        Test.equals(50483, Crc.crc16ccitt(CryptoTestSupport.data("len240")));
        Test.equals(55359, Crc.crc16ccitt(CryptoTestSupport.data("len241")));
        Test.equals(24424, Crc.crc16ccitt(CryptoTestSupport.data("len1003")));
        Test.equals(31745, Crc.crc16ccitt(CryptoTestSupport.data("len1004")));
    }

    @:test("crc16modbus vectors")
    public static function crc16modbusVectors():Void {
        Test.equals(65535, Crc.crc16modbus(CryptoTestSupport.data("empty")));
        Test.equals(22345, Crc.crc16modbus(CryptoTestSupport.data("abc")));
        Test.equals(19255, Crc.crc16modbus(CryptoTestSupport.data("digits")));
        Test.equals(56940, Crc.crc16modbus(CryptoTestSupport.data("bytes0to255")));
        Test.equals(33534, Crc.crc16modbus(CryptoTestSupport.data("len1")));
        Test.equals(24621, Crc.crc16modbus(CryptoTestSupport.data("len16")));
        Test.equals(39905, Crc.crc16modbus(CryptoTestSupport.data("len17")));
        Test.equals(46708, Crc.crc16modbus(CryptoTestSupport.data("len63")));
        Test.equals(39351, Crc.crc16modbus(CryptoTestSupport.data("len64")));
        Test.equals(58520, Crc.crc16modbus(CryptoTestSupport.data("len65")));
        Test.equals(51845, Crc.crc16modbus(CryptoTestSupport.data("len127")));
        Test.equals(19722, Crc.crc16modbus(CryptoTestSupport.data("len128")));
        Test.equals(25997, Crc.crc16modbus(CryptoTestSupport.data("len129")));
        Test.equals(51782, Crc.crc16modbus(CryptoTestSupport.data("len239")));
        Test.equals(28746, Crc.crc16modbus(CryptoTestSupport.data("len240")));
        Test.equals(63921, Crc.crc16modbus(CryptoTestSupport.data("len241")));
        Test.equals(17241, Crc.crc16modbus(CryptoTestSupport.data("len1003")));
        Test.equals(56194, Crc.crc16modbus(CryptoTestSupport.data("len1004")));
    }

    @:test("crc16kermit vectors")
    public static function crc16kermitVectors():Void {
        Test.equals(0, Crc.crc16kermit(CryptoTestSupport.data("empty")));
        Test.equals(22761, Crc.crc16kermit(CryptoTestSupport.data("abc")));
        Test.equals(8585, Crc.crc16kermit(CryptoTestSupport.data("digits")));
        Test.equals(55361, Crc.crc16kermit(CryptoTestSupport.data("bytes0to255")));
        Test.equals(29887, Crc.crc16kermit(CryptoTestSupport.data("len1")));
        Test.equals(22472, Crc.crc16kermit(CryptoTestSupport.data("len16")));
        Test.equals(51491, Crc.crc16kermit(CryptoTestSupport.data("len17")));
        Test.equals(12660, Crc.crc16kermit(CryptoTestSupport.data("len63")));
        Test.equals(7376, Crc.crc16kermit(CryptoTestSupport.data("len64")));
        Test.equals(25634, Crc.crc16kermit(CryptoTestSupport.data("len65")));
        Test.equals(57020, Crc.crc16kermit(CryptoTestSupport.data("len127")));
        Test.equals(36983, Crc.crc16kermit(CryptoTestSupport.data("len128")));
        Test.equals(63263, Crc.crc16kermit(CryptoTestSupport.data("len129")));
        Test.equals(57460, Crc.crc16kermit(CryptoTestSupport.data("len239")));
        Test.equals(20100, Crc.crc16kermit(CryptoTestSupport.data("len240")));
        Test.equals(42588, Crc.crc16kermit(CryptoTestSupport.data("len241")));
        Test.equals(40430, Crc.crc16kermit(CryptoTestSupport.data("len1003")));
        Test.equals(46854, Crc.crc16kermit(CryptoTestSupport.data("len1004")));
    }

    @:test("crc16xmodem vectors")
    public static function crc16xmodemVectors():Void {
        Test.equals(0, Crc.crc16xmodem(CryptoTestSupport.data("empty")));
        Test.equals(40406, Crc.crc16xmodem(CryptoTestSupport.data("abc")));
        Test.equals(12739, Crc.crc16xmodem(CryptoTestSupport.data("digits")));
        Test.equals(32341, Crc.crc16xmodem(CryptoTestSupport.data("bytes0to255")));
        Test.equals(28903, Crc.crc16xmodem(CryptoTestSupport.data("len1")));
        Test.equals(3383, Crc.crc16xmodem(CryptoTestSupport.data("len16")));
        Test.equals(31061, Crc.crc16xmodem(CryptoTestSupport.data("len17")));
        Test.equals(56935, Crc.crc16xmodem(CryptoTestSupport.data("len63")));
        Test.equals(31057, Crc.crc16xmodem(CryptoTestSupport.data("len64")));
        Test.equals(5909, Crc.crc16xmodem(CryptoTestSupport.data("len65")));
        Test.equals(42347, Crc.crc16xmodem(CryptoTestSupport.data("len127")));
        Test.equals(25569, Crc.crc16xmodem(CryptoTestSupport.data("len128")));
        Test.equals(23722, Crc.crc16xmodem(CryptoTestSupport.data("len129")));
        Test.equals(64188, Crc.crc16xmodem(CryptoTestSupport.data("len239")));
        Test.equals(40002, Crc.crc16xmodem(CryptoTestSupport.data("len240")));
        Test.equals(25315, Crc.crc16xmodem(CryptoTestSupport.data("len241")));
        Test.equals(64693, Crc.crc16xmodem(CryptoTestSupport.data("len1003")));
        Test.equals(9352, Crc.crc16xmodem(CryptoTestSupport.data("len1004")));
    }

    @:test("crc24 vectors")
    public static function crc24Vectors():Void {
        Test.equals(11994318, Crc.crc24(CryptoTestSupport.data("empty")));
        Test.equals(12196987, Crc.crc24(CryptoTestSupport.data("abc")));
        Test.equals(2215682, Crc.crc24(CryptoTestSupport.data("digits")));
        Test.equals(6012212, Crc.crc24(CryptoTestSupport.data("bytes0to255")));
        Test.equals(16651972, Crc.crc24(CryptoTestSupport.data("len1")));
        Test.equals(14864697, Crc.crc24(CryptoTestSupport.data("len16")));
        Test.equals(122259, Crc.crc24(CryptoTestSupport.data("len17")));
        Test.equals(7072244, Crc.crc24(CryptoTestSupport.data("len63")));
        Test.equals(13601152, Crc.crc24(CryptoTestSupport.data("len64")));
        Test.equals(2621753, Crc.crc24(CryptoTestSupport.data("len65")));
        Test.equals(11178009, Crc.crc24(CryptoTestSupport.data("len127")));
        Test.equals(3156091, Crc.crc24(CryptoTestSupport.data("len128")));
        Test.equals(5102803, Crc.crc24(CryptoTestSupport.data("len129")));
        Test.equals(11451927, Crc.crc24(CryptoTestSupport.data("len239")));
        Test.equals(8112567, Crc.crc24(CryptoTestSupport.data("len240")));
        Test.equals(15639267, Crc.crc24(CryptoTestSupport.data("len241")));
        Test.equals(4243294, Crc.crc24(CryptoTestSupport.data("len1003")));
        Test.equals(4499128, Crc.crc24(CryptoTestSupport.data("len1004")));
    }

    @:test("crc32 vectors")
    public static function crc32Vectors():Void {
        Test.equals(0, Crc.crc32(CryptoTestSupport.data("empty")));
        Test.equals(891568578, Crc.crc32(CryptoTestSupport.data("abc")));
        Test.equals(-873187034, Crc.crc32(CryptoTestSupport.data("digits")));
        Test.equals(688229491, Crc.crc32(CryptoTestSupport.data("bytes0to255")));
        Test.equals(1281784366, Crc.crc32(CryptoTestSupport.data("len1")));
        Test.equals(104245397, Crc.crc32(CryptoTestSupport.data("len16")));
        Test.equals(1907939665, Crc.crc32(CryptoTestSupport.data("len17")));
        Test.equals(2034968221, Crc.crc32(CryptoTestSupport.data("len63")));
        Test.equals(-2067242872, Crc.crc32(CryptoTestSupport.data("len64")));
        Test.equals(887454700, Crc.crc32(CryptoTestSupport.data("len65")));
        Test.equals(1250177418, Crc.crc32(CryptoTestSupport.data("len127")));
        Test.equals(-1672681240, Crc.crc32(CryptoTestSupport.data("len128")));
        Test.equals(261349292, Crc.crc32(CryptoTestSupport.data("len129")));
        Test.equals(1155886888, Crc.crc32(CryptoTestSupport.data("len239")));
        Test.equals(1419106358, Crc.crc32(CryptoTestSupport.data("len240")));
        Test.equals(-1640011253, Crc.crc32(CryptoTestSupport.data("len241")));
        Test.equals(1477071203, Crc.crc32(CryptoTestSupport.data("len1003")));
        Test.equals(1599268905, Crc.crc32(CryptoTestSupport.data("len1004")));
    }

    @:test("crc32mpeg2 vectors")
    public static function crc32mpeg2Vectors():Void {
        Test.equals(-1, Crc.crc32mpeg2(CryptoTestSupport.data("empty")));
        Test.equals(-1686944628, Crc.crc32mpeg2(CryptoTestSupport.data("abc")));
        Test.equals(58124007, Crc.crc32mpeg2(CryptoTestSupport.data("digits")));
        Test.equals(1229590890, Crc.crc32mpeg2(CryptoTestSupport.data("bytes0to255")));
        Test.equals(1347415985, Crc.crc32mpeg2(CryptoTestSupport.data("len1")));
        Test.equals(1241724105, Crc.crc32mpeg2(CryptoTestSupport.data("len16")));
        Test.equals(-1882733907, Crc.crc32mpeg2(CryptoTestSupport.data("len17")));
        Test.equals(-1054238882, Crc.crc32mpeg2(CryptoTestSupport.data("len63")));
        Test.equals(-1476695912, Crc.crc32mpeg2(CryptoTestSupport.data("len64")));
        Test.equals(1473076887, Crc.crc32mpeg2(CryptoTestSupport.data("len65")));
        Test.equals(1482736027, Crc.crc32mpeg2(CryptoTestSupport.data("len127")));
        Test.equals(-1259080048, Crc.crc32mpeg2(CryptoTestSupport.data("len128")));
        Test.equals(713546569, Crc.crc32mpeg2(CryptoTestSupport.data("len129")));
        Test.equals(1316342373, Crc.crc32mpeg2(CryptoTestSupport.data("len239")));
        Test.equals(-764238388, Crc.crc32mpeg2(CryptoTestSupport.data("len240")));
        Test.equals(954873842, Crc.crc32mpeg2(CryptoTestSupport.data("len241")));
        Test.equals(-240518757, Crc.crc32mpeg2(CryptoTestSupport.data("len1003")));
        Test.equals(-247923395, Crc.crc32mpeg2(CryptoTestSupport.data("len1004")));
    }

    @:test("crcjam vectors")
    public static function crcjamVectors():Void {
        Test.equals(-1, Crc.crcjam(CryptoTestSupport.data("empty")));
        Test.equals(-891568579, Crc.crcjam(CryptoTestSupport.data("abc")));
        Test.equals(873187033, Crc.crcjam(CryptoTestSupport.data("digits")));
        Test.equals(-688229492, Crc.crcjam(CryptoTestSupport.data("bytes0to255")));
        Test.equals(-1281784367, Crc.crcjam(CryptoTestSupport.data("len1")));
        Test.equals(-104245398, Crc.crcjam(CryptoTestSupport.data("len16")));
        Test.equals(-1907939666, Crc.crcjam(CryptoTestSupport.data("len17")));
        Test.equals(-2034968222, Crc.crcjam(CryptoTestSupport.data("len63")));
        Test.equals(2067242871, Crc.crcjam(CryptoTestSupport.data("len64")));
        Test.equals(-887454701, Crc.crcjam(CryptoTestSupport.data("len65")));
        Test.equals(-1250177419, Crc.crcjam(CryptoTestSupport.data("len127")));
        Test.equals(1672681239, Crc.crcjam(CryptoTestSupport.data("len128")));
        Test.equals(-261349293, Crc.crcjam(CryptoTestSupport.data("len129")));
        Test.equals(-1155886889, Crc.crcjam(CryptoTestSupport.data("len239")));
        Test.equals(-1419106359, Crc.crcjam(CryptoTestSupport.data("len240")));
        Test.equals(1640011252, Crc.crcjam(CryptoTestSupport.data("len241")));
        Test.equals(-1477071204, Crc.crcjam(CryptoTestSupport.data("len1003")));
        Test.equals(-1599268906, Crc.crcjam(CryptoTestSupport.data("len1004")));
    }

    @:test("crc1 incremental")
    public static function crc1Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc1(second, Crc.crc1(first));
        Test.equals(102, Crc.crc1(third, previous));
    }

    @:test("crc8 incremental")
    public static function crc8Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc8(second, Crc.crc8(first));
        Test.equals(21, Crc.crc8(third, previous));
    }

    @:test("crc81wire incremental")
    public static function crc81wireIncremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc81wire(second, Crc.crc81wire(first));
        Test.equals(157, Crc.crc81wire(third, previous));
    }

    @:test("crc8dvbs2 incremental")
    public static function crc8dvbs2Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc8dvbs2(second, Crc.crc8dvbs2(first));
        Test.equals(84, Crc.crc8dvbs2(third, previous));
    }

    @:test("crc16 incremental")
    public static function crc16Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc16(second, Crc.crc16(first));
        Test.equals(41759, Crc.crc16(third, previous));
    }

    @:test("crc16ccitt incremental")
    public static function crc16ccittIncremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc16ccitt(second, Crc.crc16ccitt(first));
        Test.equals(24424, Crc.crc16ccitt(third, previous));
    }

    @:test("crc16modbus incremental")
    public static function crc16modbusIncremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc16modbus(second, Crc.crc16modbus(first));
        Test.equals(17241, Crc.crc16modbus(third, previous));
    }

    @:test("crc16kermit incremental")
    public static function crc16kermitIncremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc16kermit(second, Crc.crc16kermit(first));
        Test.equals(40430, Crc.crc16kermit(third, previous));
    }

    @:test("crc16xmodem incremental")
    public static function crc16xmodemIncremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc16xmodem(second, Crc.crc16xmodem(first));
        Test.equals(64693, Crc.crc16xmodem(third, previous));
    }

    @:test("crc24 incremental")
    public static function crc24Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc24(second, Crc.crc24(first));
        Test.equals(4243294, Crc.crc24(third, previous));
    }

    @:test("crc32 incremental")
    public static function crc32Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc32(second, Crc.crc32(first));
        Test.equals(1477071203, Crc.crc32(third, previous));
    }

    @:test("crc32mpeg2 incremental")
    public static function crc32mpeg2Incremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crc32mpeg2(second, Crc.crc32mpeg2(first));
        Test.equals(-240518757, Crc.crc32mpeg2(third, previous));
    }

    @:test("crcjam incremental")
    public static function crcjamIncremental():Void {
        final data = CryptoTestSupport.data("len1003");
        final first = data.sub(0, 1);
        final second = data.sub(1, 500);
        final third = data.sub(501, 502);
        final previous = Crc.crcjam(second, Crc.crcjam(first));
        Test.equals(-1477071204, Crc.crcjam(third, previous));
    }
}
