package;

import FloatPrecisionPolicy.PrecisionRequest;
import FloatPrecisionPolicy.PrecisionPlan;
import FloatPrecisionPolicy.PrecisionPlanResult;
import FloatPrecisionPolicy.PrecisionRole;
import FloatPrecisionPolicy.PrecisionLane;
import FloatPrecisionPolicy.PrecisionConversionEdge;
import FloatPrecisionPolicy.FloatPrecisionPolicy;

/**
    Float Precision Validator: enforcement of docs/specs/float-precision-policy.md
    (FP-n) against emission-time IR + resolved plans.

    Contract (Astra design, frozen):
      - every float node carries a source role, a destination role, and a
        resolved plan; a missing plan is a failure, never a default.
      - def-use walks check widening, narrowing, and accumulator escape
        (exactly one Narrow leaves an accumulator; its target is a Value).
      - generated-token scanning is a supplementary lint only, never the
        primary authority.
      - a validator failure aborts emission with a named rule id, never a
        silent guess. Independent namespace from the P-n validator
        (RustHandleValidator).

    Scope: validate() and lintTokens() are independent, callable entry
    points. Neither is wired into an emitter; a renderer never re-decides a
    width from a lint finding.
**/

/** The role fact carried by one emission-time float node. */
typedef FloatNodeRoles = {
    /** the role of the node's own definition site. */
    var sourceRole:Null<PrecisionRole>;
    /** the role of the slot the node flows into (field/param/return/wire). */
    var destinationRole:Null<PrecisionRole>;
}

/**
    One emission-time float IR node: its roles, its resolved plan, and the
    structural def-use links the validator walks. Defaults keep a node legal
    until a case sets a violating field.
**/
class FloatIRNode {
    public var id:String;
    /** the declaration the node belongs to; the validator groups def-use by this. */
    public var declId:Null<String>;
    public var roles:FloatNodeRoles;
    /** the plan this node was resolved through; null means unvalidated. */
    public var plan:Null<PrecisionPlan>;
    /** nodes whose plans produce this node's value (defs). */
    public var defs:Array<FloatIRNode>;
    /** nodes consuming this node's value (uses). */
    public var uses:Array<FloatIRNode>;
    /** true when this node is the accumulator exit store. */
    public var isAccumulatorExit:Bool;

    public function new(id:String, ?declId:String, ?roles:FloatNodeRoles) {
        this.id = id;
        this.declId = declId;
        this.roles = roles != null ? roles : {sourceRole: null, destinationRole: null};
        this.defs = [];
        this.uses = [];
        this.isAccumulatorExit = false;
    }
}

/** One named validator failure; the rule id is cited in task evidence. */
typedef PrecisionValidationIssue = {
    /** the FP-V-n rule id. */
    var rule:String;
    var node_id:String;
    var message:String;
}

class FloatPrecisionValidator {
    // ---- Frozen rule-number table (docs/specs/float-precision-policy.md) ----
    /** every float node has a resolved plan (no plan = failure, never a default). */
    public static final FP_V_1_MISSING_PLAN:String = "FP-V-1";
    /** node roles missing (source/destination role fact absent). */
    public static final FP_V_2_MISSING_ROLES:String = "FP-V-2";
    /** plan role disagrees with the node's source/destination role facts. */
    public static final FP_V_3_ROLE_MISMATCH:String = "FP-V-3";
    /** Value node storage/compute width disagrees with the lane. */
    public static final FP_V_4_LANE_WIDTH:String = "FP-V-4";
    /** accumulator performs binary32 arithmetic or exits through more/fewer than one Narrow. */
    public static final FP_V_5_ACCUMULATOR_ESCAPE:String = "FP-V-5";
    /** a conversion edge in a plan is not a registered Narrow/Widen/Bitcast/Encode/Decode/IntToFloat. */
    public static final FP_V_6_UNREGISTERED_CONVERSION:String = "FP-V-6";
    /** a bitcast edge pairs mismatched widths (u32 vs f64). */
    public static final FP_V_7_BITCAST_WIDTH:String = "FP-V-7";
    /** wire/helper storage width drifted from its declared width under lane pressure. */
    public static final FP_V_8_DECLARED_WIDTH:String = "FP-V-8";
    /** supplementary generated-token lint (never the primary authority). */
    public static final FP_V_9_TOKEN_LINT:String = "FP-V-9";

