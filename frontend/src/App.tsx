import { Navigate, Route, Routes } from "react-router";
import { useApi } from "./api/ApiContext";
import { useAuth } from "./auth/AuthContext";
import { Layout } from "./components/Layout";
import { AdminPage } from "./pages/AdminPage";
import { CourseSearchPage } from "./pages/CourseSearchPage";
import { CoursesPage } from "./pages/CoursesPage";
import { ManagePage } from "./pages/ManagePage";
import { NoAccessPage } from "./pages/NoAccessPage";
import { SignInPage } from "./pages/SignInPage";

export function App() {
  const { session } = useAuth();
  const { accessError } = useApi();
  if (!session) return <SignInPage />;
  // Signed in with Google, but not invited (or disabled): ADR 0002.
  if (accessError) return <NoAccessPage error={accessError} />;
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<CoursesPage />} />
        <Route path="courses/:courseId" element={<CourseSearchPage />} />
        <Route path="manage" element={<ManagePage />} />
        <Route path="admin" element={<AdminPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
