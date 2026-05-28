/**
 * Mock for node:fs filesystem access.
 * Allows tests to control existence of binary paths without real filesystem.
 */

export class MockFilesystem {
  constructor() {
    this.existingPaths = new Set();
  }

  existsSync(path) {
    return this.existingPaths.has(path);
  }

  addPath(path) {
    this.existingPaths.add(path);
  }

  removePath(path) {
    this.existingPaths.delete(path);
  }

  clear() {
    this.existingPaths.clear();
  }

  setPaths(paths) {
    this.existingPaths = new Set(paths);
  }
}

export const mockFilesystem = new MockFilesystem();
