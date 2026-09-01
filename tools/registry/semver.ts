/**
 * Semver parsing and precedence for the registry generator (spec 26
 * ruling 10). Version ordering across every lane is semver precedence:
 * major, minor, patch, then the prerelease comparison. A version
 * outside semver stops the generation naming it.
 */

/** One parsed version: the three numeric parts plus prerelease identifiers. */
export type Semver = {
  major: number;
  minor: number;
  patch: number;
  pre: string[];
};

/** One major, minor, or patch pair of two versions under comparison. */
type VersionFieldPair = [number, number];

const SEMVER =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

/** Parses one version, or returns undefined when it is outside semver. */
export function parseSemver(version: string): Semver | undefined {
  const match = SEMVER.exec(version);
  if (!match) {
    return undefined;
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    pre: match[4] === undefined ? [] : match[4].split("."),
  };
}

/** Parses one version or throws naming the label that introduced it. */
export function requireSemver(version: string, label: string): Semver {
  const parsed = parseSemver(version);
  if (!parsed) {
    throw new Error(`${label}: version ${version} is outside semver`);
  }
  return parsed;
}

/** States whether the version carries a prerelease part. */
export function isPrerelease(version: string): boolean {
  const parsed = parseSemver(version);
  return parsed !== undefined && parsed.pre.length > 0;
}

function comparePre(a: string[], b: string[]): number {
  if (a.length === 0 && b.length === 0) {
    return 0;
  }
  if (a.length === 0) {
    return 1;
  }
  if (b.length === 0) {
    return -1;
  }
  const size = Math.min(a.length, b.length);
  for (let i = 0; i < size; i++) {
    const left = a[i] ?? "";
    const right = b[i] ?? "";
    const leftDigits = /^\d+$/.test(left);
    const rightDigits = /^\d+$/.test(right);
    if (leftDigits && rightDigits) {
      const diff = Number(left) - Number(right);
      if (diff !== 0) {
        return diff;
      }
    } else if (leftDigits !== rightDigits) {
      return leftDigits ? -1 : 1;
    } else if (left !== right) {
      return left < right ? -1 : 1;
    }
  }
  return a.length - b.length;
}

/**
 * Compares two versions by semver precedence. Both must parse; callers
 * validate versions through requireSemver before sorting.
 */
export function compareSemver(a: string, b: string): number {
  const left = requireSemver(a, "sort");
  const right = requireSemver(b, "sort");
  const fields: VersionFieldPair[] = [
    [left.major, right.major],
    [left.minor, right.minor],
    [left.patch, right.patch],
  ];
  for (const [l, r] of fields) {
    if (l !== r) {
      return l - r;
    }
  }
  return comparePre(left.pre, right.pre);
}
