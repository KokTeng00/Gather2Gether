import {existsSync, readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).map(arg => arg.replace(/^--/, '').split('=')));
const platform = args.platform;
if (!['android', 'ios'].includes(platform)) {
  console.error('Usage: npm run check:beta -- --platform=android|ios --config=.env.json');
  process.exit(1);
}
const errors = [];
const readJson = path => {
  try { return JSON.parse(readFileSync(path, 'utf8')); }
  catch { errors.push(`Provide a valid JSON configuration: ${path}`); return {}; }
};
const client = readJson(args.config ?? '.env.json');
const edge = readJson('wrangler.jsonc').vars ?? {};
const push = readJson('wrangler.push.jsonc').vars ?? {};
const configured = value => typeof value === 'string' && value.trim().length > 0 &&
  !/replace-with|your-|example\.(com|test|invalid)|YOUR_/.test(value);
const enabled = value => value === true || value === 'true';
for (const key of ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'EDGE_API_URL']) {
  if (!configured(client[key])) errors.push(`Set ${key} in the mobile configuration.`);
}
for (const key of ['SUPABASE_URL', 'EDGE_API_URL']) {
  try {
    if (new URL(client[key]).protocol !== 'https:') throw new Error();
  } catch { errors.push(`${key} must use HTTPS.`); }
}
if (!configured(edge.APP_OPERATOR_NAME)) errors.push('Set APP_OPERATOR_NAME in the Pages vars after reviewing the policy text.');
if (!configured(edge.SUPPORT_EMAIL) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(edge.SUPPORT_EMAIL ?? '')) {
  errors.push('Set a real public SUPPORT_EMAIL in the Pages vars.');
}
if (enabled(client.REMOTE_PUSH_ENABLED) !== enabled(push.REMOTE_PUSH_ENABLED)) {
  errors.push('The app and dispatcher must agree on REMOTE_PUSH_ENABLED.');
}
if (enabled(client.REMOTE_PUSH_ENABLED)) {
  for (const key of ['FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID',
    `FIREBASE_${platform.toUpperCase()}_API_KEY`, `FIREBASE_${platform.toUpperCase()}_APP_ID`]) {
    if (!configured(client[key])) errors.push(`Remote push requires ${key}.`);
  }
  if (client.FIREBASE_PROJECT_ID !== push.FIREBASE_PROJECT_ID) errors.push('The Firebase project IDs must match.');
}
if (platform === 'android') {
  const propertiesPath = 'android/key.properties';
  const properties = existsSync(propertiesPath) ? Object.fromEntries(readFileSync(propertiesPath, 'utf8')
    .split(/\r?\n/).filter(line => line && !line.startsWith('#')).map(line => {
      const at = line.indexOf('='); return [line.slice(0, at).trim(), line.slice(at + 1).trim()];
    })) : {};
  const store = process.env.ANDROID_KEYSTORE_PATH ?? properties.storeFile;
  if (!store || !existsSync(resolve('android', store))) errors.push('Create/configure the Android upload keystore.');
  for (const [environment, property] of [
    ['ANDROID_KEYSTORE_PASSWORD', 'storePassword'], ['ANDROID_KEY_ALIAS', 'keyAlias'], ['ANDROID_KEY_PASSWORD', 'keyPassword'],
  ]) {
    if (!configured(process.env[environment] ?? properties[property])) errors.push(`Configure Android release signing: ${property}.`);
  }
} else {
  if (!enabled(client.APPLE_SIGN_IN_ENABLED)) errors.push('Configure Apple OAuth and enable APPLE_SIGN_IN_ENABLED for the iOS beta.');
  const signing = existsSync('ios/Flutter/Signing.xcconfig') ? readFileSync('ios/Flutter/Signing.xcconfig', 'utf8') : '';
  if (!/^DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*$/m.test(signing)) errors.push('Configure your Apple team in ios/Flutter/Signing.xcconfig.');
  if (enabled(client.REMOTE_PUSH_ENABLED) && !/^CODE_SIGN_ENTITLEMENTS\s*=\s*Runner\/RunnerPush.entitlements\s*$/m.test(signing)) {
    errors.push('Enable RunnerPush.entitlements in Signing.xcconfig.');
  }
}
if (errors.length) {
  console.error('External beta is blocked:');
  errors.forEach(error => console.error(`- ${error}`));
  process.exitCode = 1;
} else {
  console.log(`Local ${platform} release configuration is ready. Run tests, verify deployed policy URLs, and device-test the signed build before distribution.`);
}