    /** All rule ids, in document order. */
    public static function ruleIds():Array<String> {
        return [
            FP_V_1_MISSING_PLAN,
            FP_V_2_MISSING_ROLES,
            FP_V_3_ROLE_MISMATCH,
            FP_V_4_LANE_WIDTH,
            FP_V_5_ACCUMULATOR_ESCAPE,
            FP_V_6_UNREGISTERED_CONVERSION,
            FP_V_7_BITCAST_WIDTH,
            FP_V_8_DECLARED_WIDTH,
            FP_V_9_TOKEN_LINT
        ];
    }

    /**
        Validate emission-time IR against resolved plans.

        Requires every float node to carry source role, destination role, and a
        resolved plan; walks def-use for widening, narrowing, and accumulator
        escape. Returns named issues; an empty array means the IR passed.
    **/
    public static function validate(nodes:Array<FloatIRNode>, lane:PrecisionLane):Array<PrecisionValidationIssue> {
        final issues:Array<PrecisionValidationIssue> = [];
        if (nodes == null) {
            return issues;
        }
        final laneWidth = lane == PrecisionLane.F32 ? 32 : 64;
        for (node in nodes) {
            if (node == null) {
                continue;
            }
            // FP-V-1: a missing plan is a failure, never a default.
            if (node.plan == null) {
                push(issues, FP_V_1_MISSING_PLAN, node.id, "no resolved PrecisionPlan on float node");
                continue;
            }
            final plan = node.plan;
            // FP-V-2: both role facts must be present.
            if (node.roles == null || node.roles.sourceRole == null || node.roles.destinationRole == null) {
                push(issues, FP_V_2_MISSING_ROLES, node.id, "float node missing source or destination role fact");
            }
            // FP-V-3: the plan role must agree with the destination role fact.
            if (node.roles != null && node.roles.destinationRole != null && plan.role != node.roles.destinationRole) {
                push(issues, FP_V_3_ROLE_MISMATCH, node.id,
                    "plan role " + FloatPrecisionPolicy.roleToString(plan.role)
                    + " disagrees with destination role "
                    + FloatPrecisionPolicy.roleToString(node.roles.destinationRole));
            }
            // FP-V-4: a Value node stores and computes at lane width only.
            if (plan.role == PrecisionRole.RoleValue && widthOf(plan.storageType) != laneWidth) {
                push(issues, FP_V_4_LANE_WIDTH, node.id,
                    "Value storageType=" + plan.storageType + " disagrees with lane width " + laneWidth);
            }
            // FP-V-6: every conversion edge must be a registered kind.
            if (plan.conversionEdges != null) {
                for (edge in plan.conversionEdges) {
                    if (edge == null) {
                        continue;
                    }
                    if (!isRegisteredKind(edge.kind)) {
                        push(issues, FP_V_6_UNREGISTERED_CONVERSION, node.id,
                            "conversion edge kind '" + edge.kind + "' is not a registered Narrow/Widen/Bitcast/Encode/Decode/IntToFloat");
                    }
                    // FP-V-7: a bitcast edge pairs equal widths only.
                    if (edge.kind == "Bitcast" && widthOf(plan.storageType) != widthOf(plan.bitsType)) {
                        push(issues, FP_V_7_BITCAST_WIDTH, node.id,
                            "bitcast edge pairs mismatched widths: storage=" + plan.storageType
                            + " bits=" + plan.bitsType);
                    }
                }
            }
            // FP-V-8: wire/helper widths are declared, never lane-derived or empty.
            if (plan.role == PrecisionRole.RoleWire || plan.role == PrecisionRole.RoleNumericHelper) {
                if (plan.storageType == null || plan.storageType == "") {
                    push(issues, FP_V_8_DECLARED_WIDTH, node.id,
                        FloatPrecisionPolicy.roleToString(plan.role) + " plan carries no declared storage width");
                } else if (widthOf(plan.storageType) == laneWidth && plan.ruleIds != null && plan.ruleIds.indexOf(FloatPrecisionPolicy.ENTRY_WIRE) != -1) {
                    push(issues, FP_V_8_DECLARED_WIDTH, node.id,
                        "wire storage width " + plan.storageType + " matches lane width; wire widths are declared by protocol, never the lane");
                }
            }
        }
        // Def-use walks, grouped by declaration.
        final byDecl = new Map<String, Array<FloatIRNode>>();
        for (node in nodes) {
            if (node == null || node.plan == null || node.declId == null) {
                continue;
            }
            final key = node.declId;
            if (!byDecl.exists(key)) {
                byDecl.set(key, []);
            }
            byDecl.get(key).push(node);
        }
        for (declNodes in byDecl) {
            // FP-V-8 across a declaration: two Wire slots in one decl must agree.
            var wireWidth = -1;
            var wireWidthNode = "";
            for (node in declNodes) {
                if (node.plan.role != PrecisionRole.RoleWire) {
                    continue;
                }
                final w = widthOf(node.plan.storageType);
                if (wireWidth == -1) {
                    wireWidth = w;
                    wireWidthNode = node.id;
                } else if (w != wireWidth) {
                    push(issues, FP_V_8_DECLARED_WIDTH, node.id,
                        "wire storage width drifted from " + wireWidth + " (set by " + wireWidthNode + ") to " + w);
                }
            }
            // FP-V-5: accumulator behavior per accumulator node.
            for (node in declNodes) {
                if (node.plan.role != PrecisionRole.RoleAccumulator) {
                    continue;
                }
                if (node.plan.computeType != "f64" || node.plan.storageType != "f64") {
                    push(issues, FP_V_5_ACCUMULATOR_ESCAPE, node.id,
                        "accumulator performs binary" + widthOf(node.plan.computeType)
                        + " arithmetic; v1 mixed keeps accumulator state binary64");
                }
                var valueUses = 0;
                var narrowExits = 0;
                for (use in node.uses) {
                    if (use == null || use.plan == null) {
                        continue;
                    }
                    if (use.plan.role == PrecisionRole.RoleAccumulator) {
                        continue;
                    }
                    valueUses++;
                    if (hasNarrowEdge(node.plan) || hasNarrowEdge(use.plan)) {
                        narrowExits++;
                    }
                }
                if (node.isAccumulatorExit && narrowExits == 0) {
                    push(issues, FP_V_5_ACCUMULATOR_ESCAPE, node.id,
                        "accumulator exit store reached with no Narrow edge (accumulator escape)");
                }
                if (valueUses > 1) {
                    push(issues, FP_V_5_ACCUMULATOR_ESCAPE, node.id,
                        "accumulator leaves into " + valueUses
                        + " non-accumulator uses; exactly one Narrow exit is allowed");
                } else if (valueUses == 1 && narrowExits == 0) {
                    push(issues, FP_V_5_ACCUMULATOR_ESCAPE, node.id,
                        "accumulator reaches a Value slot without a Narrow edge (accumulator escape)");
                }
            }
        }
        return issues;
    }

