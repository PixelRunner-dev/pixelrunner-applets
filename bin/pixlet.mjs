#!/usr/bin/env node

import * as fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { cm } from 'pixelrunner-shared';

function execute() {
  const platform = process.platform;
  const arch = process.arch;

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  const binaryPath = path.resolve(__dirname, `../bin/${platform}-${arch}`);

  if (!fs.existsSync(binaryPath)) {
    throw new Error(`Not found: ${binaryPath} for ${platform}-${arch}`);
  }

  const binaryProcess = cm.spawnSyncCommand(`${binaryPath}/pixlet`, process.argv.slice(2));

  console.log(binaryProcess.stderr || binaryProcess.stdout);

  process.exit(binaryProcess.status);
}

execute();
