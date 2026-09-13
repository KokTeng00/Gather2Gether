import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';

// Run on checkout in CI, and on the prospective working tree during local work.
const files = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
  encoding: 'utf8',
}).split('\0').filter(file => file && existsSync(file));
const forbidden = files.filter(file => {
  // Only these reviewed templates are exempt. A name containing "example"
  // must never exempt a saved plan, private directory or signing key.
  if (new Set([
    '.env.example.json',
    '.dev.vars.example',
    'infrastructure/terraform/terraform.tfvars.example',
    'ios/Flutter/Signing.xcconfig.example',
  ]).has(file)) return false;
  return /\.(?:tfplan|tfstate|plan)(?:\.|$)/.test(file) ||
    /(?:^|\/)(?:[^/]+\.tfvars(?:\.json)?|key\.properties|\.env(?:\..+)?|\.dev\.vars(?:\..+)?|\.secrets)(?:\/|$)/.test(file) ||
    /\.(?:jks|keystore|p8|p12|mobileprovision)$/.test(file);
});
if (forbidden.length) {
  console.error('Remove private configuration, signing material and Terraform artifacts from Git:');
  forbidden.forEach(file => console.error(`- ${file}`));
  process.exitCode = 1;
} else {
  console.log('Repository check passed: no tracked private configuration or deployment artifacts.');
}
