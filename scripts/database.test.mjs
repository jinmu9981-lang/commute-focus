import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { randomUUID } from 'node:crypto';

const db = new PGlite();
const alice = randomUUID(), bob = randomUUID();
before(async () => {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    insert into auth.users values ('${alice}'), ('${bob}');
  `);
  await db.exec(fs.readFileSync(new URL('../supabase/migrations/202610060001_initial.sql', import.meta.url), 'utf8'));
});
after(async () => { await db.close(); });

async function asUser(user) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec('set role authenticated');
}
function change(id = randomUUID(), overrides = {}) {
  return { id, kind: 'task', payload: { id, title: '报告' }, deleted: false, mutation_id: randomUUID(), ...overrides };
}
async function apply(changes) {
  return (await db.query('select * from public.apply_changes($1::jsonb)', [JSON.stringify(changes)])).rows;
}

test('migration works; users cannot read or directly write another account', async () => {
  await asUser(alice);
  const item = change();
  await apply([item]);
  assert.equal((await db.query('select * from public.records where id=$1', [item.id])).rows.length, 1);
  await assert.rejects(db.query('delete from public.records where id=$1', [item.id]), /permission denied/);
  await assert.rejects(db.query('update public.records set deleted=true where id=$1', [item.id]), /permission denied/);
  await asUser(bob);
  assert.equal((await db.query('select * from public.records where id=$1', [item.id])).rows.length, 0);
  const result = await apply([{ ...item, owner_id: alice, mutation_id: randomUUID() }]);
  assert.equal(result[0].owner_id, bob);
});

test('retries are idempotent, even after a subsequent edit', async () => {
  await asUser(alice);
  const first = change();
  const initial = (await apply([first]))[0];
  const again = (await apply([first]))[0];
  assert.equal(again.revision, initial.revision);
  const edit = change(first.id, { payload: { id: first.id, title: '新版本' } });
  const newer = (await apply([edit]))[0];
  const retry = (await apply([first]))[0];
  assert.equal(retry.revision, newer.revision);
  assert.equal(retry.payload.title, '新版本');
});

test('tombstones defeat stale offline resurrection', async () => {
  await asUser(alice);
  const first = change();
  await apply([first]);
  await apply([change(first.id, { deleted: true })]);
  const stale = (await apply([change(first.id)]))[0];
  assert.equal(stale.deleted, true);
});

test('focus history is append-only and record kinds are immutable', async () => {
  await asUser(alice);
  const first = change(undefined, { kind: 'focus' });
  const initial = (await apply([first]))[0];
  const second = (await apply([{ ...first, mutation_id: randomUUID(), deleted: true }]))[0];
  assert.equal(second.revision, initial.revision);
  assert.equal(second.deleted, false);
  await assert.rejects(apply([change(first.id)]), /kind is immutable/);
});

test('invalid batch rolls back all writes; unauthenticated requests fail', async () => {
  await asUser(alice);
  const first = change();
  await assert.rejects(apply([first, change(undefined, { kind: 'invalid' })]), /Invalid record kind/);
  assert.equal((await db.query('select * from public.records where id=$1', [first.id])).rows.length, 0);
  await asUser('');
  await assert.rejects(apply([change()]), /Authentication required/);
  await db.exec('reset role; set role anon');
  await assert.rejects(apply([change()]), /permission denied/);
});
