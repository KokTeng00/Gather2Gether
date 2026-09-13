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
# Supabase publishes identical multi-platform manifests to both registries.
# Keep the digest when falling back so a mirror cannot change test versions.
IMAGE_REGISTRIES = ("docker.io/supabase", "public.ecr.aws/supabase")
POSTGRES_IMAGES = tuple(
    f"{registry}/postgres:17.6.1.155@sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b"
    for registry in IMAGE_REGISTRIES
)
AUTH_IMAGES = tuple(
    f"{registry}/gotrue:v2.195.0@sha256:362659ca70eaa75ba05bbaf963caa84c1c5afe5e8fbf0777e17b830dd5f0f60a"
    for registry in IMAGE_REGISTRIES
)


def prepare_image(candidates, log):
    """Use a cached digest or try official mirrors, within a five-minute budget."""
    for image in candidates:
        cached = subprocess.run(
            ["docker", "image", "inspect", image],
            stdout=log, stderr=subprocess.STDOUT, timeout=15,
        )
        if cached.returncode == 0:
            return image

    deadline = time.monotonic() + 300
    for attempt in range(2):
        if attempt:
            time.sleep(min(5, max(0, deadline - time.monotonic())))
        for image in candidates:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            print(f"Pulling {image.split('@')[0]} (attempt {attempt + 1}/2)", flush=True)
            try:
                result = subprocess.run(
                    ["docker", "pull", image],
                    stdout=log, stderr=subprocess.STDOUT,
                    timeout=min(180, remaining),
                )
            except subprocess.TimeoutExpired:
                continue
            if result.returncode == 0:
                return image
    raise RuntimeError("Could not download the pinned database test image from official registries.")


def main():
    if not shutil.which("docker"):
        raise RuntimeError("Docker is required. Start Docker and retry npm run test:db.")
    container = f"gather2gether-db-check-{uuid.uuid4().hex[:12]}"
    container_requested = False
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
            postgres_image = prepare_image(POSTGRES_IMAGES, log)
            auth_image = prepare_image(AUTH_IMAGES, log)
            # Images may be downloaded, but the running database has no external
            # network, published ports, host mounts, or persistent data volume.
            container_requested = True
            run([
                "docker", "run", "--pull=never", "--detach", "--name", container,
                "--network", "none", "--tmpfs", "/var/lib/postgresql/data:rw",
                "--env", "POSTGRES_PASSWORD=local-test-only",
                "--env", "POSTGRES_DB=postgres", postgres_image,
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
                "docker", "run", "--pull=never", "--rm", "--network", f"container:{container}",
                "--env", "GOTRUE_DB_DRIVER=postgres",
                "--env", "GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:local-test-only@127.0.0.1:5432/postgres",
                "--env", "GOTRUE_SITE_URL=http://127.0.0.1",
                "--env", "GOTRUE_JWT_SECRET=local-regression-secret-with-32-characters",
                "--env", "API_EXTERNAL_URL=http://127.0.0.1",
                auth_image, "auth", "migrate",
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
            if container_requested:
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
