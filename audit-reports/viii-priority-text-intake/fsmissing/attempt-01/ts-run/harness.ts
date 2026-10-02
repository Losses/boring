// Native harness of the dc-fs-missing probe (TypeScript target).
//
// It imports the generated module and calls the generated entry, so every
// observation line comes from the generated tree. It prints nothing of its
// own and catches nothing: whether the host failure reaches the generated
// catch clause is the measurement.
import { FsProbe } from "./fsprobe/FsProbe.ts";

FsProbe.run();
