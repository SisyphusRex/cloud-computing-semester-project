import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { AdminUser, Course } from "../api/types";
import { fakeApi, renderPage } from "../test/render";
import { AdminPage, parseEmails } from "./AdminPage";

function user(id: number, email: string, extra: Partial<AdminUser> = {}): AdminUser {
  return {
    id,
    email,
    name: null,
    role: "student",
    is_admin: false,
    is_active: true,
    status: "active",
    created_at: "2026-10-19",
    ...extra,
  };
}

const ME = user(1, "admin@example.edu", { is_admin: true });
const USERS = [
  ME,
  user(3, "other-admin@example.edu", { is_admin: true }),
  user(4, "student@example.edu"),
  user(5, "invited@example.edu", { status: "invited" }),
];

const COURSES: Course[] = [
  { id: 7, code: "CS6030", title: "Cloud", professor: "Prof", lecture_count: 2 },
];

function setup(overrides = {}, refreshMe?: () => Promise<void>) {
  const api = fakeApi({
    listUsers: vi.fn(() => Promise.resolve(USERS)),
    listCourses: vi.fn(() => Promise.resolve(COURSES)),
    ...overrides,
  });
  renderPage(<AdminPage />, { api, role: "student", me: ME, refreshMe, path: "/admin", url: "/admin" });
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
    const api = setup({ inviteUsers });

    await userEvent.type(screen.getByLabelText(/Emails/), "new@example.edu, student@example.edu");
    await userEvent.selectOptions(screen.getByLabelText("Role"), "professor");
    await userEvent.click(screen.getByRole("button", { name: "Invite" }));

    expect(inviteUsers).toHaveBeenCalledWith(["new@example.edu", "student@example.edu"], "professor");
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Invited 1. Already had an account: student@example.edu.",
    );
    expect(api.listUsers).toHaveBeenCalledTimes(2);
  });

  it("lets an admin change other users, admins included", async () => {
    const updateUser = vi.fn(() => Promise.resolve(USERS[2]));
    const refreshMe = vi.fn(() => Promise.resolve());
    setup({ updateUser }, refreshMe);

    await userEvent.selectOptions(await screen.findByLabelText("Role for student@example.edu"), "professor");
    expect(updateUser).toHaveBeenCalledWith(4, { role: "professor" });

    await userEvent.click(screen.getByLabelText("Admin: student@example.edu"));
    expect(updateUser).toHaveBeenCalledWith(4, { is_admin: true });

    await userEvent.click(screen.getByLabelText("Admin: other-admin@example.edu"));
    expect(updateUser).toHaveBeenCalledWith(3, { is_admin: false });

    const row = screen.getByText("other-admin@example.edu").closest("tr")!;
    await userEvent.click(within(row).getByRole("button", { name: "Disable" }));
    expect(updateUser).toHaveBeenCalledWith(3, { is_active: false });

    expect(refreshMe).not.toHaveBeenCalled();
  });

  it("lets admins change only the role on their own row", async () => {
    const updateUser = vi.fn(() => Promise.resolve(ME));
    const refreshMe = vi.fn(() => Promise.resolve());
    setup({ updateUser }, refreshMe);

    const role = await screen.findByLabelText("Role for admin@example.edu");
    expect(screen.getByLabelText("Admin: admin@example.edu")).toBeDisabled();
    const row = screen.getByText("admin@example.edu").closest("tr")!;
    expect(within(row).queryByRole("button")).not.toBeInTheDocument();

    await userEvent.selectOptions(role, "professor");
    expect(updateUser).toHaveBeenCalledWith(1, { role: "professor" });
    expect(refreshMe).toHaveBeenCalled();
  });

  it("cancels an invitation nobody has claimed", async () => {
    const deleteUser = vi.fn(() => Promise.resolve());
    setup({ deleteUser });

    const row = (await screen.findByText("invited@example.edu")).closest("tr")!;
    await userEvent.click(within(row).getByRole("button", { name: "Cancel invitation" }));
    expect(deleteUser).toHaveBeenCalledWith(5);
  });

  it("deletes a signed-in user after confirming, then reloads users and courses", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValueOnce(false).mockReturnValueOnce(true);
    const deleteUser = vi.fn(() => Promise.resolve());
    const api = setup({ deleteUser });

    const row = (await screen.findByText("student@example.edu")).closest("tr")!;
    const button = within(row).getByRole("button", { name: "Delete" });
    await userEvent.click(button);
    expect(deleteUser).not.toHaveBeenCalled();

    await userEvent.click(button);
    expect(deleteUser).toHaveBeenCalledWith(4);
    expect(confirm).toHaveBeenLastCalledWith(expect.stringContaining("student@example.edu"));
    await vi.waitFor(() => expect(api.listCourses).toHaveBeenCalledTimes(2));
    confirm.mockRestore();
  });

  it("lists every course and deletes one after confirming", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
    const deleteCourse = vi.fn(() => Promise.resolve());
    setup({ deleteCourse });

    const row = (await screen.findByText("CS6030 Cloud")).closest("tr")!;
    expect(row).toHaveTextContent("Prof");
    await userEvent.click(within(row).getByRole("button", { name: "Delete CS6030" }));
    expect(deleteCourse).toHaveBeenCalledWith(7);
    confirm.mockRestore();
  });
});
