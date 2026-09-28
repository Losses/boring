# TypeScript source origin fixture

The sidecar stores sparse ranges. A `mapped` span carries a source occurrence; an explicit `unmapped` span identifies generated output such as headers, imports, and filesystem helpers. Coordinates outside every stored span use `defaultResolution`, which is `Unmapped`.

The extra Haxe entry calls `std.Fs.exists`, which selects the production `fsExists` helper. Its generated helper block has an explicit `Unmapped` range. The body assignment is not a supported mapped statement, so its coordinate falls in a gap and the checker resolves it through the default.
