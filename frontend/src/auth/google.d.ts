// The parts of Google Identity Services (https://accounts.google.com/gsi/client) we use.

interface GoogleCredentialResponse {
  credential: string;
}

interface GoogleTokenResponse {
  access_token: string;
  expires_in: number;
  error?: string;
  error_description?: string;
}

interface GoogleTokenClient {
  requestAccessToken(overrides?: { prompt?: string }): void;
}

interface Window {
  google?: {
    accounts: {
      id: {
        initialize(options: {
          client_id: string;
          callback: (response: GoogleCredentialResponse) => void;
          auto_select?: boolean;
        }): void;
        renderButton(parent: HTMLElement, options: Record<string, string | number>): void;
        disableAutoSelect(): void;
      };
      oauth2: {
        initTokenClient(options: {
          client_id: string;
          scope: string;
          hint?: string;
          callback: (response: GoogleTokenResponse) => void;
          error_callback?: (error: { type: string; message?: string }) => void;
        }): GoogleTokenClient;
      };
    };
  };
}
