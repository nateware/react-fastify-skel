import { Navigate, useSearchParams } from "react-router";
import { useAuth } from "../lib/auth";
import { AppleSignInButton, GoogleSignInButton } from "../lib/sso-buttons";

export default function Login() {
  const { user, loading } = useAuth();
  const [searchParams] = useSearchParams();
  const error = searchParams.get("error");

  if (!loading && user) {
    return <Navigate to="/" replace />;
  }

  return (
    <main className="flex items-center justify-center min-h-screen">
      <div className="w-full max-w-sm space-y-6 px-4">
        <h1 className="text-2xl font-bold text-center text-gray-900 dark:text-gray-100">Sign In</h1>

        {error && (
          <p className="text-red-600 text-sm text-center">
            Authentication failed. Please try again.
          </p>
        )}

        <div className="space-y-3">
          <GoogleSignInButton />
          <AppleSignInButton />
        </div>
      </div>
    </main>
  );
}
