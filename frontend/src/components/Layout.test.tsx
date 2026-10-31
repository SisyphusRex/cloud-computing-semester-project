import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ApiError } from "../api/client";
import { fakeApi, renderPage } from "../test/render";
import { Layout } from "./Layout";

const page = { path: "/", url: "/" };

describe("<Layout>", () => {
  it("shows other users their role as a badge", () => {
    renderPage(<Layout />, { api: fakeApi(), role: "professor", ...page });

    expect(screen.getByText("professor")).toBeInTheDocument();
    expect(screen.queryByLabelText("Your role")).not.toBeInTheDocument();
  });

  it("lets an admin switch their own role", async () => {
    const updateUser = vi.fn(() => Promise.resolve({}));
    const refreshMe = vi.fn(() => Promise.resolve());
    renderPage(<Layout />, {
      api: fakeApi({ updateUser } as never),
      role: "student",
      me: { id: 7, is_admin: true },
      refreshMe,
      ...page,
    });

    await userEvent.selectOptions(screen.getByLabelText("Your role"), "professor");

    expect(updateUser).toHaveBeenCalledWith(7, { role: "professor" });
    expect(refreshMe).toHaveBeenCalled();
  });

  it("shows why a switch failed", async () => {
    const error = new ApiError(403, "forbidden", "No.");
    const refreshMe = vi.fn(() => Promise.resolve());
    renderPage(<Layout />, {
      api: fakeApi({ updateUser: vi.fn(() => Promise.reject(error)) }),
      role: "student",
      me: { is_admin: true },
      refreshMe,
      ...page,
    });

    await userEvent.selectOptions(screen.getByLabelText("Your role"), "professor");

    expect(await screen.findByRole("alert")).toHaveTextContent("No.");
    expect(refreshMe).not.toHaveBeenCalled();
  });
});
