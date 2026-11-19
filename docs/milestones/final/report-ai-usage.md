# Ai tool used
Claude (Claude Code)
# Purpose
1. To plan a report that covers every remaining course deliverable, using our presentation and repository as sources
2. To draft the report in IEEE format and build the pdf
# Example prompt
Come up with a plan to create a final report for our project that covers all of the deliverables from the project-requirements.md. You can reference the LectureINdexerPresentation.odp as well.
# Generated output used
This report, CS6030_F26_FinalReport_LectureIndexer.pdf
# Verification performed
Claude recounted each figure in the report from the repository (tests, commits, documentation, releases, autoscaling limits, backup schedule) rather than copying it from the slides. We checked the report against our presentation, the cost analysis session log, and the deployed system, and revised it until it matched what we built.
# AI use toward the project
We built Lecture Indexer with Claude Code across eleven logged sessions, from October 13 to November 11, 2026, plus the one that produced this report. Claude wrote most of the code, infrastructure, workflows, and documentation; 95 of 133 commits are co-authored by Claude. The team made the design decisions, approved every plan, and made all merges and release approvals. Each prompt, with a summary of Claude's response, is logged in [docs/ai_usage/](../../ai_usage/). Section XI of the report reflects on this use.
