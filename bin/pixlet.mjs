#!/usr/bin/env node

import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { cm } from 'pixelrunner-shared/backend';

function execute() {
  const platform = process.platform;
  const arch = process.arch;

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const binaryPath = resolve(__dirname, `../bin/${platform}-${arch}`);

  if (!existsSync(binaryPath)) {
    throw new Error(`Not found: ${binaryPath} for ${platform}-${arch}`);
  }

  const binaryProcess = cm.spawnSyncCommand(`${binaryPath}/pixlet`, process.argv.slice(2));

  console.log(binaryProcess.stderr || binaryProcess.stdout);

  process.exit(binaryProcess.status);
}

execute();
