package driver;

import driver.Comparison.ExtraEntry;
import registry.Json;
import registry.JsonException;

/** Parses JSONL results and compares each target with the baseline. */
class CompareCore {
    static function padRight(value:String, filler:String, width:Int):String {
        var result = value;
        while (result.length < width) result = result + filler;
        return result;
    }
    static function optionalText(value:registry.Json.JsonValue, name:String):String {
        final text = Json.stringValue(Json.getField(value, name));
        if (text == null) return "";
        return text + "";
    }

    static function readRecord(text:String):Null<TestRecord> {
        final value = Json.read(text);
        final id = Json.stringValue(Json.getField(value, "id"));
        final verdict = Json.stringValue(Json.getField(value, "verdict"));
        if (id == null) return null;
        if (verdict == null) return null;
        final recordId = id + "";
        if (recordId == "") return null;
        final record:TestRecord = {
            id: recordId,
            name: optionalText(value, "name"),
            verdict: verdict + "",
            message: optionalText(value, "message")
        };
        return record;
    }

    static function find(records:Array<TestRecord>, id:String):Null<TestRecord> {
        for (record in records) if (record.id == id) return record;
        return null;
    }

    static function findTarget(targets:Array<TargetRecords>, id:String):Null<TargetRecords> {
        for (target in targets) if (target.id == id) return target;
        return null;
    }

    /** The declaring module of a test id: the id without its trailing member name. **/
    static function moduleOfId(id:String):String {
        var last = -1;
        var index = 0;
        while (index < id.length) {
            final found = id.indexOf(".", index);
            if (found < 0) {
                break;
            }
            last = found;
            index = found + 1;
        }
        if (last <= 0) {
            return id;
        }
        return id.substr(0, last);
    }

    /**
        The declaration that authorises `id` in bundle `bundleId`, or null.
        An id is authorised only by a declaration of its own module that lists
        the bundle the id was produced by, so a module declared target-only for
        one target never authorises its ids on another.
    **/
    static function findExtra(extras:Array<ExtraEntry>, id:String, bundleId:String):Null<ExtraEntry> {
        final moduleName = moduleOfId(id);
        for (extra in extras) {
            if (extra.module != moduleName) continue;
            for (bundle in extra.bundles) if (bundle == bundleId) return extra;
        }
        return null;
    }

    public static function run(inputs:Array<ResultInput>, baseline:String, ?extraReasons:Array<ExtraEntry>):Comparison {
        final extras:Array<ExtraEntry> = extraReasons == null ? [] : extraReasons;
        final targets:Array<TargetRecords> = [];
        final allIds:Array<String> = [];
        final errors:Array<String> = [];
        final lines:Array<String> = [];
        final declaredExtras:Array<String> = [];
        for (input in inputs) {
            final records:Array<TestRecord> = [];
            for (line in input.text.split("\n")) {
                final value = StringTools.trim(line);
                if (value == "") continue;
                var record:Null<TestRecord> = null;
                try {
                    record = readRecord(value);
                } catch (error:JsonException) {
                    errors.push('Failed to parse JSONL line for ${input.id}: $value');
                }
                if (record == null) {
                    errors.push('Invalid test record for ${input.id}: $value');
                    continue;
                }
                if (find(records, record.id) != null) errors.push('[${input.id}] Duplicate test ID: ${record.id}');
                final recordId = record.id + "";
                records.push(record);
                if (allIds.indexOf(recordId) < 0) allIds.push(recordId);
            }
            final target:TargetRecords = {id: input.id, records: records};
            targets.push(target);
        }
        for (index in 1...allIds.length) {
            final value = allIds[index];
            var slot = index;
            while (slot > 0 && allIds[slot - 1] > value) {
                allIds[slot] = allIds[slot - 1];
                slot--;
            }
            allIds[slot] = value;
        }
        final base = findTarget(targets, baseline);
        if (base == null || allIds.length == 0) {
            errors.push('Baseline target "$baseline" produced no test records.');
            final empty:Comparison = {lines: lines, errors: errors, allIds: allIds, declaredExtras: declaredExtras};
            return empty;
        }
        var idWidth = "TEST ID".length;
        for (id in allIds) if (id.length > idWidth) idWidth = id.length;
        final widths:Array<Int> = [];
        for (target in targets) {
            var width = target.id == baseline ? target.id.length + " (baseline)".length : target.id.length;
            for (id in allIds) {
                final record = find(target.records, id);
                final verdict = record == null ? "MISSING" : record.verdict;
                if (verdict.length > width) width = verdict.length;
            }
            widths.push(width);
        }
        final headers = [padRight("TEST ID", " ", idWidth)];
        final separators = [padRight("", "-", idWidth)];
        for (index in 0...targets.length) {
            final target = targets[index].id;
            headers.push(padRight(target == baseline ? target + " (baseline)" : target, " ", widths[index]));
            separators.push(padRight("", "-", widths[index]));
        }
        lines.push(headers.join(" | "));
        lines.push(separators.join("-+-"));
        for (id in allIds) {
            final baseRecord = find(base.records, id);
            final cells = [padRight(id, " ", idWidth)];
            for (index in 0...targets.length) {
                final target = targets[index];
                final record = find(target.records, id);
                cells.push(padRight(record == null ? "MISSING" : record.verdict, " ", widths[index]));
                if (target.id == baseline) continue;
                if (baseRecord == null) {
                    if (record != null) {
                        // A declared extra: the module of this id carries a
                        // verified @only-in marker (read from the bundle roots
                        // files by the roots guard), so the id legitimately
                        // exists outside the baseline for this bundle. It is
                        // reported as a declared extra and never counted as a
                        // divergence.
                        final extra = findExtra(extras, id, target.id);
                        if (extra != null) {
                            final tag = '[${target.id}] $id -- ${extra.reason}';
                            if (declaredExtras.indexOf(tag) < 0) declaredExtras.push(tag);
                        } else {
                            errors.push('[${target.id}] Extra test ID not in baseline: $id');
                        }
                    }
                    continue;
                }
                if (record == null) {
                    errors.push('[${target.id}] Missing test ID present in baseline: $id');
                    continue;
                }
                if (record.verdict == "not_applicable") continue;
                final baseName = baseRecord.name;
                final name = record.name;
                if (baseRecord.verdict != "not_applicable" && baseRecord.verdict != record.verdict) {
                    errors.push('[${target.id}] Verdict mismatch on $id: baseline=${baseRecord.verdict}, actual=${record.verdict}');
                } else if (baseName != name) {
                    errors.push('[${target.id}] Runner name mismatch on $id:\n  baseline: $baseName\n  actual:   $name');
                }
                if (baseRecord.verdict == "fail" && record.verdict == "fail") {
                    final baseMessage = baseRecord.message;
                    final message = record.message;
                    if (baseMessage != message) errors.push('[${target.id}] Failure message mismatch on $id:\n  baseline: $baseMessage\n  actual:   $message');
                }
            }
            lines.push(cells.join(" | "));
        }
        lines.push("");
        final result:Comparison = {lines: lines, errors: errors, allIds: allIds, declaredExtras: declaredExtras};
        return result;
    }
}
