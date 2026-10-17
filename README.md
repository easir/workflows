# easir/workflows

Reusable GitHub Actions workflows shared across the easir organisation. 43 repositories
call `cicd.yaml`, so treat every change here as a change to everyone's CI.

## Workflows

| workflow | what it does |
|---|---|
| `cicd.yaml` | the main pipeline: install, lint, static analysis, tests, image build, manifest, deploy |
| `cicd-dev.yaml` | same, for development branches |
| `deploy-app.yaml` | deploy an already built image |
| `bugfix-app.yaml` | bugfix branch pipeline |
| `composer-audit.yaml` | scheduled `composer audit --locked`, reads composer.lock, never installs |
| `cicd-cleanup-cache.yaml` | drops caches for a closed branch |

Always reference `@master`. A few callers still pin feature branches; that is drift, not a pattern.

## Calling cicd.yaml

```yaml
jobs:
  cicd:
    uses: easir/workflows/.github/workflows/cicd.yaml@master
    with:
      PhpVersion: "8.4"
      EnablePhpstan: true
    secrets:
      token: ${{ secrets.GITHUB_TOKEN }}
      numa-numa-token: ${{ secrets.GH_TOKEN }}
      docker-reg: ${{ secrets.DOCKER_REGISTRY_URL }}
      docker-login: ${{ secrets.DOCKER_LOGIN }}
      docker-pass: ${{ secrets.DOCKER_REGISTRY_PASSWORD }}
      chartmuseum-url: ${{ secrets.CHART_REPOSITORY_URL }}
      gh-ssh-key: ${{ secrets.GH_SSH_KEY }}
      defectdojo-token: ${{ secrets.DEFECTDOJO_SANDBOX_TOKEN }}
```

`numa-numa-token` needs cross repository read, it is what lets composer and the submodule
checkout reach private easir repositories.

## Input naming

- `Enable*` is off by default, you opt in
- `Disable*` and `Skip*` are on by default, you opt out

Keep new inputs on that convention.

## Inputs you will actually use

### PHP

| input | default | notes |
|---|---|---|
| `PhpVersion` | `8.1` | minor only, no bugfix version |
| `PhpExtensions` | `pdo_sqlite` | comma separated |
| `PhpcsWorkdir` | `./src/` | where the code lives |
| `SkipPhpcs` | `false` | |
| `EnablePhpstan` | `false` | runs `composer exec -- phpstan analyse` |
| `EnablePsalm` | `false` | being retired across the estate, do not add it to new repositories |
| `LintContainer` | `""` | comma separated environments for `bin/console lint:container`, needs `bin/console` |
| `ComposerAudit` | `""` | `report`, or the lowest severity that should fail the build |
| `ComposerVersion` | `latest` | |
| `ComposerAdditionalArguments` | `""` | `--no-scripts` here means composer scripts must run somewhere else |

### Tests

| input | default | notes |
|---|---|---|
| `SkipTests` | `false` | skips the whole test job |
| `SkipUnitTests` | unset | skips phpunit only |
| `UseMakeTargets` | `""` | runs `make <targets>` before the test steps |
| `RunBehatTests` | `false` | |
| `BehatUsePostgresql` | `false` | |

### Services for tests

MariaDB and Redis start by default. PostgreSQL is opt in.

| input | default | notes |
|---|---|---|
| `DisableMariadb` | `false` | MariaDB 10.6.10, root/root on 127.0.0.1:3306, one database `zebra-tests` |
| `DisableRedis` | `false` | valkey 8.1.5 on 6379 |
| `EnablePostgres` | `false` | exports `DATABASE_URL` for you |
| `PostgresVersion` | `16` | |
| `PostgresSchema` | `app` | created after the container is up, also put in `DATABASE_URL` |
| `MariadbInitDir` | `""` | repository directory mounted into `/docker-entrypoint-initdb.d` |
| `PostgresInitDir` | `""` | the same for PostgreSQL |

The init directories run once, when the container initialises an empty data directory.
In CI the container is always fresh, so they run exactly once per job. They are the place
for `CREATE DATABASE` and `CREATE SCHEMA`, which keeps CI and a local docker compose on the
same files instead of duplicating the setup in a test bootstrap. The step fails if the
directory does not exist, because docker would otherwise mount an empty one and the typo
would go unnoticed.

### Image, manifest, deploy

`SkipImageBuild` (default `true`, ignored when the PR carries the `deploy-test` label),
`UseManifest`, `Platforms`, `WithTarget`, `RunSBOM`, and the `Sentry*` group.

### Node

`UseNPM`, `NodeVersion`, `DisableNodeBuild`, `DisableKarmaTests`, `DisableJestTests`,
`AdditionalJestParameters`.

## Traps

- **`EnableMysql` and `EnableRedis` do nothing.** They are declared but never read. At
  least one repository sets them anyway, so removing them would break that caller:
  an unknown input to `workflow_call` is a hard error, not a warning. Leave them.
- **MariaDB starts without a readiness check.** Only the path that mounts `MariadbInitDir`
  waits for it. Anything else that assumes the database is up right after the step is racing.
- **Two steps are hardcoded to one application**, both `if: app == 'zebra'`: the `migrate`
  step and the elasticsearch one. New per application behaviour belongs in an input, or in
  the application's own test bootstrap, not in another `if`.
- **Static analysis is not gated on tests.** `EnablePhpstan` is the only switch for phpstan.
  It used to also require `SkipUnitTests != true`, which meant a repository running its tests
  from a Makefile could never have static analysis.
