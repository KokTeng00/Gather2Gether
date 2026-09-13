#!/usr/bin/env python3
"""Apply every migration and SQL regression in a disposable, offline database."""

import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = pathlib.Path(__file__).resolve().parents[1]
POSTGRES_IMAGE = "public.ecr.aws/supabase/postgres:17.6.1.155"
AUTH_IMAGE = "public.ecr.aws/supabase/gotrue:v2.195.0"


def main():
    if not shutil.which("docker"):
        raise RuntimeError("Docker is required. Start Docker and retry npm run test:db.")
    container = f"gather2gether-db-check-{uuid.uuid4().hex[:12]}"
    with tempfile.TemporaryFile(mode="w+") as log:
        def run(command, *, sql=None, timeout=180):
            result = subprocess.run(
                command, input=sql, text=True, stdout=log,
                stderr=subprocess.STDOUT, timeout=timeout,
            )
            if result.returncode:
                raise RuntimeError(f"Command failed: {' '.join(command[:4])}")

        def psql(sql, *, user="postgres", transaction=False):
            command = [
                "docker", "exec", "-i", container, "psql", "-X",
                "-U", user, "-d", "postgres", "-v", "ON_ERROR_STOP=1",
            ]
            if transaction:
                command.extend(["--single-transaction", "--file=-"])
            run(command, sql=sql)

        try:
            # Images may be downloaded, but the running database has no external
            # network, published ports, host mounts, or persistent data volume.
            run([
                "docker", "run", "--detach", "--name", container,
                "--network", "none", "--tmpfs", "/var/lib/postgresql/data:rw",
                "--env", "POSTGRES_PASSWORD=local-test-only",
                "--env", "POSTGRES_DB=postgres", POSTGRES_IMAGE,
            ], timeout=600)
            for _ in range(60):
                ready = subprocess.run(
                    ["docker", "exec", container, "pg_isready", "-h", "127.0.0.1",
                     "-U", "postgres"],
                    stdout=log, stderr=subprocess.STDOUT, timeout=10,
                )
                if ready.returncode == 0:
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError("The disposable database did not become ready.")

            # Bootstrap the official Auth schema before application migrations,
            # including auth.jwt(). No Auth HTTP server is started.
            psql("alter role supabase_auth_admin password 'local-test-only';",
                 user="supabase_admin")
            run([
                "docker", "run", "--rm", "--network", f"container:{container}",
                "--env", "GOTRUE_DB_DRIVER=postgres",
                "--env", "GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:local-test-only@127.0.0.1:5432/postgres",
                "--env", "GOTRUE_SITE_URL=http://127.0.0.1",
                "--env", "GOTRUE_JWT_SECRET=local-regression-secret-with-32-characters",
                "--env", "API_EXTERNAL_URL=http://127.0.0.1",
                AUTH_IMAGE, "auth", "migrate",
            ], timeout=600)

            migrations = sorted((ROOT / "supabase/migrations").glob("*.sql"))
            tests = sorted((ROOT / "supabase/tests").glob("*.sql"))
            if not migrations or not tests:
                raise RuntimeError("Expected both application migrations and SQL tests.")
            for path in migrations:
                psql(path.read_text(), transaction=True)
                print(f"Applied {path.name}", flush=True)
            for path in tests:
                # Existing regression scripts own their BEGIN/ROLLBACK fixture
                # transactions. ON_ERROR_STOP still makes assertions fail CI.
                psql(path.read_text())
                print(f"Passed {path.name}", flush=True)
            print(f"Passed {len(migrations)} migrations and {len(tests)} SQL regressions.")
        except (RuntimeError, subprocess.TimeoutExpired):
            log.seek(0)
            print("\n".join(log.read().splitlines()[-70:]), file=sys.stderr)
            raise
        finally:
            cleanup = subprocess.run(
                ["docker", "rm", "--force", "--volumes", container],
                stdout=log, stderr=subprocess.STDOUT, timeout=30,
            )
            if cleanup.returncode:
                print(f"Check Docker cleanup for {container}.", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
