package dcpe;

/**
    Probe-only entry: makes the probe classes reachable so the typer loads every
    fixture `TSwitch` node for the SubjectProbe dump. Referenced by probe.hxml
    only; no generation hxml lists it.
**/
class ProbeEntry {
	public static function main():Void {
		EvalProbe.main();
		DoubleEvalControl.main();
	}
}
