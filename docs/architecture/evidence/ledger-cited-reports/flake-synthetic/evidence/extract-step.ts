// Extract the report step body VERBATIM from the committed workflow blob so the
// proof runs the committed artifact, not a scratch copy.
const repo = process.argv[2];
const out = process.argv[3];
const p = Bun.spawnSync(["git", "-C", repo, "show", "HEAD:.github/workflows/ci.yml"]);
const workflow = new TextDecoder().decode(p.stdout);
const doc = Bun.YAML.parse(workflow) as any;
const steps = doc.jobs["collected-suite"].steps as Array<{ name?: string; run?: string }>;
const step = steps.find((s) => (s.name ?? "").startsWith("Report the counts"));
if (!step?.run) throw new Error("report step not found by name");
await Bun.write(`${out}/step-report-from-yaml.sh`, step.run + "\n");
console.log(`extracted report step (${step.run.length} chars) from HEAD blob -> ${out}/step-report-from-yaml.sh`);
