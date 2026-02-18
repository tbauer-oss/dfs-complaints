#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const buildDir = process.argv[2] || 'flutter_web/build/web';
const requiredManifestKey = 'assets/data/dfs_products.csv';

const manifestCandidates = [
  path.join(buildDir, 'AssetManifest.json'),
  path.join(buildDir, 'assets', 'AssetManifest.json'),
  path.join(buildDir, 'assets', 'AssetManifest.bin.json'),
  path.join(buildDir, 'flutter_assets', 'AssetManifest.json'),
  path.join(buildDir, 'flutter_assets', 'AssetManifest.bin.json'),
];

const candidateFiles = [
  path.join(buildDir, 'assets/assets/data/dfs_products.csv'),
  path.join(buildDir, 'assets/data/dfs_products.csv'),
  path.join(buildDir, 'flutter_assets/assets/data/dfs_products.csv'),
  path.join(buildDir, 'flutter_assets/data/dfs_products.csv'),
];

function fail(message) {
  console.error(`[asset-guard] ${message}`);
  process.exit(1);
}

function parseJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  try {
    return JSON.parse(raw);
  } catch (error) {
    fail(`Cannot parse ${filePath}: ${error.message}`);
  }
}

function manifestContainsKey(manifest, key) {
  if (!manifest) return false;
  if (Array.isArray(manifest)) return manifest.includes(key);
  if (typeof manifest === 'string') return manifest.includes(key);
  if (typeof manifest === 'object') {
    if (Object.prototype.hasOwnProperty.call(manifest, key)) return true;
    const values = Object.values(manifest);
    return values.some((entry) => {
      if (Array.isArray(entry)) return entry.includes(key);
      if (typeof entry === 'string') return entry.includes(key);
      return false;
    });
  }
  return false;
}

const existingManifestCandidates = manifestCandidates.filter((filePath) => fs.existsSync(filePath));
if (existingManifestCandidates.length === 0) {
  fail(
    `Missing asset manifest. Checked:\n- ${manifestCandidates.join('\n- ')}`,
  );
}

const manifestPath = existingManifestCandidates[0];
const manifest = parseJsonFile(manifestPath);
if (!manifestContainsKey(manifest, requiredManifestKey)) {
  fail(`Manifest ${manifestPath} does not include '${requiredManifestKey}'. Ensure pubspec.yaml assets are correct.`);
}

const existingCandidates = candidateFiles.filter((filePath) => fs.existsSync(filePath));
if (existingCandidates.length === 0) {
  fail(
    `Built asset file missing. Expected one of:\n- ${candidateFiles.join('\n- ')}`,
  );
}

console.log(`[asset-guard] OK manifest=${manifestPath} manifestKey=${requiredManifestKey} file=${existingCandidates[0]}`);
