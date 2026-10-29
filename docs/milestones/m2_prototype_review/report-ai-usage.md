# Ai tool used
Claude (Claude Code)
# Purpose
1. To plan a report that maps each Milestone 2 deliverable to evidence in our repository
2. To draft the report in IEEE format and build the pdf
3. To redact email addresses and account details from the screenshots
# Example prompt
Make a plan for creating a report showing how we have met the deliverables for milestone 2.
# Generated output used
This report, CS6030_F26_PrototypeReview_LectureIndexer.pdf
# Verification performed
We checked the report's facts against our deployment notes, test logs, and GitHub release records, took the screenshots ourselves from the live system, and revised the draft until it matched what we built.
# AI use toward Milestone 2
We built the prototype with Claude Code in four logged sessions (October 13–19, 2026). Claude proposed the repository layout and implementation plan; wrote most of the services, Terraform, Kubernetes configuration, CI/CD workflows, and frontend; helped run the real Google/YouTube test; and diagnosed the failed first release attempts. About two thirds of the commits are co-authored by Claude. The team chose the framework and design decisions, approved every plan before Claude built it, made all merges and release approvals, and verified the result with the automated tests and end-to-end testing in production. Each prompt, with a summary of Claude's response, is logged in [docs/ai_usage/](../../ai_usage/).
