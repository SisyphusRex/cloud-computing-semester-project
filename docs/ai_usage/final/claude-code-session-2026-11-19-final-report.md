# AI usage log: Claude Code session, 2026-11-19 (final report)

| | |
|---|---|
| Tool | Claude Code (VS Code extension), model Claude Opus 5.5 |
| User | [redacted] |
| Date | 2026-11-19 |
| Branch | `development`. Nothing was committed in the session |
| Outputs | [final-report.tex](../../milestones/final/report/final-report.tex), the built [CS6030_F26_FinalReport_LectureIndexer.pdf](../../milestones/final/CS6030_F26_FinalReport_LectureIndexer.pdf), [report-ai-usage.md](../../milestones/final/report-ai-usage.md), a `final-report` target in the Makefile, and `.gitignore` entries for the LaTeX build output |
| Outcome | A 9-page IEEE report (8 pages plus the AI usage appendix) covering every deliverable in the project requirements except the live demo and the architecture presentation, which were given in class |

Each entry gives the prompt, then a summary of what Claude did in response.

---

## 1. A plan for the final report

> Come up with a plan to create a final report for our project that covers all of the deliverables from the project-requirements.md. You can reference the LectureINdexerPresentation.odp as well.

In plan mode, Claude read the requirements, extracted the slide text and speaker notes from the presentation, and read the M2 report's LaTeX source, the elements summary, the security review notes, and the cost analysis session log. It asked four questions. The user's answers:

- **Scope:** leave out the live demo and the architecture presentation, which were already given, and cover every other deliverable from M1 to Final.
- **Format:** IEEE LaTeX, built like the M2 report.
- **Screenshots:** none.
- **Length:** no limit, about 8 to 10 pages.

Claude wrote a plan that maps each deliverable to a section, reuses the M2 preamble and architecture figure, and recounts every figure from the repository. The user approved it.

## 2. Writing and building the report

Claude recounted the figures instead of copying them from the slides:

- 106 Python tests (`pytest --collect-only`) and 39 frontend tests
- 95 of 133 commits co-authored by Claude
- 15 releases
- 42 Markdown files and about 9,400 lines in `docs/`
- the HPA limits, the backup schedule (08:00 UTC), and Cloud Run's 0 to 2 instances

Two of these differ from the slides, which say about 40 files and 7,000 lines of documentation. The report uses the current counts. Claude then wrote the report, redrew the architecture figure for the final system (Azure backups, Grafana Cloud, Cloud Monitoring, GKE Autopilot), added the Makefile target, built the PDF, and checked the rendered pages.

## 3. What went wrong

- **Figure layout.** The first render put YouTube inside the Google Cloud box, ran the captions arrow through the GKE label, drew the Cloud Monitoring arrow through its own box, and overlapped two labels. Claude found each one in a rendered page and fixed it in two more builds.
- **A stale PDF.** The `make` target copied the PDF from the first build. Claude rebuilt it after fixing the figure, so the committed copy matches the source.
- **An invented example.** The draft's twelve-factor lesson gave two examples of cut corners that weren't from any source. Claude removed them before building.
