/*
 * Replace the SMS-derived summaries for +250798579079 with the authoritative
 * values computed from the official MTN MoMo statement (tools/momo_summaries.json).
 *
 * Dependency-free: mints a Google OAuth token from the service-account key using
 * Node's built-in crypto, then writes via the Firestore REST API. No npm install.
 *
 *   node tools/update_firestore.js --dry-run                 # preview only
 *   node tools/update_firestore.js                           # uses tools/update_firestore.json
 *   node tools/update_firestore.js /path/to/serviceAccount.json
 *
 * The write is a PATCH with an updateMask, so unrelated fields on the user doc
 * (name, passwordHash, isPublic, createdAt, ...) are preserved.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');

const PROJECT_ID = 'money-dashboard-2026';
const DOC_ID = '+250798579079';
const SCOPE = 'https://www.googleapis.com/auth/datastore';

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const keyPathArg =
  args.find((a) => !a.startsWith('--')) ||
  path.join(__dirname, 'update_firestore.json');

const data = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'momo_summaries.json'), 'utf8')
);

// ---- Firestore typed-value encoders (match the app's schema exactly) --------
const monthlyVal = (arr) => ({
  arrayValue: {
    values: arr.map((m) => ({
      mapValue: {
        fields: {
          month: { stringValue: m.month },
          totalReceived: { doubleValue: m.totalReceived },
          totalSent: { doubleValue: m.totalSent },
          transactionCount: { integerValue: String(m.transactionCount) },
        },
      },
    })),
  },
});
const weeklyVal = (arr) => ({
  arrayValue: {
    values: arr.map((w) => ({
      mapValue: {
        fields: {
          weekStart: { stringValue: w.weekStart },
          totalReceived: { doubleValue: w.totalReceived },
          totalSent: { doubleValue: w.totalSent },
          transactionCount: { integerValue: String(w.transactionCount) },
        },
      },
    })),
  },
});

const fields = {
  dashboardSummaries: monthlyVal(data.dashboardSummaries),
  publicSummaries: monthlyVal(data.publicSummaries),
  publicWeeklySummaries: weeklyVal(data.publicWeeklySummaries),
  momoStatementSummaries: monthlyVal(data.dashboardSummaries),
  momoStatementWeekly: weeklyVal(data.publicWeeklySummaries),
  momoStatementThrough: { stringValue: data.momoStatementThrough },
  dataSource: { stringValue: 'momo-statement' },
  momoStatementImportedAt: { stringValue: new Date().toISOString() },
};

const tr = data.dashboardSummaries.reduce((s, m) => s + m.totalReceived, 0);
const ts = data.dashboardSummaries.reduce((s, m) => s + m.totalSent, 0);
console.log(`Target doc : users/${DOC_ID}`);
console.log(`Months     : ${data.dashboardSummaries.length}`);
console.log(`Weeks      : ${data.publicWeeklySummaries.length}`);
console.log(`Through    : ${data.momoStatementThrough}`);
console.log(`Received   : ${tr.toLocaleString()} RWF`);
console.log(`Sent       : ${ts.toLocaleString()} RWF`);

if (dryRun) {
  console.log('\n--dry-run: no write performed.');
  process.exit(0);
}

// ---- OAuth + REST helpers ---------------------------------------------------
const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

function request(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function getToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: SCOPE,
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })
  );
  const unsigned = `${header}.${claim}`;
  const sig = b64url(crypto.createSign('RSA-SHA256').update(unsigned).sign(sa.private_key));
  const jwt = `${unsigned}.${sig}`;
  const body = `grant_type=${encodeURIComponent(
    'urn:ietf:params:oauth:grant-type:jwt-bearer'
  )}&assertion=${jwt}`;
  const resp = await request(
    {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    },
    body
  );
  if (resp.status !== 200) throw new Error(`token ${resp.status}: ${resp.body}`);
  return JSON.parse(resp.body).access_token;
}

const docPath = `projects/${PROJECT_ID}/databases/(default)/documents/users/${encodeURIComponent(
  DOC_ID
)}`;

async function getDoc(token) {
  const resp = await request({
    hostname: 'firestore.googleapis.com',
    path: `/v1/${docPath}`,
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
  return resp;
}

function summarize(label, resp) {
  if (resp.status !== 200) {
    console.log(`${label}: (status ${resp.status})`);
    return;
  }
  const f = JSON.parse(resp.body).fields || {};
  const ds = f.dashboardSummaries?.arrayValue?.values || [];
  const sumField = (m, k) => {
    const v = m.mapValue.fields[k];
    return v ? Number(v.doubleValue ?? v.integerValue ?? 0) : 0;
  };
  const recv = ds.reduce((s, m) => s + sumField(m, 'totalReceived'), 0);
  const sent = ds.reduce((s, m) => s + sumField(m, 'totalSent'), 0);
  console.log(
    `${label}: dataSource=${f.dataSource?.stringValue ?? '(none)'} ` +
      `months=${ds.length} received=${recv.toLocaleString()} sent=${sent.toLocaleString()}`
  );
}

(async () => {
  const sa = JSON.parse(fs.readFileSync(path.resolve(keyPathArg), 'utf8'));
  const token = await getToken(sa);

  console.log('\n--- reading current record (before) ---');
  summarize('BEFORE', await getDoc(token));

  const mask = Object.keys(fields)
    .map((k) => `updateMask.fieldPaths=${k}`)
    .join('&');
  const body = JSON.stringify({ fields });
  const resp = await request(
    {
      hostname: 'firestore.googleapis.com',
      path: `/v1/${docPath}?${mask}`,
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    },
    body
  );
  if (resp.status !== 200) {
    console.error(`\n✗ Write failed ${resp.status}: ${resp.body}`);
    process.exit(1);
  }

  console.log('\n--- verifying (after) ---');
  summarize('AFTER ', await getDoc(token));
  console.log(`\n✓ Firestore updated for users/${DOC_ID}`);
})().catch((e) => {
  console.error('\n✗ Error:', e.message);
  process.exit(1);
});
