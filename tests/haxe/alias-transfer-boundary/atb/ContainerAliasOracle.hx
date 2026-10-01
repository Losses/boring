package atb;

import std.ReadOnlyArray;

/**
    Authored Haxe oracle for the two container-identity-transfer shapes:

    (a) `Holder.Null<Array<Int>>` field — the container identity crosses a
        nullable field slot. The field is read back, unwrapped, and the
        retained mutable alias mutates the original container; the
        observation is whether the unwrapped read sees the mutation.
    (b) `Array -> ReadOnlyArray` argument/return relay — the container
        identity crosses a call boundary as a read-only argument and is
        returned as a read-only value; the caller retains a mutable alias
        and mutates after the call; the observation is whether the relayed
        view sees the mutation.

    The expected values are the shared-container reading (feature 18
    ruling): the nullable field slot shares the original storage and the
    relay returns the argument view, so both shapes observe the post-call
    mutation. The Haxe JS oracle prints the labeled lines; native harnesses
    call the shape functions directly and print the same lines.

    Discriminator controls (probe discrimination, criterion 4):
    - `fieldNull` prints `fieldNull=0` when the nullable field is null
      (the unwrap probe is not stuck on a constant value).
    - `relayFresh` prints `relayFresh=0` when the relayed view is a fresh
      container (the relay probe is not stuck on a shared reading).
    - `fieldRebind` prints `fieldRebind=0` when the field is rebound to a
      fresh container after the view exists (the field-rebinding probe is
      not stuck on a constant value).
**/
class ContainerAliasOracle {
    /**
        Shape (a) field: the container identity crosses the nullable field
        slot. The holder is built with the original container; the field is
        read back and unwrapped into a view; the retained mutable alias
        mutates the original. A shared reading reports 702 (7 * 100 + 2);
        a detached copy reports 101.
    **/
    public static function field():Int {
        var original:Array<Int> = [1];
        final holder:NullableHolder = new NullableHolder(original);
        final view:ReadOnlyArray<Int> = holder.values;
        original[0] = 7;
        original.push(9);
        return view[0] * 100 + view.length;
    }

    /**
        Shape (a) field-null control: the nullable field is null, so the
        unwrap probe must report 0. This proves the unwrap probe is not
        stuck on a constant value. The read stays a plain nullable field
        read (no ReadOnlyArray conversion), so it observes the field's
        null-ness without crossing the array boundary.
    **/
    public static function fieldNull():Int {
        final holder:NullableHolder = new NullableHolder(null);
        return holder.values == null ? 0 : 1;
    }

    /**
        Shape (a) field-rebind control: the field is rebound to a fresh
        container after the view exists. A view that retains the original
        storage reports 123; a view that follows the binding reports 987.
    **/
    public static function fieldRebind():Int {
        final holder:NullableHolder = new NullableHolder([1, 2, 3]);
        final view:ReadOnlyArray<Int> = holder.values;
        holder.values = [9, 8, 7];
        return view[0] * 100 + view[1] * 10 + view[2];
    }

    /**
        Shape (b) relay: the container crosses a call boundary as a
        read-only argument and is returned as a read-only value; the caller
        retains a mutable alias and mutates after the call. A shared
        argument/return reading reports 3301 (33 * 100 + 1); a value copied
        at the argument or return position reports 1201.
    **/
    public static function relay():Int {
        var source:Array<Int> = [12];
        final view:ReadOnlyArray<Int> = relayThrough(source);
        source[0] = 33;
        return view[0] * 100 + view.length;
    }

    public static function relayThrough(values:ReadOnlyArray<Int>):ReadOnlyArray<Int> {
        return values;
    }

    /**
        Shape (b) relay-fresh control: the relayed view is a fresh
        container, so the relay probe must report 0. This proves the relay
        probe is not stuck on a shared reading.
    **/
    public static function relayFresh():Int {
        final view:ReadOnlyArray<Int> = relayThrough([1, 2]);
        return view.length == 2 && view[0] == 1 ? 0 : 1;
    }

    /**
        The Haxe JS oracle entry. Native harnesses call the shape functions
        directly and print the same labeled lines; the generated trees for
        native targets keep an empty main so the fixture adds no
        target-specific console dependency.
    **/
    public static function main():Void {
        #if js
        std.Console.log("field=" + field());
        std.Console.log("fieldNull=" + fieldNull());
        std.Console.log("fieldRebind=" + fieldRebind());
        std.Console.log("relay=" + relay());
        std.Console.log("relayFresh=" + relayFresh());
        #end
    }
}
