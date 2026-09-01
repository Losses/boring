/**
 * The release scan (spec 26 ruling 1). The scan is the only network
 * reader: it lists every repository's releases page by page with
 * conditional requests carrying the stored ETag, skips drafts, and
 * returns the manifests with the asset names and URLs recorded verbatim
 * from the listing. The tool performs no artifact download.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { parseManifest, type Manifest } from "./manifest.ts";

/** One release asset: its name and its URL, verbatim from the listing. */
export type ReleaseAsset = { name: string; url: string };

/** One scanned release that participates in the registry. */
export type ScannedRelease = {
  repo: string;
  tag: string;
  assets: ReleaseAsset[];
  manifest: Manifest;
};

/** The scan inputs: the API origin, the repository list, the token, the cache. */
export type ScanOptions = {
  apiBase: string;
  repos: string[];
  token: string;
  cacheDir?: string;
};

type CacheEntry = { etag?: string; body: string };

/** One asset of a listing item: the name and the download URL, both optional JSON. */
type ListingAsset = { name?: string; browser_download_url?: string };

type ListingItem = {
  draft?: boolean;
  tag_name?: string;
  body?: string;
  assets?: ListingAsset[];
};

function cacheFile(cacheDir: string, url: string): string {
  return path.join(cacheDir, Buffer.from(url).toString("base64url"));
}

function loadCache(cacheDir: string | undefined, url: string): CacheEntry | undefined {
  if (!cacheDir) {
    return undefined;
  }
  const file = cacheFile(cacheDir, url);
  if (!fs.existsSync(file)) {
    return undefined;
  }
  return JSON.parse(fs.readFileSync(file, "utf8")) as CacheEntry;
}

function storeCache(cacheDir: string | undefined, url: string, entry: CacheEntry): void {
  if (!cacheDir) {
    return;
  }
  const file = cacheFile(cacheDir, url);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(entry));
}

/** Looks up the URL of one asset by name, verbatim from the listing. */
export function assetUrl(release: ScannedRelease, name: string): string {
  const asset = release.assets.find((candidate) => candidate.name === name);
  if (!asset) {
    throw new Error(`${release.repo} release ${release.tag}: missing asset ${name}`);
  }
  return asset.url;
}

/**
 * Scans every listed repository. Throws, naming the repository, when a
 * listing answers an error status or a manifest does not conform.
 */
export async function scanReleases(options: ScanOptions): Promise<ScannedRelease[]> {
  const releases: ScannedRelease[] = [];
  for (const repo of options.repos) {
    let url = `${options.apiBase}/repos/${repo}/releases?per_page=100`;
    while (url) {
      const cached = loadCache(options.cacheDir, url);
      const headers: Record<string, string> = {
        Authorization: `Bearer ${options.token}`,
        Accept: "application/vnd.github+json",
      };
      if (cached?.etag) {
        headers["If-None-Match"] = cached.etag;
      }
      const response = await fetch(url, { headers });
      let body: string;
      if (response.status === 304) {
        if (!cached) {
          throw new Error(`${repo}: release listing answered 304 without a cached body`);
        }
        body = cached.body;
      } else if (response.ok) {
        body = await response.text();
        storeCache(options.cacheDir, url, { etag: response.headers.get("etag") ?? undefined, body });
      } else {
        throw new Error(`${repo}: release listing returned HTTP ${response.status}`);
      }
      let items: unknown;
      try {
        items = JSON.parse(body);
      } catch {
        throw new Error(`${repo}: release listing is not JSON`);
      }
      if (!Array.isArray(items)) {
        throw new Error(`${repo}: release listing is not an array`);
      }
      for (const item of items as ListingItem[]) {
        if (item.draft) {
          continue;
        }
        const tag = item.tag_name ?? "";
        const manifest = parseManifest(item.body ?? "", repo, tag);
        if (!manifest) {
          continue;
        }
        const assets: ReleaseAsset[] = [];
        for (const asset of item.assets ?? []) {
          if (typeof asset.name === "string" && typeof asset.browser_download_url === "string") {
            assets.push({ name: asset.name, url: asset.browser_download_url });
          }
        }
        releases.push({ repo, tag, assets, manifest });
      }
      const link = response.headers.get("link") ?? "";
      url = /<([^>]+)>;\s*rel="next"/.exec(link)?.[1] ?? "";
    }
  }
  return releases;
}
