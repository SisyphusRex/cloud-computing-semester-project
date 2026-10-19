import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { AdminUser } from "../api/types";
import { fakeApi, renderPage } from "../test/render";
import { AdminPage, parseEmails } from "./AdminPage";

function user(id: number, email: string, extra: Partial<AdminUser> = {}): AdminUser {
  return {
    id,
    email,
    name: null,
    role: "student",
    is_admin: false,
    is_superuser: false,
    is_active: true,
    status: "active",
    created_at: "2026-10-19",
    ...extra,
  };
}

const ME = user(1, "admin@example.edu", { is_admin: true });
const USERS = [
  ME,
  user(2, "root@example.edu", { is_admin: true, is_superuser: true }),
  user(3, "other-admin@example.edu", { is_admin: true }),
  user(4, "student@example.edu"),
  user(5, "invited@example.edu", { status: "invited" }),
];

function setup(me: Partial<AdminUser> = ME, overrides = {}) {
  const api = fakeApi({ listUsers: vi.fn(() => Promise.resolve(USERS)), ...overrides });
  renderPage(<AdminPage />, { api, role: "student", me, path: "/admin", url: "/admin" });
  return api;
}

describe("parseEmails", () => {
  it("accepts lines, commas and semicolons", () => {
    expect(parseEmails(" a@x.edu\nb@x.edu, c@x.edu;d@x.edu \n")).toEqual([
      "a@x.edu",
      "b@x.edu",
      "c@x.edu",
      "d@x.edu",
    ]);
  });
});

describe("<AdminPage>", () => {
  it("tells non-admins the page isn't for them", () => {
    renderPage(<AdminPage />, { api: fakeApi(), role: "professor", path: "/admin", url: "/admin" });
    expect(screen.getByText("Only admins can manage users.")).toBeInTheDocument();
  });

  it("invites a pasted list of emails with the chosen role", async () => {
    const inviteUsers = vi.fn(() =>
      Promise.resolve({ created: [user(6, "new@example.edu")], already_exists: ["student@example.edu"] }),
    );
    const api = setup(ME, { inviteUsers });

    await userEvent.type(screen.getByLabelText(/Emails/), "new@example.edu, student@example.edu");
    await userEvent.selectOptions(screen.getByLabelText("Role"), "professor");
    await userEvent.click(screen.getByRole("button", { name: "Invite" }));

    expect(inviteUsers).toHaveBeenCalledWith(["new@example.edu", "student@example.edu"], "professor");
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Invited 1. Already had an account: student@example.edu.",
    );
    expect(api.listUsers).toHaveBeenCalledTimes(2);
  });

  it("lets an admin change students and professors, but not admins, superusers or themselves", async () => {
    const updateUser = vi.fn(() => Promise.resolve(USERS[3]));
    setup(ME, { updateUser });

    expect(await screen.findByLabelText("Role for admin@example.edu")).toBeDisabled();
    expect(screen.getByLabelText("Role for root@example.edu")).toBeDisabled();
    expect(screen.getByLabelText("Role for other-admin@example.edu")).toBeDisabled();
    expect(screen.getByLabelText("Admin: student@example.edu")).toBeDisabled();

    await userEvent.selectOptions(screen.getByLabelText("Role for student@example.edu"), "professor");
    expect(updateUser).toHaveBeenCalledWith(4, { role: "professor" });

    const row = screen.getByText("student@example.edu").closest("tr")!;
    await userEvent.click(within(row).getByRole("button", { name: "Disable" }));
    expect(updateUser).toHaveBeenCalledWith(4, { is_active: false });
  });

  it("lets a superuser grant admin", async () => {
    const updateUser = vi.fn(() => Promise.resolve(USERS[3]));
    setup({ ...USERS[1] }, { updateUser });

    await userEvent.click(await screen.findByLabelText("Admin: student@example.edu"));
    expect(updateUser).toHaveBeenCalledWith(4, { is_admin: true });
    expect(screen.getByLabelText("Role for other-admin@example.edu")).toBeEnabled();
  });

  it("cancels an invitation nobody has claimed", async () => {
    const deleteInvitation = vi.fn(() => Promise.resolve());
    setup(ME, { deleteInvitation });

    const row = (await screen.findByText("invited@example.edu")).closest("tr")!;
    await userEvent.click(within(row).getByRole("button", { name: "Cancel invitation" }));
    expect(deleteInvitation).toHaveBeenCalledWith(5);
  });
});
