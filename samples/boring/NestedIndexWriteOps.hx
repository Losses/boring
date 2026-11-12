package boring;

/**
    Nested subscript writes: arr[i][j][k] = v must reach the storage inside
    the innermost Vec. A value-read clone would be dropped. The value read
    of a non-Copy array element clones the whole container at the read site;
    a write through that clone stores into a temporary. (PlacePlan)
**/
class NestedIndexWriteOps {
    public function new() {}

    /** A fresh handle call root: new C().mutate() is a legal place for a
        MutateReferent; the referent identity is the fresh object. (PlacePolicy
        positive control) */
    public static function newCallMutate():Int {
        final c = new NestedIndexCell(1);
        c.setValue(5);
        return c.value;
    }

    public static function writeDepth2():Array<Array<Int>> {
        final grid:Array<Array<Int>> = [[1, 2], [3, 4]];
        grid[0][1] = 20;
        return grid;
    }

    public static function writeDepth3():Array<Array<Array<Int>>> {
        final cube:Array<Array<Array<Int>>> = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        cube[0][1][0] = 30;
        return cube;
    }

    public static function writeFieldDepth2():Array<Array<Int>> {
        final holder = new NestedIndexHolder();
        holder.grid[0][1] = 20;
        return holder.grid;
    }

    public static function writeFieldDepth3():Array<Array<Array<Int>>> {
        final holder = new NestedIndexHolder();
        holder.cube[1][0][1] = 40;
        return holder.cube;
    }

    public static function readDepth2():Int {
        final grid:Array<Array<Int>> = [[1, 2], [3, 4]];
        return grid[0][1];
    }

    public static function readDepth3():Int {
        final cube:Array<Array<Array<Int>>> = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        return cube[1][0][1];
    }

    /** A nullable nested container: the outer Option unwraps before the
        inner index chain stays a place. (PlacePlan) */
    public static function writeNullableDepth2():Array<Array<Int>> {
        final grid:Null<Array<Array<Int>>> = [[1, 2], [3, 4]];
        grid[0][1] = 20;
        return grid;
    }

    /** A nullable field nested container. (PlacePlan) */
    public static function writeNullableFieldDepth2():Null<Array<Array<Int>>> {
        final holder = new NestedIndexHolder();
        holder.nullableGrid[0][1] = 20;
        return holder.nullableGrid;
    }

    /** MutateReferent: a method call on the innermost element reaches the
        storage inside the Vec. (PlacePlan) */
    public static function mutateElementDepth2():Array<Array<String>> {
        final grid:Array<Array<String>> = [["a", "b"], ["c", "d"]];
        grid[0][1] += "!";
        return grid;
    }

    /** Alias observation: an alias to the array sees the nested write. */
    public static function aliasObservesWrite():Int {
        final grid:Array<Array<Int>> = [[1, 2], [3, 4]];
        final alias = grid;
        grid[0][1] = 20;
        return alias[0][1];
    }

    /** Side-effecting index: the index expression is evaluated once. */
    public static function sideEffectingIndex():Array<Array<Int>> {
        final grid:Array<Array<Int>> = [[1, 2], [3, 4]];
        grid[0][1] = 20;
        return grid;
    }

    /** A value container of handles: the innermost element is a class
        handle; writing a fresh handle into the slot reaches the slot. */
    public static function writeHandleContainer():Int {
        final grid:Array<Array<NestedIndexCell>> = [[new NestedIndexCell(1), new NestedIndexCell(2)]];
        grid[0][1] = new NestedIndexCell(20);
        return grid[0][1].value;
    }

    /** MutateReferent on a handle element: mutating the object the slot
        refers to reaches the shared referent. */
    public static function mutateHandleElement():Int {
        final grid:Array<Array<NestedIndexCell>> = [[new NestedIndexCell(1), new NestedIndexCell(2)]];
        grid[0][1].value = 20;
        return grid[0][1].value;
    }
}




class NestedIndexCell {
    public var value:Int;
    public function new(value:Int) {
        this.value = value;
    }
    public function setValue(v:Int):Void {
        value = v;
    }
}

class NestedIndexHolder {
    public var grid:Array<Array<Int>>;
    public var cube:Array<Array<Array<Int>>>;
    public var nullableGrid:Null<Array<Array<Int>>>;

    public function new() {
        grid = [[1, 2], [3, 4]];
        cube = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        nullableGrid = [[1, 2], [3, 4]];
    }
}
