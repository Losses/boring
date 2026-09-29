import { PairKey, comparePairKey } from "./comparisoncollision/PairKey.ts";
import { Point as FirstPoint } from "./comparisoncollision/first/Point.ts";
import { Point as SecondPoint } from "./comparisoncollision/second/Point.ts";
import { TintedKey, compareTintedKey } from "./comparisoncollision/TintedKey.ts";
import { TintedHolder } from "./comparisoncollision/TintedHolder.ts";
import { ColorMaker } from "./comparisoncollision/ColorMaker.ts";
import { Pair as ShellPair, comparePair as compareShellPair } from "./comparisoncollision/pair/Pair.ts";

const left = new PairKey(new FirstPoint(1), new SecondPoint(9));
const middle = new PairKey(new FirstPoint(2), new SecondPoint(1));
const right = new PairKey(new FirstPoint(2), new SecondPoint(3));
const observed = [
    comparePairKey(left, middle),
    comparePairKey(middle, right),
    comparePairKey(right, middle),
    comparePairKey(left, left),
].map((value) => Math.sign(value)).join(",");
if (observed !== "-1,-1,1,0") {
    throw new Error("unexpected order: " + observed);
}
console.log(observed);

const crimsonNavy = TintedKey.keyCrimsonNavy();
const crimsonCrimson = TintedKey.keyCrimsonCrimson();
const navyCrimson = TintedKey.keyNavyCrimson();
const enumObserved = [
    compareTintedKey(crimsonNavy, crimsonCrimson),
    compareTintedKey(crimsonCrimson, crimsonNavy),
    compareTintedKey(crimsonNavy, navyCrimson),
    compareTintedKey(navyCrimson, crimsonCrimson),
    compareTintedKey(crimsonNavy, crimsonNavy),
].map((value) => Math.sign(value)).join(",");
if (enumObserved !== "-1,1,-1,1,0") {
    throw new Error("unexpected enum order: " + enumObserved);
}
console.log(enumObserved);

const holder = TintedHolder.tintedCrimsonNavy();
if (holder.left.kind !== "Crimson" || holder.right.kind !== "Navy") {
    throw new Error("unexpected holder fields: " + holder.left.kind + "," + holder.right.kind);
}
const other = TintedHolder.tintedNavyCrimson();
if (other.left.kind !== "Navy" || other.right.kind !== "Crimson") {
    throw new Error("unexpected other fields: " + other.left.kind + "," + other.right.kind);
}
console.log("holder=" + holder.left.kind + "," + holder.right.kind + ";" + other.left.kind + "," + other.right.kind);

const shellOne = ShellPair.wrap(1);
const shellTwo = ShellPair.wrap(2);
const shellObserved = [
    compareShellPair(shellOne, shellTwo),
    compareShellPair(shellTwo, shellOne),
    compareShellPair(shellOne, shellOne),
].map((value) => Math.sign(value)).join(",");
if (shellObserved !== "-1,1,0") {
    throw new Error("unexpected shell order: " + shellObserved);
}
console.log(shellObserved);

import { Shell } from "./comparisoncollision/pair/Shell.ts";

const makerFirst = ColorMaker.firstColor();
const makerSecond = ColorMaker.secondColor();
if (makerFirst === null || makerSecond === null) {
    throw new Error("unexpected maker values");
}
if (makerFirst.kind !== "Crimson" || makerSecond.kind !== "Navy") {
    throw new Error("unexpected maker kinds: " + makerFirst.kind + "," + makerSecond.kind);
}
console.log("maker=" + makerFirst.kind + "," + makerSecond.kind);

const shell = Shell.wrapped(7);
if (shell.left.value !== 7 || shell.right.value !== 7) {
    throw new Error("unexpected shell values: " + shell.left.value + "," + shell.right.value);
}
console.log("shell=7,7");
const tableRead = ShellPair.tableRead();
if (tableRead !== "one;two") {
    throw new Error("unexpected table read: " + tableRead);
}
console.log("table=" + tableRead);
