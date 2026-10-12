package;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
    The role a lowered value plays at a consumption site. Each role
    determines how coerce converts the lowered value to valid target text.
    Only Condition is migrated in P1; the other roles are enumerated for
    future migration steps.
**/
enum DestinationRole {
    /** An if/while condition or the subject of boolean negation. */
    Condition;
    /** Operand of an arithmetic operator. */
    ArithmeticOperand;
    /** Bound of a for-loop range. */
    RangeBound;
    /** Receiver of a member access (field read, method call). */
    Receiver(memberKind:String);
    /** Argument passed to a function parameter. */
    Argument(param:String);
    /** Right-hand side of an assignment. */
    Assignment(target:String);
    /** Return value that must satisfy the return-type contract. */
    Return(contract:String);
    /** Argument to string concatenation (may propagate null). */
    StringConcatArgument;
    /** Value whose result is discarded. */
    Discard;
}

/**
    A destination: what the consuming site needs from a lowered value.
    See arch-review-claude.md §3.2 for the full design.
**/
typedef Destination = {
    /** The Haxe type at this site, for storage/error axis decisions. */
    var type:Null<Type>;
    /** Whether the site accepts a nullable value (string concat, Any? param). */
    var admitsAbsence:Bool;
    /** How the value is used at this site. */
    var role:DestinationRole;
    /** Error domain for this site, for error axis conversions. */
    var errorSlot:Null<String>;
}
#end

