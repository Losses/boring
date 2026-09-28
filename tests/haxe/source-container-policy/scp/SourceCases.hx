package scp;

import std.ReadOnlyArray;

/**
    Authored source declarations of the container cases. Each static field is
    one case; the field name is the case identity and the written annotation
    is the input the analyzer classifies. No initializer is needed because
    only the written type is under observation. Expectations live in the
    runner, never here.

    The transparent aliases are subtypes of this module, so a written alias
    and its declaration are observed through one authored source.
**/
class SourceCases {
    public static var directArray:Array<Int>;
    public static var aliasedArray:AliasArray<Int>;
    public static var genericAliasArray:Box<Int>;
    public static var nestedAliasArray:OuterAlias<Float>;
    public static var directReadOnly:ReadOnlyArray<String>;
    public static var aliasedReadOnly:AliasReadOnly<String>;
    public static var outerNullArray:Null<Array<Int>>;
    public static var outerNullReadOnly:Null<ReadOnlyArray<String>>;
    public static var elementNullArray:Array<Null<String>>;
    public static var scalar:Int;
    public static var aliasedScalar:AliasInt;
    public static var foreignReadOnly:scp.face.ReadOnlyArray<String>;
    public static var foreignAliasReadOnly:ForeignReadOnlyAlias<String>;
    public static var foreignArray:scp.face.Array<Int>;
    public static var chainArray:Chain01<Int>;
    public static var longChainArray:Long01<Int>;
}

/** Transparent alias of the built-in mutable array. */
typedef AliasArray<T> = Array<T>;

/** Generic alias with one substituted parameter. */
typedef Box<T> = Array<T>;

/** Alias of an alias, so substitution crosses two hops. */
typedef OuterAlias<T> = Box<T>;

/** Transparent alias of the reserved read-only declaration. */
typedef AliasReadOnly<T> = ReadOnlyArray<T>;

/** Alias of a foreign declaration that shares only the name. */
typedef ForeignReadOnlyAlias<T> = scp.face.ReadOnlyArray<T>;

/** Alias of a scalar, which stays a non-container. */
typedef AliasInt = Int;

/** A finite alias chain of twelve hops; it must resolve within the bound. */
typedef Chain01<T> = Chain02<T>;

typedef Chain02<T> = Chain03<T>;
typedef Chain03<T> = Chain04<T>;
typedef Chain04<T> = Chain05<T>;
typedef Chain05<T> = Chain06<T>;
typedef Chain06<T> = Chain07<T>;
typedef Chain07<T> = Chain08<T>;
typedef Chain08<T> = Chain09<T>;
typedef Chain09<T> = Chain10<T>;
typedef Chain10<T> = Chain11<T>;
typedef Chain11<T> = Chain12<T>;
typedef Chain12<T> = Array<T>;

/** An ordinary finite alias chain longer than the removed resolver cutoff. */
typedef Long01<T> = Long02<T>;

typedef Long02<T> = Long03<T>;
typedef Long03<T> = Long04<T>;
typedef Long04<T> = Long05<T>;
typedef Long05<T> = Long06<T>;
typedef Long06<T> = Long07<T>;
typedef Long07<T> = Long08<T>;
typedef Long08<T> = Long09<T>;
typedef Long09<T> = Long10<T>;
typedef Long10<T> = Long11<T>;
typedef Long11<T> = Long12<T>;
typedef Long12<T> = Long13<T>;
typedef Long13<T> = Long14<T>;
typedef Long14<T> = Long15<T>;
typedef Long15<T> = Long16<T>;
typedef Long16<T> = Long17<T>;
typedef Long17<T> = Long18<T>;
typedef Long18<T> = Long19<T>;
typedef Long19<T> = Long20<T>;
typedef Long20<T> = Long21<T>;
typedef Long21<T> = Long22<T>;
typedef Long22<T> = Long23<T>;
typedef Long23<T> = Long24<T>;
typedef Long24<T> = Long25<T>;
typedef Long25<T> = Long26<T>;
typedef Long26<T> = Long27<T>;
typedef Long27<T> = Long28<T>;
typedef Long28<T> = Long29<T>;
typedef Long29<T> = Long30<T>;
typedef Long30<T> = Long31<T>;
typedef Long31<T> = Long32<T>;
typedef Long32<T> = Long33<T>;
typedef Long33<T> = Long34<T>;
typedef Long34<T> = Long35<T>;
typedef Long35<T> = Long36<T>;
typedef Long36<T> = Long37<T>;
typedef Long37<T> = Long38<T>;
typedef Long38<T> = Long39<T>;
typedef Long39<T> = Long40<T>;
typedef Long40<T> = Long41<T>;
typedef Long41<T> = Long42<T>;
typedef Long42<T> = Long43<T>;
typedef Long43<T> = Long44<T>;
typedef Long44<T> = Long45<T>;
typedef Long45<T> = Long46<T>;
typedef Long46<T> = Long47<T>;
typedef Long47<T> = Long48<T>;
typedef Long48<T> = Long49<T>;
typedef Long49<T> = Long50<T>;
typedef Long50<T> = Long51<T>;
typedef Long51<T> = Long52<T>;
typedef Long52<T> = Long53<T>;
typedef Long53<T> = Long54<T>;
typedef Long54<T> = Long55<T>;
typedef Long55<T> = Long56<T>;
typedef Long56<T> = Long57<T>;
typedef Long57<T> = Long58<T>;
typedef Long58<T> = Long59<T>;
typedef Long59<T> = Long60<T>;
typedef Long60<T> = Long61<T>;
typedef Long61<T> = Long62<T>;
typedef Long62<T> = Long63<T>;
typedef Long63<T> = Long64<T>;
typedef Long64<T> = Long65<T>;
typedef Long65<T> = Long66<T>;
typedef Long66<T> = Long67<T>;
typedef Long67<T> = Long68<T>;
typedef Long68<T> = Long69<T>;
typedef Long69<T> = Long70<T>;
typedef Long70<T> = Long71<T>;
typedef Long71<T> = Long72<T>;
typedef Long72<T> = Long73<T>;
typedef Long73<T> = Long74<T>;
typedef Long74<T> = Long75<T>;
typedef Long75<T> = Long76<T>;
typedef Long76<T> = Long77<T>;
typedef Long77<T> = Long78<T>;
typedef Long78<T> = Long79<T>;
typedef Long79<T> = Long80<T>;
typedef Long80<T> = Array<T>;
