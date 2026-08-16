#!/usr/bin/env node

/*
 * Prints a GitHub App installation token for the current repository. This is
 * intentionally dependency-free so it can be used by both the gh wrapper and
 * Git's credential helper.
 */

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const appId = process.env.GITHUB_APP_ID;
const installationId = process.env.GITHUB_APP_INSTALLATION_ID;
const apiUrl = (process.env.GITHUB_APP_API_URL || 'https://api.github.com').replace(/\/$/, '');
const cacheDirectory = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'github-app');
const cacheSkewSeconds = 120;

function fail(message) {
  process.stderr.write(`github-app-token: ${message}\n`);
  process.exit(1);
}

function readPrivateKey() {
  const keyFile = process.env.GITHUB_APP_PRIVATE_KEY_FILE;
  if (keyFile) {
    try {
      return fs.readFileSync(keyFile, 'utf8');
    } catch (error) {
      fail(`could not read GITHUB_APP_PRIVATE_KEY_FILE (${error.message})`);
    }
  }

  if (process.env.GITHUB_APP_PRIVATE_KEY_B64) {
    return Buffer.from(process.env.GITHUB_APP_PRIVATE_KEY_B64, 'base64').toString('utf8');
  }

  if (process.env.GITHUB_APP_PRIVATE_KEY) {
    return process.env.GITHUB_APP_PRIVATE_KEY.replace(/\\n/g, '\n');
  }

  fail('set GITHUB_APP_PRIVATE_KEY_FILE or GITHUB_APP_PRIVATE_KEY_B64');
}

function run(command, args, input) {
  const result = spawnSync(command, args, { encoding: 'utf8', input });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `${command} exited ${result.status}`).trim());
  }
  return result.stdout;
}

function repositoryFromRemote(remote) {
  const trimmed = remote.trim().replace(/\/$/, '').replace(/\.git$/, '');
  let match = trimmed.match(/^git@[^:]+:([^/]+)\/(.+)$/);
  if (!match) match = trimmed.match(/^[a-z][a-z0-9+.-]*:\/\/[^/]+\/([^/]+)\/(.+)$/i);
  return match ? `${match[1]}/${match[2]}` : undefined;
}

function currentRepository() {
  const explicit = process.env.GITHUB_APP_REPOSITORY || process.env.GH_REPO;
  if (explicit) {
    const parts = explicit.split('/');
    return parts.length >= 2 ? `${parts[parts.length - 2]}/${parts[parts.length - 1]}` : undefined;
  }

  try {
    return repositoryFromRemote(run('git', ['config', '--get', 'remote.origin.url']));
  } catch {
    return undefined;
  }
}

function appJwt(privateKey) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iat: now - 60, exp: now + 540, iss: appId })).toString('base64url');
  const unsigned = `${header}.${payload}`;
  const signature = crypto.createSign('RSA-SHA256').update(unsigned).end().sign(privateKey).toString('base64url');
  return `${unsigned}.${signature}`;
}

function api(method, endpoint, jwt) {
  const response = run('curl', [
    '--fail-with-body', '--silent', '--show-error', '--request', method,
    '--header', 'Accept: application/vnd.github+json',
    '--header', `Authorization: Bearer ${jwt}`,
    '--header', 'X-GitHub-Api-Version: 2022-11-28',
    '--header', 'User-Agent: agent-harness-github-app-token',
    `${apiUrl}${endpoint}`,
  ]);
  try {
    return JSON.parse(response);
  } catch {
    throw new Error('GitHub returned an invalid JSON response');
  }
}

function cachePath(id) {
  return path.join(cacheDirectory, `installation-${id}.json`);
}

function cachedToken(id) {
  try {
    const cached = JSON.parse(fs.readFileSync(cachePath(id), 'utf8'));
    if (cached.token && Date.parse(cached.expires_at) > Date.now() + cacheSkewSeconds * 1000) return cached.token;
  } catch {
    // A missing, expired, or malformed cache entry simply gets replaced.
  }
  return undefined;
}

function saveToken(id, token) {
  fs.mkdirSync(cacheDirectory, { recursive: true, mode: 0o700 });
  fs.chmodSync(cacheDirectory, 0o700);
  const destination = cachePath(id);
  const temporary = `${destination}.${process.pid}`;
  fs.writeFileSync(temporary, JSON.stringify(token), { mode: 0o600 });
  fs.renameSync(temporary, destination);
  fs.chmodSync(destination, 0o600);
}

function main() {
  if (!appId) fail('set GITHUB_APP_ID');
  const privateKey = readPrivateKey();
  let id = installationId;
  const repository = currentRepository();
  const jwt = appJwt(privateKey);

  if (!id) {
    if (!repository) {
      fail('could not identify a repository; set GITHUB_APP_INSTALLATION_ID or GITHUB_APP_REPOSITORY');
    }
    const [owner, repo] = repository.split('/');
    try {
      id = String(api('GET', `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/installation`, jwt).id);
    } catch (error) {
      fail(`could not find this app's installation for ${repository}: ${error.message}`);
    }
  }

  const cached = cachedToken(id);
  if (cached) {
    process.stdout.write(cached);
    return;
  }

  let token;
  try {
    token = api('POST', `/app/installations/${encodeURIComponent(id)}/access_tokens`, jwt);
  } catch (error) {
    fail(`could not mint an installation token: ${error.message}`);
  }
  if (!token.token || !token.expires_at) fail('GitHub returned an incomplete installation token');
  saveToken(id, token);
  process.stdout.write(token.token);
}

main();
