import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { ApiProvider } from "./api/ApiContext";
import { App } from "./App";
import { AuthProvider } from "./auth/AuthContext";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <ApiProvider>
          <App />
        </ApiProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
