"""Render the cost-comparison figures for the final presentation.

Compares the monthly cost of running Lecture Indexer as built (GKE Autopilot +
Cloud SQL + load balancer) against one VM sized for the peak and against owning
the hardware, at 100k, 1M and 10M requests per day. All prices are rough
estimates; edit the constants below and re-run to regenerate both images.

    uv run --with matplotlib python scripts/cost_charts.py
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator, NullLocator

OUT_DIR = Path(__file__).resolve().parent.parent / "docs/milestones/final/figures"

# ---------------------------------------------------------------- cost model
REQUESTS = [100_000, 1_000_000, 10_000_000]
REQUEST_LABELS = ["100k", "1M", "10M"]
OPTIONS = ["Our setup", "VM", "Owned"]

HARDWARE_LIFE_MONTHS = 60  # owned hardware is spread over a 5-year life
# Owned: one-time hardware cost and monthly running cost (power + business internet).
OWNED_HARDWARE = [
    1700,
    1700,
    9000,
]  # one server + UPS; same box; two servers + UPS + switch
OWNED_RUNNING = [110, 110, 240]

# Monthly cost in dollars at each traffic level.
MONTHLY = {
    # Midpoints of $40–60, $70–110, $500–800.
    "Our setup": [50, 90, 650],
    # One VM sized for each level's peak, running 24/7: e2-medium; e2-standard-4
    # (+disk, IP, ~150 GB egress); e2-standard-32 (+SSD, IP, ~1.5 TB egress).
    "VM": [30, 125, 970],
    "Owned": [
        round(h / HARDWARE_LIFE_MONTHS + r)
        for h, r in zip(OWNED_HARDWARE, OWNED_RUNNING)
    ],
}

DETAIL = {
    "Our setup": [
        "min. pods, db-f1-micro, load balancer",
        "bigger Cloud SQL, 2–3 search pods",
        "Cloud SQL + replica, 10–20 pods",
    ],
    "VM": [
        "e2-medium",
        "e2-standard-4 (4 vCPU, 16 GB)",
        "e2-standard-32 (32 vCPU, 128 GB)",
    ],
    "Owned": [
        "one server, power, internet",
        "same server",
        "two servers, faster internet",
    ],
}

FOOTNOTE = (
    "Estimates: today's list prices, no commitment discounts, no staff time. Peak ≈ 5× the daily average. "
    "Owned = hardware spread over a 5-year life, plus power and business internet."
)

# ---------------------------------------------------------------- palette
# Reference categorical slots 1–3 (validated all-pairs, light mode).
COLOR = {"Our setup": "#2a78d6", "VM": "#eb6834", "Owned": "#1baf7a"}
DASH = {"Our setup": "-", "VM": (0, (6, 3)), "Owned": (0, (2, 2))}  # secondary encoding
MARKER = {"Our setup": "o", "VM": "s", "Owned": "D"}
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"

plt.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.sans-serif": ["Inter", "Segoe UI", "Helvetica", "Arial", "DejaVu Sans"],
        "font.size": 13,
        "text.color": INK,
        "axes.labelcolor": INK_2,
        "axes.edgecolor": AXIS,
        "xtick.color": INK_2,
        "ytick.color": MUTED,
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
    }
)


def header(fig, title: str, subtitle: str) -> None:
    fig.suptitle(title, x=0.012, y=0.95, ha="left", fontsize=26, weight="bold")
    fig.text(0.012, 0.885, subtitle, fontsize=15, color=INK_2)
    fig.text(0.012, 0.02, FOOTNOTE, fontsize=10, color=MUTED, ha="left")


def cheapest(level: int) -> str:
    return min(OPTIONS, key=lambda o: MONTHLY[o][level])


def chart_table() -> Path:
    fig = plt.figure(figsize=(19.2, 10.8), dpi=100)
    header(
        fig, "Monthly cost by traffic", "Cheapest option at each traffic level in bold."
    )
    ax = fig.add_axes((0.04, 0.12, 0.92, 0.72))
    ax.axis("off")

    rows = [
        [f"{label} requests/day"]
        + [f"${MONTHLY[o][level]:,}/mo\n{DETAIL[o][level]}" for o in OPTIONS]
        for level, label in enumerate(REQUEST_LABELS)
    ]
    table = ax.table(
        cellText=rows,
        colLabels=["", *(f"   {o}" for o in OPTIONS)],
        loc="upper center",
        cellLoc="left",
        colLoc="left",
        colWidths=[0.16, 0.28, 0.28, 0.28],
    )
    table.auto_set_font_size(False)
    table.set_fontsize(16)
    table.scale(1, 5.2)
    for (r, c), cell in table.get_celld().items():
        cell.set_facecolor(SURFACE)
        cell.set_edgecolor(GRID)
        cell.visible_edges = "B"
        cell.PAD = 0.04
        text = cell.get_text()
        if r == 0:
            text.set_weight("bold")
            text.set_color(INK_2)
            cell.set_edgecolor(AXIS)
        elif c == 0 or OPTIONS[c - 1] == cheapest(r - 1):
            text.set_weight("bold")
    # A series swatch beside each column header ties the table to the chart.
    fig.canvas.draw()
    for c, opt in enumerate(OPTIONS, start=1):
        bbox = table[0, c].get_window_extent().transformed(fig.transFigure.inverted())
        fig.patches.append(
            plt.Rectangle(
                (bbox.x0 + 0.008, bbox.y0 + bbox.height * 0.25),
                0.006,
                bbox.height * 0.5,
                color=COLOR[opt],
                transform=fig.transFigure,
                figure=fig,
            )
        )
    path = OUT_DIR / "cost-table.png"
    fig.savefig(path, dpi=100)
    plt.close(fig)
    return path


def chart_by_traffic() -> Path:
    fig, ax = plt.subplots(figsize=(19.2, 10.8), dpi=100)
    fig.subplots_adjust(left=0.07, right=0.86, top=0.80, bottom=0.14)
    header(
        fig,
        "Monthly cost vs. requests per day",
        "The VM is cheapest at our traffic, our setup at 1M/day, and owned hardware at 10M/day.",
    )
    ax.set_xscale("log")
    ax.set_yscale("log")
    for opt in OPTIONS:
        ax.plot(
            REQUESTS,
            MONTHLY[opt],
            color=COLOR[opt],
            linestyle=DASH[opt],
            linewidth=2.5,
            marker=MARKER[opt],
            markersize=11,
            markeredgecolor=SURFACE,
            markeredgewidth=2,
        )
        ax.annotate(
            opt,
            xy=(REQUESTS[-1], MONTHLY[opt][-1]),
            xytext=(18, 0),
            textcoords="offset points",
            va="center",
            fontsize=15,
            weight="bold",
            color=INK,
        )
    # Value labels: below the cheapest point, above the dearest, left of the middle one.
    placement = {
        0: ((0, -20), "top", "center"),
        1: ((-18, 0), "center", "right"),
        2: ((0, 20), "bottom", "center"),
    }
    for level, x in enumerate(REQUESTS):
        ordered = sorted(OPTIONS, key=lambda o: MONTHLY[o][level])
        for rank, opt in enumerate(ordered):
            offset, va, ha = placement[rank]
            ax.annotate(
                f"${MONTHLY[opt][level]:,}",
                xy=(x, MONTHLY[opt][level]),
                xytext=offset,
                textcoords="offset points",
                ha=ha,
                va=va,
                fontsize=13,
                color=INK if rank == 0 else INK_2,
                weight="bold" if rank == 0 else "normal",
            )
    ax.text(
        0.0,
        1.02,
        "Points are the three estimates; lines only join them.",
        transform=ax.transAxes,
        fontsize=12,
        color=MUTED,
    )
    ax.set_xlim(REQUESTS[0] / 1.6, REQUESTS[-1] * 1.6)
    ax.set_ylim(15, 2000)
    ax.xaxis.set_major_locator(FixedLocator(REQUESTS))
    ax.xaxis.set_minor_locator(NullLocator())
    ax.set_xticklabels(REQUEST_LABELS, fontsize=15)
    ax.set_xlabel("Requests per day (log scale)", fontsize=14)
    yticks = [20, 50, 100, 200, 500, 1000]
    ax.yaxis.set_major_locator(FixedLocator(yticks))
    ax.yaxis.set_minor_locator(NullLocator())
    ax.set_yticklabels([f"${v:,}" for v in yticks])
    ax.set_ylabel("Cost per month (log scale)", fontsize=14)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.tick_params(length=0)
    path = OUT_DIR / "cost-by-traffic.png"
    fig.savefig(path, dpi=100)
    plt.close(fig)
    return path


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for p in (chart_table(), chart_by_traffic()):
        print(p)
