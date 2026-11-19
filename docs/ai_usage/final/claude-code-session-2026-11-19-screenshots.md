# AI usage log: Claude Code session, 2026-11-19 (screenshots)

| | |
|---|---|
| Tool | Claude Code (VS Code extension) with Claude in Chrome, model Claude Opus 5.5 |
| User | [redacted] |
| Date | 2026-11-19 |
| Branch | `development`. Nothing was committed in the session |
| Outputs | 24 PNG screenshots and an index in [docs/milestones/final/screenshots/](../../milestones/final/screenshots/README.md) |
| Outcome | Redacted screenshots of the live app, the Grafana dashboard, GitHub Actions, the Google Cloud console, and the Azure portal |

Each entry gives the prompt, then a summary of what Claude did in response.

---

## 1. A plan

> Can you come up with a plan to drive my chrome browser and take screenshots of the project?

Claude asked what the screenshots were for, which parts to capture, whether production was running, and how to handle personal data. The user's answers: save PNGs only, without adding them to the report; capture the app, Grafana, GitHub Actions, and the cloud consoles; production was already running; redact before saving. Claude's plan was to redact each page with a script that changes only what the page displays, capture it, and never click buttons that change anything.

## 2. Capturing

The Chrome tools weren't connected at first, and the user connected them. The screenshot tool saves JPEGs, and Claude converted each one to PNG with `ffmpeg`. The user signed in to the app themselves each time. At the user's request, Claude switched the user's role to professor to capture the Manage page, then switched it back to student. That change is recorded twice in `user_audit`.

## 3. What went wrong

- **A lost sign-in.** Claude opened a course by loading its URL directly. The app doesn't keep its sign-in across a page load, so the user had to sign in again. After that, Claude moved around the app only by clicking its links.
- **Missed redactions, caught before saving.**
  - The Admin page showed a nickname ("Josh Jubenville") that the first name list didn't cover.
  - The Google Cloud avatar wasn't blurred on the first try.
  - The Secret Manager page's blur landed on the wrong element and left a popover over the list.
  - The Azure tenant name was only partly redacted.

  Claude found each one in a check screenshot and recaptured the page.
- **A failed shell loop.** A `for` loop written for bash didn't split its words in zsh, and no files were converted. Claude rewrote it as a function.
- **Not redactable:** the YouTube player is in a cross-origin frame, so the video frame and channel name in `05-app-search-player.png` show as they are.
