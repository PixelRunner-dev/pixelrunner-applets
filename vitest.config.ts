import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    dir: './test/',
    reporters: process.env.GITHUB_ACTIONS ? ['dot', 'github-actions'] : ['default'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      thresholds: {
        lines: 50,
        functions: 50,
        branches: 50,
        statements: 50
      }
    }
  }
});