    /**
        Supplementary lint over generated tokens. Never the primary
        authority; a token-lint finding alone must not block emission once
        FP-V-1..8 pass.

        Each element of 'generated' is one generated artifact's full text.
        Findings carry FP-V-9 with node_id "gen:<fileIndex>:<line>" and name
        the offending token class in the message:
          - bare-float-literal: a float literal with no f32/f64 suffix (the
            lane cannot be read off the token).
          - unknown-literal: a float literal with an unrecognized suffix.
          - int-to-float-cast: '<int> as fN' (FP-6 provenance: the edge is
            real, but a cast token means the emitter bypassed the plan).
          - value-cast: a non-integer operand 'as fN', a bare Narrow/Widen
            the plan never registered.
          - cfg-cast-combination: a cfg attribute gating a width decision
            (the lane leaking into a conditional-compilation axis).

        String literals and comments are stripped before scanning so that
        diagnostics, byte arrays and version strings do not produce noise.
    **/
    public static function lintTokens(generated:Array<String>):Array<PrecisionValidationIssue> {
        final issues:Array<PrecisionValidationIssue> = [];
        if (generated == null) {
            return issues;
        }
        final anyCast = ~/([A-Za-z0-9_)][A-Za-z0-9_)]*|[0-9]+)[ \t]+as[ \t]+f(32|64)\b/;
        final intCast = ~/^([0-9]+)[ \t]+as[ \t]+f(32|64)$/;
        final cfgAttr = ~/#\[cfg\(/;
        for (fileIndex in 0...generated.length) {
            final text = generated[fileIndex];
            if (text == null) {
                continue;
            }
            var inBlockComment = false;
            var previousWasCfg = false;
            var lineNo = 0;
            for (rawLine in text.split("\n")) {
                lineNo++;
                final code = stripRustNoise(rawLine, inBlockComment);
                inBlockComment = code.inBlock;
                final line = code.text;
                final isCfgLine = cfgAttr.match(line);
                // bare / unknown float literals
                final bareLiteral = ~/([^A-Za-z0-9_.]|^)([0-9]+\.[0-9]+([eE][+-]?[0-9]+)?)([A-Za-z][A-Za-z0-9]*)?/;
                var probe = line;
                while (bareLiteral.match(probe)) {
                    final matched = bareLiteral.matched(2);
                    final after = bareLiteral.matched(4) != null ? bareLiteral.matched(4) : "";
                    final whole = bareLiteral.matched(0);
                    if (after == "") {
                        push(issues, FP_V_9_TOKEN_LINT, "gen:" + fileIndex + ":" + lineNo,
                            "bare-float-literal: '" + matched + "' carries no f32/f64 suffix");
                    } else if (after != "f32" && after != "f64" && !isIntSuffix(after)) {
                        push(issues, FP_V_9_TOKEN_LINT, "gen:" + fileIndex + ":" + lineNo,
                            "unknown-literal: '" + matched + after + "' has an unrecognized float suffix");
                    }
                    final pos = bareLiteral.matchedPos();
                    final rest = probe.substr(pos.pos + pos.len);
                    if (rest.length == 0 || rest.length >= probe.length) {
                        break;
                    }
                    probe = rest;
                }
                // casts
                var castProbe = line;
                while (anyCast.match(castProbe)) {
                    final whole = StringTools.trim(anyCast.matched(0));
                    final width = anyCast.matched(2);
                    if (intCast.match(whole)) {
                        push(issues, FP_V_9_TOKEN_LINT, "gen:" + fileIndex + ":" + lineNo,
                            "int-to-float-cast: '" + whole
                            + "' (FP-6 provenance; an IntToFloat edge emitted as a cast token instead of a literal with suffix)");
                    } else {
                        push(issues, FP_V_9_TOKEN_LINT, "gen:" + fileIndex + ":" + lineNo,
                            "value-cast: '" + whole + "' is a bare cast to f" + width
                            + " with no registered Narrow/Widen edge");
                    }
                    final pos = anyCast.matchedPos();
                    final rest = castProbe.substr(pos.pos + pos.len);
                    if (rest.length == 0 || rest.length >= castProbe.length) {
                        break;
                    }
                    castProbe = rest;
                }
                // cfg gating a width decision
                final hasFloatToken = ~/[0-9]\.[0-9]|as f(32|64)/.match(line);
                if (isCfgLine && hasFloatToken) {
                    push(issues, FP_V_9_TOKEN_LINT, "gen:" + fileIndex + ":" + lineNo,
                        "cfg-cast-combination: a cfg attribute gates a float width decision on this line");
                } else if (!isCfgLine && previousWasCfg && hasFloatToken) {
                    push(issues, FP_V_9_TOKEN_LINT, "gen:" + fileIndex + ":" + lineNo,
                        "cfg-cast-combination: this width decision is gated by the cfg attribute on the previous line");
                }
                previousWasCfg = isCfgLine;
            }
        }
        return issues;
    }

    /**
        Blank out string literals, line comments and block-comment bodies so
        token scanning sees code only. Tracks multi-line block comments via
        the inBlock flag threaded across lines of one artifact.
    **/
    static function stripRustNoise(line:String, inBlock:Bool):{text:String, inBlock:Bool} {
        final chars = line.split("");
        final out = chars;
        var i = 0;
        var inString = false;
        var stringQuote = "";
        while (i < chars.length) {
            if (inBlock) {
                if (i + 1 < chars.length && chars[i] == "*" && chars[i + 1] == "/") {
                    out[i] = " ";
                    out[i + 1] = " ";
                    i += 2;
                    inBlock = false;
                    continue;
                }
                out[i] = " ";
                i++;
                continue;
            }
            if (inString) {
                if (chars[i] == "\\") {
                    out[i] = " ";
                    if (i + 1 < chars.length) {
                        out[i + 1] = " ";
                    }
                    i += 2;
                    continue;
                }
                if (chars[i] == stringQuote) {
                    inString = false;
                }
                out[i] = " ";
                i++;
                continue;
            }
            if (chars[i] == "\"" || chars[i] == "'") {
                inString = true;
                stringQuote = chars[i];
                out[i] = " ";
                i++;
                continue;
            }
            if (i + 1 < chars.length && chars[i] == "/" && chars[i + 1] == "/") {
                while (i < chars.length) {
                    out[i] = " ";
                    i++;
                }
                break;
            }
            if (i + 1 < chars.length && chars[i] == "/" && chars[i + 1] == "*") {
                out[i] = " ";
                out[i + 1] = " ";
                i += 2;
                inBlock = true;
                continue;
            }
            i++;
        }
        return {text: out.join(""), inBlock: inBlock};
    }

    // ---- helpers ----

    static function push(issues:Array<PrecisionValidationIssue>, rule:String, nodeId:String, message:String):Void {
        issues.push({rule: rule, node_id: nodeId, message: message});
    }

    static function isRegisteredKind(kind:String):Bool {
        return kind == "Narrow" || kind == "Widen" || kind == "Bitcast"
            || kind == "Encode" || kind == "Decode" || kind == "IntToFloat";
    }

    static function hasNarrowEdge(plan:PrecisionPlan):Bool {
        if (plan.conversionEdges == null) {
            return false;
        }
        for (edge in plan.conversionEdges) {
            if (edge != null && edge.kind == "Narrow") {
                return true;
            }
        }
        return false;
    }

    /** Width in bits of an f32/f64/u32/u64 style type token; -1 when unknown. */
    static function widthOf(type:String):Int {
        if (type == null) {
            return -1;
        }
        final t = type.toLowerCase();
        if (t.charCodeAt(t.length - 1) >= 48 && t.charCodeAt(t.length - 1) <= 57) {
            var i = t.length - 1;
            while (i > 0 && t.charCodeAt(i - 1) >= 48 && t.charCodeAt(i - 1) <= 57) {
                i--;
            }
            return Std.parseInt(t.substr(i));
        }
        return -1;
    }

    static function isFloatSuffix(s:String):Bool {
        return s.substr(0, 3) == "f32" || s.substr(0, 3) == "f64"
            || s.substr(0, 3) == "u32" || s.substr(0, 3) == "u64"
            || s.substr(0, 3) == "i32" || s.substr(0, 3) == "i64";
    }

    static function isIntSuffix(s:String):Bool {
        return s.substr(0, 3) == "i32" || s.substr(0, 3) == "i64"
            || s.substr(0, 3) == "u32" || s.substr(0, 3) == "u64";
    }
}