# Reference

This page describes the demo script, `quality.sh`. It is demo code, not a
maintained tool.

## Commands

| Command | What it does |
|---|---|
| `./quality.sh up` | Creates the `quality-net` network and the volumes if they do not exist. Starts the `quality-sonarqube` container with telemetry off, and waits until `GET /api/system/status` returns `UP`. Fails if the existing container uses another image. |
| `./quality.sh token <key>` | Creates the project if it does not exist. Revokes the token `quality-<key>` if it exists, and writes a new project analysis token to `.quality/<key>.token` with mode `600`. |
| `./quality.sh reference <file> <key>` | Applies a reference file to the project. See [Reference file](#reference-file). Fails if the project does not exist. |
| `./quality.sh scan <repo> <key> [-Dsonar.key=value ...]` | Runs the scanner with the repository mounted read-only and `sonar.host.url` set to the local server. Waits until SonarQube processes the analysis. A failed quality gate is not an error. Fails if `.quality/<key>.token` does not exist, or if an extra argument does not have the form `-Dsonar.key=value`. |
| `./quality.sh export <key> [file]` | Writes the metrics to `reports/<key>.csv` in the sonarqube-demo folder, or to `file`, relative to the current folder. |
| `./quality.sh down` | Removes the container. Keeps the volumes, so the analyses stay. |
| `./quality.sh down --purge` | Also removes the volumes and the network. Deletes every analysis and resets the password to `admin`. Keeps `.quality/` and `reports/`. |

## Environment variables

| Variable | Default | Use |
|---|---|---|
| `SONARQUBE_IMAGE` | `sonarqube:9.9.8-community` | The SonarQube version. Match the CI server. |
| `SCANNER_IMAGE` | `sonarsource/sonar-scanner-cli:11.3.1.1910_7.1.0` | The scanner version. The image has SonarScanner CLI 7.1.0 and the Node.js 18 that the JavaScript analysis of SonarQube 9.9 needs. |
| `SONAR_PORT` | `9000` | The port on `127.0.0.1`. |
| `SONAR_ADMIN_USER` | `admin` | The user for the Web API calls. |
| `SONAR_ADMIN_PASSWORD` | The content of `.quality/admin.password`, or `admin` | The password for the Web API calls. |
| `QUALITY_WAIT_SECONDS` | `300` | Seconds that `up` waits for SonarQube to start, and that `scan` waits for the analysis, before they fail. |

## Files

| Path | Content | In Git |
|---|---|---|
| `quality.sh` | The demo script. The `METRICS` array at the top lists the exported metrics. | Yes |
| `reference/*.json` | Reference files. | Yes |
| `test/e2e.sh` | Runs the tutorial from step 1 to step 6 and checks the CSV. | Yes |
| `docs/images/solution.mmd` | The source of `docs/images/solution.png`. | Yes |
| `.quality/<key>.token` | Analysis tokens. | No |
| `.quality/admin.password` | The local admin password, if you changed it. | No |
| `.quality/work/<key>/` | Scanner work files. | No |
| `reports/<key>.csv` | Exported metrics. | No |

## CSV columns

| Column | Content |
|---|---|
| `project_key` | The project key. |
| `analysis_date` | The date of the last analysis, in ISO 8601. |
| `metric_key` | The metric key, such as `sqale_index`. |
| `metric_name` | The name shown in the web interface, such as `Technical Debt`. |
| `metric_type` | `INT` is a count. `WORK_DUR` is minutes. `PERCENT` is a percentage. `RATING` is 1 to 5, for A to E. `LEVEL` is `OK` or `ERROR`. |
| `value` | The value returned by the Web API. |

## Exported metrics

| Key | Meaning |
|---|---|
| `ncloc` | Lines of code, without comments and blank lines. |
| `sqale_index` | Technical debt, in minutes. |
| `sqale_debt_ratio` | Technical debt divided by the cost to write the code (30 minutes per line). |
| `sqale_rating` | Maintainability rating, from the debt ratio. |
| `code_smells` | Maintainability issues. |
| `bugs` | Reliability issues. |
| `vulnerabilities` | Security issues. |
| `security_hotspots` | Code that a person must review for security. |
| `coverage` | Covered lines and conditions, as one percentage. |
| `duplicated_lines_density` | Duplicated lines, as a percentage. |
| `alert_status` | The result of the quality gate. |

`export` skips a key that the server does not know and prints a warning.
To export another metric, add its key to `METRICS`. `GET /api/metrics/search`
lists every key that the server knows.

## Reference file

This example shows every field. `reference/ci-default.json` is a complete
file.

```json
{
	"serverVersion": "9.9.8.100196",
	"retrieved": "2026-10-19",
	"gate": {
		"name": "CI default",
		"conditions": [
			{ "metric": "new_coverage", "op": "LT", "error": "80" },
			{ "metric": "coverage", "op": "LT", "error": "80" }
		]
	},
	"profiles": [
		{ "language": "js", "name": "Sonar way", "activeRules": 219 },
		{ "language": "ts", "name": "Team-TS", "parent": "Sonar way", "activeRules": 208 }
	]
}
```

| Field | Content |
|---|---|
| `serverVersion` | The version of the CI server the values come from. |
| `retrieved` | The date you copied the values. |
| `gate.name` | The gate name. |
| `gate.conditions[]` | One object per condition. `op` is `GT` (greater than) or `LT` (less than). `error` is the threshold. |
| `profiles[].language` | The language key, such as `js`, `ts`, or `css`. |
| `profiles[].name` | The profile name. |
| `profiles[].parent` | Optional. The profile it inherits its rules from. |
| `profiles[].activeRules` | The number of active rules on the CI server. |

`quality.sh reference` does this with the file:

- For each profile with `parent`, it creates the profile if it does not
  exist and sets its parent. The profile inherits every rule of its parent
  and changes none.
- For each profile without `parent`, it uses the existing profile, such as
  the built-in `Sonar way`. It fails if that profile does not exist.
- It assigns every profile to the project, and prints a warning if the
  number of active rules differs from `activeRules`.
- It creates the gate if it does not exist, replaces its conditions with
  the conditions in the file, and selects the gate for the project.
