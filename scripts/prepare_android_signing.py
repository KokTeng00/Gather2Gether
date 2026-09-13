"""Create a private upload key once. Never print passwords or overwrite a key."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
private = root / '.secrets'
keystore = private / 'android-upload.jks'
properties = root / 'android' / 'key.properties'

if keystore.exists() or properties.exists():
    raise SystemExit('Signing material already exists. Preserve it; do not generate a replacement.')
keytool = shutil.which('keytool')
if not keytool:
    raise SystemExit('Install a JDK and make keytool available before generating the upload key.')
private.mkdir(mode=0o700, exist_ok=True)
password = secrets.token_urlsafe(36)
environment = {**os.environ, 'GATHER_UPLOAD_PASSWORD': password}
try:
    result = subprocess.run([
        keytool, '-genkeypair', '-keystore', str(keystore), '-storetype', 'JKS',
        '-alias', 'upload', '-keyalg', 'RSA', '-keysize', '3072',
        '-validity', '10000', '-dname', 'CN=Gather2Gether Upload',
        '-storepass:env', 'GATHER_UPLOAD_PASSWORD',
        '-keypass:env', 'GATHER_UPLOAD_PASSWORD', '-noprompt',
    ], env=environment, capture_output=True, text=True)
    if result.returncode:
        # Avoid relaying provider output into a transcript containing secrets.
        raise SystemExit('keytool failed. Check that your JDK is installed and available.')
    keystore.chmod(0o600)
    with os.fdopen(os.open(properties, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        output.write(f'storeFile=../.secrets/android-upload.jks\n'
                     f'storePassword={password}\nkeyAlias=upload\nkeyPassword={password}\n')
finally:
    environment.pop('GATHER_UPLOAD_PASSWORD', None)
print('Created an upload key in .secrets/android-upload.jks and android/key.properties.')
print('Back up both files securely before uploading a release. Passwords were not printed.')
