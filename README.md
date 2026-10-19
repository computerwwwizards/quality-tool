# sonarqube-demo

This repository is a throwaway demo, not a maintained tool. It shows how to
measure the technical debt of a repository on your own machine. Its
script, `quality.sh`, runs SonarQube in Docker, analyzes the code and its
test coverage, and writes the results to a CSV file. The source code never
leaves the machine.

In about 10 minutes, you analyze the example app in `examples/vite-app`
and get a CSV with its technical debt, its coverage, and the result of its
quality gate.

| To | Read |
|---|---|
| Understand how the pieces fit and what the numbers mean | [How it works](docs/how-it-works.md) |
| Analyze your own repository | [Analyze your repository](docs/analyze-your-repo.md) |
| Look up a command, a variable, or a CSV column | [Reference](docs/reference.md) |
| Know why this demo exists | [Running a code quality tool locally for a new repository](https://medium.com/@dryor/running-a-code-quality-tool-locally-for-a-new-repository-350104de89f5) |

## Before you start

You need:

- Docker Engine. Docker Desktop also runs the demo, but large companies
  need a paid subscription for it. On macOS, Colima runs Docker Engine.
- `curl` and `jq`.
- Node.js 22.12 or later, for the tests of the example app.
- About 2 GB of free memory.

Check that Docker works:

```bash
docker run --rm hello-world
```

You see `Hello from Docker!`.

Clone this repository and open its folder. Run every command on this page
from that folder.

## 1. Start SonarQube

```bash
./quality.sh up
```

The first run downloads the image and takes about a minute. When it ends,
you see:

```text
SonarQube is UP at http://127.0.0.1:9000
```

SonarQube now runs in a container that only your machine can reach.

## 2. Create the project

```bash
./quality.sh token vite-app
```

```text
created project vite-app
token written to /…/sonarqube-demo/.quality/vite-app.token
```

SonarQube keeps the results of `vite-app` in this project. The token lets
the scanner send analyses to this project, and nothing else.

## 3. Apply the rules

```bash
./quality.sh reference reference/ci-default.json vite-app
```

```text
profile Sonar way (js): 219 rules
profile Sonar way (ts): 208 rules
profile Sonar way (css): 23 rules
gate CI default: 12 conditions
```

A quality profile lists the rules that the scanner checks. A quality gate
lists the conditions that fail the analysis. `reference/ci-default.json`
records the default gate and profiles of a CI server, so the demo uses the
same rules and conditions as that server.

## 4. Generate the coverage report

```bash
cd examples/vite-app
npm ci
npm run coverage
cd ../..
```

Vitest runs the tests, prints a coverage summary, and writes
`coverage/lcov.info`. SonarQube does not run tests. In step 5, the scanner
reads that file.

## 5. Analyze the code

```bash
./quality.sh scan examples/vite-app vite-app
```

The scanner reads the code and the coverage report, and sends the result
to SonarQube. It prints `SCM provider autodetection failed`, because
`examples/vite-app` has no `.git` folder of its own. The analysis still
completes. The last line is:

```text
analysis AaFV… processed
```

## 6. Export the metrics

```bash
./quality.sh export vite-app
```

```text
wrote /…/sonarqube-demo/reports/vite-app.csv
```

The file has one row for each of 11 metrics. These are four of them:

```csv
"project_key","analysis_date","metric_key","metric_name","metric_type","value"
"vite-app","2026-10-19T18:46:45+0000","sqale_index","Technical Debt","WORK_DUR","20"
"vite-app","2026-10-19T18:46:45+0000","code_smells","Code Smells","INT","2"
"vite-app","2026-10-19T18:46:45+0000","coverage","Coverage","PERCENT","12.2"
"vite-app","2026-10-19T18:46:45+0000","alert_status","Quality Gate Status","LEVEL","ERROR"
```

`sqale_index` is `20`, which means 20 minutes of work to fix the two code
smells in `src/cart.js`. `alert_status` is `ERROR` because the gate
requires 80 % coverage and the tests cover 12.2 %.
[How it works](docs/how-it-works.md#each-number-comes-from-a-fixed-formula)
explains each number.

## 7. Look at the dashboard

Open `http://127.0.0.1:9000/dashboard?id=vite-app` and log in as `admin`
with password `admin`.

SonarQube asks you to change the password. `token`, `reference`, `scan`,
and `export` use that password, so save the new one now. Create the file with
owner-only access:

```bash
touch .quality/admin.password
chmod 600 .quality/admin.password
```

Write the new password in `.quality/admin.password` with your editor.

## 8. Stop SonarQube

```bash
./quality.sh down
```

`down` keeps the analysis for the next `up`. To delete the analyses and
reset the password to `admin`, run `./quality.sh down --purge`.

## Next

To analyze your own repository, follow
[Analyze your repository](docs/analyze-your-repo.md).
