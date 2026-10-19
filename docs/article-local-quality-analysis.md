# Running a code quality tool locally for a new repository

> SonarQube, the tool in this article, does not guarantee code quality. It
> measures maintainability issues, duplication, and test coverage, but it
> does not show whether the tests would catch a bug. Upcoming articles cover
> tools that complement it.

## Summary

Nobody sees the technical debt of a new repository until someone adds a
quality step to its CI pipeline. Until then, a developer can run SonarQube
Community Edition on their own machine and export its metrics to a CSV
file.

## 1. Situation

Every time a new repository is created:
- It has no CI pipeline step that measures code quality.
- The team responsible for configuring that step is busy with other priorities.

## 2. Complication

We have no visibility of the technical debt in new repositories during the
period between their creation and the configuration of the CI quality step.

Without this information:
- Technical debt grows unnoticed from the first commits.
- Code reviews depend on individual judgment instead of shared criteria.
- Management cannot see or prioritize the cost of that debt.
- When the CI quality step is finally configured, the team faces an
  accumulated backlog of issues at once.

## 3. Constraints

- Developers do not have permissions to configure the CI pipeline.
- Source code cannot leave the developer's physical machine (security
  policies and NDA).
- Developer machines may run only open source tools that need no paid
  license.

## 4. Goal

Measure the technical debt of a new repository on the developer's machine,
with the same rules as the future CI analysis. Put the results in a CSV
file that developers and managers can open.

## 5. Alternatives considered

- **Cloud-hosted quality service.** Source code would leave the
  developer's machine.
- **Docker Desktop.** Requires a paid license in large organizations.
- **IDE plugin only.** No API to extract metrics, and no project-level
  debt summary.
- **Wait for the CI configuration.** Debt keeps growing unnoticed
  meanwhile.

## 6. Solution

The bridge runs SonarQube Community Edition 9.9.8 in a Docker Engine
container on the developer's machine. SonarQube analyzes the repository and
its test coverage, and a script exports the metrics from its Web API to a
CSV file.

Every piece runs on the developer's machine, and the source code never
leaves it. The CSV leaves the machine only when the developer shares it.

![The pieces that run on the developer's machine](https://raw.githubusercontent.com/computerwwwizards/sonarqube-demo/main/docs/images/solution.png)

The local numbers match CI only if the local server checks the same rules
and the same conditions as the CI server. A reference file records the
quality gate and the quality profiles of the CI server, and the script
applies them to the local server before the analysis.

## 7. We published a demo

We published a demo of the bridge in a GitHub repository,
[sonarqube-demo](https://github.com/computerwwwizards/sonarqube-demo). It is throwaway code, not a maintained tool. Its
script, `quality.sh`, runs the whole analysis in six commands. The
repository includes an example app, and its README analyzes that app from
start to end in about 10 minutes. The guide
[Try the demo on your repository](https://github.com/computerwwwizards/sonarqube-demo/blob/main/docs/analyze-your-repo.md) applies
the demo script to your own repository. It also shows where each value of the reference file is in
the web interface of your CI server.

## 8. Result

On a real repository that CI already analyzes, the local run and CI gave
the same values: 21 minutes of technical debt, 3 code smells, and 1
security hotspot.

The demo analyzes a Vite app with 56 lines
of code and Vitest tests. It applies the default quality gate and quality
profiles of a CI server. The app has 20
minutes of technical debt from two code smells. The quality gate fails
because the tests cover 12.2 % of the code, and the gate requires 80 %.
These are four rows of its CSV:

```csv
"project_key","analysis_date","metric_key","metric_name","metric_type","value"
"vite-app","2026-10-19T18:46:45+0000","ncloc","Lines of Code","INT","56"
"vite-app","2026-10-19T18:46:45+0000","sqale_index","Technical Debt","WORK_DUR","20"
"vite-app","2026-10-19T18:46:45+0000","coverage","Coverage","PERCENT","12.2"
"vite-app","2026-10-19T18:46:45+0000","alert_status","Quality Gate Status","LEVEL","ERROR"
```

## 9. Scope and limitations

- This is a temporary bridge until the official CI quality step exists.
  It does not replace it.
- If the CI server runs a commercial edition, some of its rules do not
  exist in the Community Edition, so the local results match only in part.
- The Community Edition keeps one branch per project. Each analysis
  replaces the previous result, whatever branch is checked out, and the
  Community Edition cannot analyze pull requests.

## Ubiquitous language

- **Technical debt.** Estimated effort (in time) to fix the maintainability issues detected by the tool.
- **Local.** The developer's physical machine. Nothing runs on external servers.
- **CI quality step.** The pipeline stage that runs the quality tool automatically on every change.
- **CI server.** The SonarQube server that CI uses. The reference file records its configuration.
- **Local server.** The SonarQube container that runs on the developer's machine. The script writes the configuration of the CI server to it.
- **Reference file.** A JSON file in the sonarqube-demo repository that records the quality profiles and the quality gate of the CI server.
