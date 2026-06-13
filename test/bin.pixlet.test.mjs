import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

vi.mock('node:fs', () => ({
  existsSync: vi.fn(),
}));

vi.mock('pixelrunner-shared/backend', () => ({
  cm: {
    spawnSyncCommand: vi.fn(),
  },
  logger: {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
  },
}));

describe('bin/pixlet.mjs', () => {
  let exitSpy;
  let stdoutSpy;
  let stderrSpy;

  beforeEach(() => {
    vi.resetModules();
    exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => {});
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
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
    await importPixlet([], { spawnResult: { status: 0, stdout: Buffer.from('stdout data'), stderr: Buffer.from('stderr msg') } });
    expect(stderrSpy).toHaveBeenCalledWith(expect.objectContaining({ length: expect.any(Number) }));
  });

  it('logs stdout when stderr is empty', async () => {
    await importPixlet([], { spawnResult: { status: 0, stdout: Buffer.from('stdout msg'), stderr: Buffer.alloc(0) } });
    expect(stdoutSpy).toHaveBeenCalled();
  });

  it('checks existsSync with platform-arch binary directory', async () => {
    const { existsSync } = await importPixlet();
    expect(existsSync).toHaveBeenCalledWith(
      expect.stringContaining(`bin/${process.platform}-${process.arch}`)
    );
  });

  it('exits 1 when binary not found', async () => {
    const { logger } = await import('pixelrunner-shared/backend');
    await importPixlet([], { binaryExists: false });
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(logger.error).toHaveBeenCalledWith(expect.stringContaining('Not found'));
  });
});
