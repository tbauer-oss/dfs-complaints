#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const buildDir = process.argv[2] || 'flutter_web/build/web';
const manifestPath = path.join(buildDir, 'AssetManifest.json');
const requiredManifestKey = 'assets/data/dfs_products.csv';
const candidateFiles = [
  path.join(buildDir, 'assets/assets/data/dfs_products.csv'),
  path.join(buildDir, 'assets/data/dfs_products.csv'),
];

function fail(message) {
  console.error(`[asset-guard] ${message}`);
  process.exit(1);
}

if (!fs.existsSync(manifestPath)) {
  fail(`Missing ${manifestPath}. Flutter web build output is incomplete.`);
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
} catch (error) {
  fail(`Cannot parse ${manifestPath}: ${error.message}`);
}

if (!Object.prototype.hasOwnProperty.call(manifest, requiredManifestKey)) {
  fail(`AssetManifest.json does not include '${requiredManifestKey}'. Ensure pubspec.yaml assets are correct.`);
}

const existingCandidates = candidateFiles.filter((filePath) => fs.existsSync(filePath));
if (existingCandidates.length === 0) {
  fail(
    `Built asset file missing. Expected one of:\n- ${candidateFiles.join('\n- ')}`,
  );
}

console.log(`[asset-guard] OK manifestKey=${requiredManifestKey} file=${existingCandidates[0]}`);
