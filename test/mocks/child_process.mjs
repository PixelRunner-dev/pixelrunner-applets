/**
 * Mock for node:child_process spawnSync.
 * Allows tests to simulate success, failure, missing binary, and stdout/stderr forwarding.
 */

export class MockChildProcess {
  constructor() {
    this.executions = [];
  }

  setResponse(status, stdout = '', stderr = '') {
    this._mockResponse = { status, stdout, stderr };
  }

  setError(error) {
    this._mockError = error;
  }

  spawnSync(cmd, args = [], opts = {}) {
    this.executions.push({ cmd, args, opts });

    if (this._mockError) {
      throw this._mockError;
    }

    if (this._mockResponse) {
      return {
        status: this._mockResponse.status,
        stdout: Buffer.from(this._mockResponse.stdout),
        stderr: Buffer.from(this._mockResponse.stderr),
        error: undefined,
        signal: null
      };
    }

    // Default: success with empty output
    return {
      status: 0,
      stdout: Buffer.from(''),
      stderr: Buffer.from(''),
      error: undefined,
      signal: null
    };
  }

  getLastExecution() {
    return this.executions[this.executions.length - 1];
  }

  clearExecutions() {
    this.executions = [];
  }
}

export const mockChildProcess = new MockChildProcess();
