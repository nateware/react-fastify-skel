import { useAuth } from "../lib/auth";
import { AppleSignInButton, GoogleSignInButton } from "../lib/sso-buttons";
import type { Route } from "./+types/home";

export function meta(_args: Route.MetaArgs) {
  return [{ title: "react-fastify-skel" }, { name: "description", content: "It works!" }];
}

export default function Home() {
  const { user, loading, logout } = useAuth();

  return (
    <main className="flex items-center justify-center min-h-screen">
      <div className="w-full max-w-sm space-y-6 px-4 text-center">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">It works!</h1>

        {loading ? (
          <p className="text-gray-500">Loading...</p>
        ) : user ? (
          <div className="space-y-4">
            <p className="text-gray-700 dark:text-gray-300">
              Signed in as <span className="font-medium">{user.email}</span>
            </p>
            <button
              type="button"
              onClick={logout}
              className="px-4 py-2 text-sm border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-800 transition-colors"
            >
              Sign out
            </button>
          </div>
        ) : (
          <div className="space-y-3">
            <GoogleSignInButton />
            <AppleSignInButton />
          </div>
        )}
      </div>
    </main>
  );
}
