import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const packageName = 'gr.modernlanguage.app';
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/edits`;

export function nextVersionCode(local, tracks, bundles = [], apks = []) {
  const codes = [local, ...bundles.map(x => x.versionCode), ...apks.map(x => x.versionCode),
    ...tracks.flatMap(t => (t.releases ?? []).flatMap(r => r.versionCodes ?? []))].map(Number);
  if (codes.some(x => !Number.isSafeInteger(x) || x < 1)) throw new Error('Invalid version code.');
  const next = Math.max(...codes) + 1;
  if (next > 2100000000) throw new Error('Android version code limit exceeded.');
  return next;
}

export function releaseBody(track, existing, versionCode, notes) {
  if (!['internal', 'production'].includes(track)) throw new Error('Unsupported track.');
  if ((existing.releases ?? []).some(r => r.status !== 'completed')) {
    throw new Error('This track has a draft or staged release. Resolve it in Play Console first.');
  }
  if (!notes.trim() || [...notes.trim()].length > 500) throw new Error('Release notes must contain 1-500 characters.');
  return { track, releases: [{ status: 'completed', versionCodes: [String(versionCode)],
    releaseNotes: [{ language: 'el-GR', text: notes.trim() }] }] };
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!['check', 'next-code', 'upload'].includes(command)) {
    console.log('Usage: node scripts/play-console.mjs check | next-code | upload <aab> <internal|production> <notes-file>');
    return;
  }
  let key;
  try {
    key = JSON.parse(readFileSync(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT ?? resolve(root, '.secrets/google-play-service-account.json'), 'utf8').replace(/^\uFEFF/, ''));
  } catch {
    throw new Error('Missing or invalid service account JSON. See docs/play_console_automation_el.md.');
  }
  if (key.type !== 'service_account' || !key.client_email || !key.private_key) throw new Error('Expected a service account JSON key.');
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({ iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(key.private_key, 'base64url');
  const auth = await fetch('https://oauth2.googleapis.com/token', { method: 'POST',
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    signal: AbortSignal.timeout(60000) });
  if (!auth.ok) throw new Error(`Google authentication failed (${auth.status}). Check the service account key.`);
  const { access_token: token } = await auth.json();
  async function request(url, method = 'GET', body, binary = false) {
    const response = await fetch(url, { method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': binary ? 'application/octet-stream' : 'application/json' },
      body: body === undefined ? undefined : binary ? body : JSON.stringify(body),
      signal: AbortSignal.timeout(binary ? 600000 : 60000) });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new Error(`Play API ${response.status}: ${error.error?.message ?? response.statusText}`);
    }
    return response.status === 204 ? {} : response.json();
  }
  let bundle, notes, track;
  if (command === 'upload') {
    if (args.length !== 3) throw new Error('Upload requires an AAB, track and notes file.');
    track = args[1];
    notes = readFileSync(resolve(args[2]), 'utf8').replace(/^\uFEFF/, '');
    releaseBody(track, {}, 1, notes);
    bundle = readFileSync(resolve(args[0]));
  }
  const edit = await request(base, 'POST', {});
  const editUrl = `${base}/${edit.id}`;
  let commitAttempted = false;
  try {
    const { tracks = [] } = await request(`${editUrl}/tracks`);
    if (command === 'check') {
      console.log(`Connected to ${packageName}.`);
      for (const t of tracks) console.log(`${t.track}: ${JSON.stringify(t.releases ?? [])}`);
    } else if (command === 'next-code') {
      const local = readFileSync(resolve(root, 'pubspec.yaml'), 'utf8').match(/^version:\s*\S+\+(\d+)\s*$/m);
      if (!local) throw new Error('Cannot read version code from pubspec.yaml.');
      const [{ bundles = [] }, { apks = [] }] = await Promise.all([
        request(`${editUrl}/bundles`), request(`${editUrl}/apks`)]);
      console.log(nextVersionCode(Number(local[1]), tracks, bundles, apks));
    } else {
      const existing = tracks.find(t => t.track === track) ?? {};
      releaseBody(track, existing, 1, notes);
      const uploaded = await request(`https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${packageName}/edits/${edit.id}/bundles?uploadType=media`, 'POST', bundle, true);
      await request(`${editUrl}/tracks/${track}`, 'PUT', releaseBody(track, existing, uploaded.versionCode, notes));
      await request(`${editUrl}:validate`, 'POST');
      commitAttempted = true;
      await request(`${editUrl}:commit`, 'POST');
      console.log(`Committed version ${uploaded.versionCode} to ${track}. Check Publishing overview for review / managed publishing status.`);
    }
  } catch (error) {
    if (commitAttempted) console.error('Commit was attempted. Check Play Console before retrying; the outcome may be uncertain.');
    throw error;
  } finally {
    if (!commitAttempted) await request(editUrl, 'DELETE').catch(() => console.error('Could not remove temporary edit; it will expire.'));
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
