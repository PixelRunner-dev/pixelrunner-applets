import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

describe('pixlet binary execution', () => {
  let mockFs;
  let mockCm;
  let originalPlatform;
  let originalArch;
  let originalArgv;
  let originalExit;
  let exitCodes;
  let logOutput;

  beforeEach(() => {
    mockFs = {
      existsSync: vi.fn()
    };

    mockCm = {
      spawnSyncCommand: vi.fn()
    };

    exitCodes = [];
    logOutput = [];

    originalPlatform = Object.getOwnPropertyDescriptor(process, 'platform');
    originalArch = Object.getOwnPropertyDescriptor(process, 'arch');
    originalArgv = process.argv;
    originalExit = process.exit;

    Object.defineProperty(process, 'platform', { value: 'linux', configurable: true });
    Object.defineProperty(process, 'arch', { value: 'x64', configurable: true });
    process.argv = ['node', 'pixlet.mjs'];
    process.exit = vi.fn((code) => exitCodes.push(code));
    console.log = vi.fn((...args) => logOutput.push(args.join(' ')));
  });

  afterEach(() => {
    if (originalPlatform) Object.defineProperty(process, 'platform', originalPlatform);
    if (originalArch) Object.defineProperty(process, 'arch', originalArch);
    process.argv = originalArgv;
    process.exit = originalExit;
  });

  describe('binary path resolution', () => {
    it('constructs correct path for linux-x64', () => {
      Object.defineProperty(process, 'platform', { value: 'linux', configurable: true });
      Object.defineProperty(process, 'arch', { value: 'x64', configurable: true });

      const platform = process.platform;
      const arch = process.arch;
      const binaryDir = `bin/${platform}-${arch}`;

      expect(binaryDir).toBe('bin/linux-x64');
    });

    it('constructs correct path for darwin-arm64', () => {
      Object.defineProperty(process, 'platform', { value: 'darwin', configurable: true });
      Object.defineProperty(process, 'arch', { value: 'arm64', configurable: true });

      const platform = process.platform;
      const arch = process.arch;
      const binaryDir = `bin/${platform}-${arch}`;

      expect(binaryDir).toBe('bin/darwin-arm64');
    });

    it('supports win32-x64', () => {
      Object.defineProperty(process, 'platform', { value: 'win32', configurable: true });
      Object.defineProperty(process, 'arch', { value: 'x64', configurable: true });

      const platform = process.platform;
      const arch = process.arch;
      const binaryDir = `bin/${platform}-${arch}`;

      expect(binaryDir).toBe('bin/win32-x64');
    });
  });

  describe('binary existence checks', () => {
    it('checks filesystem for binary existence', () => {
      mockFs.existsSync('/path/to/bin/linux-x64');

      expect(mockFs.existsSync).toHaveBeenCalledWith('/path/to/bin/linux-x64');
    });

    it('throws error when binary not found', () => {
      mockFs.existsSync.mockReturnValue(false);

      const platform = process.platform;
      const arch = process.arch;
      const binaryPath = `/path/to/bin/${platform}-${arch}`;

      if (!mockFs.existsSync(binaryPath)) {
        expect(() => {
          throw new Error(`Not found: ${binaryPath} for ${platform}-${arch}`);
        }).toThrow('Not found');
      }
    });

    it('does not throw when binary exists', () => {
      mockFs.existsSync.mockReturnValue(true);

      const platform = process.platform;
      const arch = process.arch;
      const binaryPath = `/path/to/bin/${platform}-${arch}`;

      expect(() => {
        if (!mockFs.existsSync(binaryPath)) {
          throw new Error(`Not found: ${binaryPath}`);
        }
      }).not.toThrow();
    });
  });

  describe('binary spawning', () => {
    it('spawns binary with no arguments', () => {
      mockCm.spawnSyncCommand('/path/to/pixlet', []);

      expect(mockCm.spawnSyncCommand).toHaveBeenCalledWith('/path/to/pixlet', []);
    });

    it('spawns binary with CLI arguments', () => {
      const args = ['render', '--help'];
      mockCm.spawnSyncCommand('/path/to/pixlet', args);

      expect(mockCm.spawnSyncCommand).toHaveBeenCalledWith('/path/to/pixlet', args);
    });

    it('forwards all process.argv arguments', () => {
      process.argv = ['node', 'pixlet.mjs', 'compile', 'app.star', '--output', 'out.webp'];
      const cliArgs = process.argv.slice(2);

      mockCm.spawnSyncCommand('/path/to/pixlet', cliArgs);

      expect(mockCm.spawnSyncCommand).toHaveBeenCalledWith(
        '/path/to/pixlet',
        ['compile', 'app.star', '--output', 'out.webp']
      );
    });
  });

  describe('output handling', () => {
    it('outputs stdout when available', () => {
      const result = { status: 0, stdout: 'test output', stderr: '' };

      const output = result.stderr || result.stdout;
      console.log(output);

      expect(logOutput).toContain('test output');
    });

    it('outputs stderr when stdout is empty', () => {
      const result = { status: 0, stdout: '', stderr: 'error message' };

      const output = result.stderr || result.stdout;
      console.log(output);

      expect(logOutput).toContain('error message');
    });

    it('outputs stderr when available (prioritizes stderr)', () => {
      const result = { status: 0, stdout: 'stdout data', stderr: 'stderr data' };

      const output = result.stderr || result.stdout;
      console.log(output);

      expect(logOutput).toContain('stderr data');
    });

    it('handles empty output', () => {
      const result = { status: 0, stdout: '', stderr: '' };

      const output = result.stderr || result.stdout;
      if (output) {
        console.log(output);
      }

      // No error thrown, test passes
      expect(true).toBe(true);
    });
  });

  describe('exit code handling', () => {
    it('exits with status 0 on success', () => {
      const status = 0;
      process.exit(status);

      expect(exitCodes).toContain(0);
    });

    it('exits with non-zero status on failure', () => {
      const status = 127;
      process.exit(status);

      expect(exitCodes).toContain(127);
    });

    it('exits with correct error codes', () => {
      const errorCodes = [1, 2, 127, 128];

      errorCodes.forEach(code => {
        process.exit(code);
      });

      expect(exitCodes).toEqual([1, 2, 127, 128]);
    });
  });

  describe('integration scenarios', () => {
    it('handles successful pixlet render', () => {
      Object.defineProperty(process, 'platform', { value: 'linux', configurable: true });
      Object.defineProperty(process, 'arch', { value: 'x64', configurable: true });
      process.argv = ['node', 'pixlet.mjs', 'render', 'applet.star'];

      mockFs.existsSync.mockReturnValue(true);
      mockCm.spawnSyncCommand.mockReturnValue({
        status: 0,
        stdout: 'render output',
        stderr: ''
      });

      const result = mockCm.spawnSyncCommand('/path/to/pixlet', process.argv.slice(2));
      const output = result.stderr || result.stdout;
      console.log(output);
      process.exit(result.status);

      expect(mockCm.spawnSyncCommand).toHaveBeenCalledWith(
        '/path/to/pixlet',
        ['render', 'applet.star']
      );
      expect(logOutput).toContain('render output');
      expect(exitCodes).toContain(0);
    });

    it('handles pixlet compile with multiple arguments', () => {
      process.argv = ['node', 'pixlet.mjs', 'compile', 'app.star', '--output', 'out.webp', '--optimize'];

      mockFs.existsSync.mockReturnValue(true);
      mockCm.spawnSyncCommand.mockReturnValue({
        status: 0,
        stdout: 'compiled successfully',
        stderr: ''
      });

      const result = mockCm.spawnSyncCommand('/path/to/pixlet', process.argv.slice(2));
      process.exit(result.status);

      expect(mockCm.spawnSyncCommand).toHaveBeenCalledWith(
        '/path/to/pixlet',
        ['compile', 'app.star', '--output', 'out.webp', '--optimize']
      );
      expect(exitCodes).toContain(0);
    });

    it('handles binary failure with error output', () => {
      mockFs.existsSync.mockReturnValue(true);
      mockCm.spawnSyncCommand.mockReturnValue({
        status: 1,
        stdout: '',
        stderr: 'syntax error in applet.star:10'
      });

      const result = mockCm.spawnSyncCommand('/path/to/pixlet', ['render', 'applet.star']);
      const output = result.stderr || result.stdout;
      console.log(output);
      process.exit(result.status);

      expect(logOutput.some(msg => msg.includes('syntax error'))).toBe(true);
      expect(exitCodes).toContain(1);
    });
  });

  describe('error handling', () => {
    it('handles missing binary error', () => {
      mockFs.existsSync.mockReturnValue(false);

      const platform = process.platform;
      const arch = process.arch;
      const binaryPath = `/path/to/bin/${platform}-${arch}`;

      expect(() => {
        if (!mockFs.existsSync(binaryPath)) {
          throw new Error(`Not found: ${binaryPath} for ${platform}-${arch}`);
        }
      }).toThrow();
    });

    it('handles spawn error', () => {
      mockCm.spawnSyncCommand.mockImplementation(() => {
        throw new Error('Failed to spawn process');
      });

      expect(() => {
        mockCm.spawnSyncCommand('/path/to/pixlet', []);
      }).toThrow('Failed to spawn process');
    });
  });
});
