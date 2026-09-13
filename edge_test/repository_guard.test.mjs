import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('repository gate accepts reviewed templates and rejects misleading private filenames', () => {
  const directory = mkdtempSync(join(tmpdir(), 'gather-repository-check-'));
  const script = fileURLToPath(new URL('../scripts/check_repository.mjs', import.meta.url));
  try {
    execFileSync('git', ['init', '--quiet', directory]);
    for (const name of ['.env.example.json', '.dev.vars.example', 'infrastructure/terraform/terraform.tfvars.example', 'ios/Flutter/Signing.xcconfig.example']) {
      mkdirSync(dirname(join(directory, name)), {recursive: true});
      writeFileSync(join(directory, name), 'placeholder');
    }
    const run = () => spawnSync(process.execPath, [script], {cwd: directory, encoding: 'utf8'});
    assert.equal(run().status, 0);
    for (const name of ['production-example.tfplan', 'example-signing.p8', '.secrets/example.json', 'production.tfvars', '.env.local']) {
      const path = join(directory, name);
      mkdirSync(dirname(path), {recursive: true});
      writeFileSync(path, 'test fixture, never a credential');
      const result = run();
      assert.equal(result.status, 1, name);
      assert.ok(result.stderr.includes(name));
      rmSync(path);
    }
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
