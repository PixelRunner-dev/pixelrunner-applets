import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

vi.mock('node:fs', () => ({
  existsSync: vi.fn(),
}));

vi.mock('pixelrunner-shared/backend', () => ({
  cm: {
    spawnSyncCommand: vi.fn(),
  },
}));

describe('bin/pixlet.mjs', () => {
  let exitSpy;
  let logSpy;

  beforeEach(() => {
    vi.resetModules();
    exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => {});
    logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  async function importPixlet(argv = [], { binaryExists = true, spawnResult = { status: 0, stdout: '', stderr: '' } } = {}) {
    process.argv = ['node', 'pixlet.mjs', ...argv];
    const { existsSync } = await import('node:fs');
    const { cm } = await import('pixelrunner-shared/backend');
    vi.mocked(existsSync).mockReturnValue(binaryExists);
    vi.mocked(cm.spawnSyncCommand).mockReturnValue(spawnResult);
    await import('../bin/pixlet.mjs');
    return { existsSync: vi.mocked(existsSync), spawnSyncCommand: vi.mocked(cm.spawnSyncCommand) };
  }

  it('exits 0 when spawn succeeds', async () => {
    await importPixlet([], { spawnResult: { status: 0, stdout: 'ok', stderr: '' } });
    expect(exitSpy).toHaveBeenCalledWith(0);
  });

  it('exits with spawn status on failure', async () => {
    await importPixlet([], { spawnResult: { status: 1, stdout: '', stderr: 'error' } });
    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  it('exits 1 when signal-killed subprocess returns null status', async () => {
    await importPixlet([], { spawnResult: { status: null, stdout: '', stderr: '' } });
    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  it('spawns binary with platform-arch path', async () => {
    const { spawnSyncCommand } = await importPixlet();
    expect(spawnSyncCommand).toHaveBeenCalledWith(
      expect.stringContaining(`bin/${process.platform}-${process.arch}/pixlet`),
      expect.any(Array)
    );
  });

  it('forwards process.argv slice to spawn', async () => {
    const { spawnSyncCommand } = await importPixlet(['render', 'app.star', '--output', 'out.webp']);
    expect(spawnSyncCommand).toHaveBeenCalledWith(
      expect.any(String),
      ['render', 'app.star', '--output', 'out.webp']
    );
  });

  it('passes empty argv when no extra args', async () => {
    const { spawnSyncCommand } = await importPixlet([]);
    expect(spawnSyncCommand).toHaveBeenCalledWith(expect.any(String), []);
  });

  it('logs stderr when available', async () => {
    await importPixlet([], { spawnResult: { status: 0, stdout: 'stdout data', stderr: 'stderr msg' } });
    expect(logSpy).toHaveBeenCalledWith('stderr msg');
  });

  it('logs stdout when stderr is empty', async () => {
    await importPixlet([], { spawnResult: { status: 0, stdout: 'stdout msg', stderr: '' } });
    expect(logSpy).toHaveBeenCalledWith('stdout msg');
  });

  it('checks existsSync with platform-arch binary directory', async () => {
    const { existsSync } = await importPixlet();
    expect(existsSync).toHaveBeenCalledWith(
      expect.stringContaining(`bin/${process.platform}-${process.arch}`)
    );
  });

  it('throws when binary not found', async () => {
    await expect(importPixlet([], { binaryExists: false })).rejects.toThrow('Not found');
  });
});
