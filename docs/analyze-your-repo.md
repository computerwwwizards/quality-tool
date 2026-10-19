# Try the demo on your repository

Use this guide to run the demo script, `quality.sh`, on your own
repository. The script is demo code, not a maintained tool, so adapt it if
your setup differs. This guide assumes you ran the demo in the
[README](../README.md) once. To understand what each
step does, read [How it works](how-it-works.md).

The examples use a repository at `~/code/my-repo` and the project key
`my-repo`. If CI already analyzes the repository, or the CI team assigned
it a key, use that key.

## 1. Check the analysis properties

Look for `sonar-project.properties` at the root of your repository.

- If the file exists, keep it as it is. CI uses it, and the local results
  match CI only with the same properties.
- If the file does not exist, create it:

  ```properties
  sonar.projectKey=my-repo
  sonar.sources=src
  sonar.tests=test
  sonar.javascript.lcov.reportPaths=coverage/lcov.info
  ```

- If your tests live next to the code (`src/**/*.test.ts`), use these
  lines instead of `sonar.tests=test`:

  ```properties
  sonar.tests=src
  sonar.test.inclusions=src/**/*.test.ts
  sonar.exclusions=src/**/*.test.ts
  ```

If the file has a `sonar.host.url` that points to another server, you do
not need to change it. `quality.sh scan` always sends the analysis to the
local server.

## 2. Write the reference file

The reference file records the quality gate and the quality profiles that
CI applies to your repository. If you have no CI server to copy from, skip
this step and use `reference/ci-default.json` in step 4.

Every value comes from the web interface of the CI server.

1. Open the project. Type its name in the **Search for projects** box at
   the top right, or select **Projects** in the top bar and select the
   project.
2. Select **Project Information**, at the right end of the bar with
   **Overview**, **Issues**, and **Measures**. A side panel opens.
3. In the panel, read **Quality Gate used** and **Quality Profiles used**.
   They name the gate and one profile for each language. `(Default)` next
   to the gate means that the project uses the default gate of the server.
4. Select **Quality Profiles** in the top bar. Open each profile from step
   3. Write down its parent, if it has one, and its number of active rules.
5. Select **Quality Gates** in the top bar. Open the gate from step 3 and
   write down each condition.
6. Copy `reference/ci-default.json` to `reference/my-team.json` and replace
   the values. The file uses keys, not the labels of the web interface:

   | Label in the web interface | Key in the file |
   |---|---|
   | **Coverage on New Code** | `new_coverage` |
   | **Coverage** | `coverage` |
   | **is less than** | `LT` |
   | **is greater than** | `GT` |
   | **JavaScript**, **TypeScript**, **CSS** | `js`, `ts`, `css` |

   `GET /api/metrics/search` on the CI server lists every metric key. The
   [reference](reference.md#reference-file) explains each field.
7. Open `https://<CI server>/api/server/version` in the browser. Write the
   version in `serverVersion`.

If a profile on the CI server changes rules of its own, the reference file
cannot record those changes. Back up the profile on the CI server
(**Quality Profiles**, then **Back up**). After step 4, restore the XML on
the local server (**Quality Profiles**, then **Restore**), and compare the
number of active rules with the CI server.

## 3. Generate the coverage report

These commands are for a repository that uses Vitest. With another test
runner, turn on its LCOV reporter.

1. Install the dependencies of the repository. If the tests run in a
   subfolder, such as `react/`, run the commands in that subfolder.

   ```bash
   cd ~/code/my-repo
   npm ci
   ```

   `@vitest/coverage-v8` must be a dev dependency.
2. Run the tests with the `lcov` reporter:

   ```bash
   npx vitest run --coverage --coverage.reporter=lcov --coverage.reporter=text-summary
   ```

   The flags add the `lcov` reporter without editing `vitest.config.*`.
3. Check that the report exists:

   ```bash
   ls coverage/lcov.info
   ```

If the configuration has coverage thresholds, Vitest can exit with an
error after it writes the report. The report is still valid.

## 4. Start SonarQube and prepare the project

Set the SonarQube version of the CI server, from step 2. Then run the
commands from the sonarqube-demo folder:

```bash
export SONARQUBE_IMAGE=sonarqube:9.9.8-community
./quality.sh up
./quality.sh token my-repo
./quality.sh reference reference/my-team.json my-repo
```

## 5. Analyze the repository

Pass the root of the repository, the folder that has `.git`:

```bash
./quality.sh scan ~/code/my-repo my-repo
```

If the properties file does not name the coverage report, or the report is
in a subfolder, pass its path:

```bash
./quality.sh scan ~/code/my-repo my-repo \
	-Dsonar.javascript.lcov.reportPaths=react/coverage/lcov.info
```

Any `-Dsonar.key=value` argument after the key overrides the properties
file for this analysis only. Your repository does not change.

## 6. Check the result

Open `http://127.0.0.1:9000/dashboard?id=my-repo` and check:

- The analysis date is the date of your run.
- **Coverage** has a value. If it is 0, the report path or the paths inside
  `lcov.info` do not match the analyzed files.
- **Lines of Code** is close to what you expect. A much larger number means
  that the analysis includes generated or vendor files. Add their folders
  to `sonar.exclusions`.
- **Project Information** shows the profiles and the gate from step 2.

## 7. Export the metrics

```bash
./quality.sh export my-repo
```

The CSV is in `reports/my-repo.csv`, in the sonarqube-demo folder.

## Analyze again after a change

If SonarQube is stopped, run `./quality.sh up`. Then repeat steps 3, 5,
and 7. From the second analysis on, the gate also checks the code that
changed since the first analysis.

## If something fails

| Message | Fix |
|---|---|
| `SonarQube rejected the password of 'admin'` | You changed the password in the web interface. Write it to `.quality/admin.password`. |
| `missing .quality/my-repo.token` | Run `./quality.sh token my-repo`. |
| `quality-sonarqube runs …, not …` | You changed `SONARQUBE_IMAGE`. Run `./quality.sh down --purge`, which deletes the analyses, and start again from step 4. |
| `SCM provider autodetection failed` | You passed a subfolder. Pass the folder that has `.git`. |
