# F: package tsc diagnostic candidate review

## Current decision

The second TypeScript diagnostic batch in the isolated F checkout is a candidate,
not an accepted integration. An independent rerun of its focused runner exited
zero and retained attempt `attempt-RuxmIjTw`. The successful case recorded tsc
exit zero with empty stdout and stderr. Three negative cases recorded Haxe exit
one. The mapped case identifies the second source call occurrence; the generated
helper remains `Unmapped`. These observations establish the covered fixture
behavior. The path and sidecar boundaries below remain untested.

The first rerun, `attempt-n4En72cN`, stopped in the valid case because the F
checkout had no `tsc` executable on its path. Its wrapper recorded exit 127.
The second rerun used the TypeScript executable installed in the coordinator
checkout, as specified in the executor handoff. The candidate source was
unchanged between the two runs.

## Required corrections before integration

1. `relativeStagePath` mixes a relative stage prefix with absolute diagnostic
   paths. Exercise a relative `ts-output` directory in the real runner and
   require the same source occurrence as the absolute directory case.
2. `runPackageTsc` returns immediately on success and removes the stage later.
   The successful child command's status and separate streams need retained
   evidence, including a case that succeeds while writing output. Name the
   evidence owner for this nested child.
3. Validate the selected sidecar span before constructing a Haxe position.
   Check its generated file and coordinate order, the source range, and whether
   either path escapes its declared root. Bad metadata must resolve to
   `Unmapped`; add negative cases for each boundary.
4. Rerun the full focused procedure after these corrections. Record its exact
   command, exit status, changed source hashes, and the child output files.
   Review those bytes independently before copying the batch into the
   coordinator checkout.

The existing runner proves separate child streams on failure, including a
large output case, and keeps source mapping for repeated direct calls. It also
checks that sidecars do not enter the npm archive. The broader fixed Boring
and Tiqian regressions remain required after candidate integration.

The isolated fixture still carries an old generic directory name. Rename it
for its diagnostic purpose and update all references before integration; the
coordinator's terminology scan must remain clear.
