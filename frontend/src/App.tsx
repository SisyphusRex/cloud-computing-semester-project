import { Navigate, Route, Routes } from "react-router";
import { useAuth } from "./auth/AuthContext";
import { Layout } from "./components/Layout";
import { CourseSearchPage } from "./pages/CourseSearchPage";
import { CoursesPage } from "./pages/CoursesPage";
import { ManagePage } from "./pages/ManagePage";
import { SignInPage } from "./pages/SignInPage";

export function App() {
  const { session } = useAuth();
  if (!session) return <SignInPage />;
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<CoursesPage />} />
        <Route path="courses/:courseId" element={<CourseSearchPage />} />
        <Route path="manage" element={<ManagePage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
