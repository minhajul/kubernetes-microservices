"use client";

import { useAuth } from "../contexts/AuthContext";
import Link from "next/link";

export default function Home() {
  const { user, loading } = useAuth();

  if (loading) {
    return <div className="flex justify-center mt-20">Loading...</div>;
  }

  return (
    <div className="max-w-4xl mx-auto space-y-8 mt-10">
      <div className="text-center">
        <h1 className="text-4xl font-extrabold tracking-tight lg:text-5xl mb-4 text-blue-600 dark:text-blue-400">
          Welcome to MyApp
        </h1>
        {user ? (
          <p className="text-xl text-gray-700 dark:text-gray-300">
            Hello, <strong>{user.name}</strong>! You are successfully logged in.
          </p>
        ) : (
          <div className="space-y-4">
            <p className="text-xl text-gray-500 dark:text-gray-400">
              Please log in or register to get started.
            </p>
            <div className="flex justify-center gap-4 mt-6">
              <Link
                href="/login"
                className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors"
              >
                Login
              </Link>
              <Link
                href="/register"
                className="px-6 py-3 bg-gray-200 hover:bg-gray-300 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-900 dark:text-white font-medium rounded-lg transition-colors"
              >
                Create Account
              </Link>
            </div>
          </div>
        )}
      </div>

      {user && (
        <div className="bg-white dark:bg-gray-800 shadow rounded-lg p-6 mt-8 border border-gray-200 dark:border-gray-700">
          <h2 className="text-2xl font-bold mb-4">Your Dashboard</h2>
          <div className="space-y-2">
            <p className="text-gray-600 dark:text-gray-300">
              <strong>Account ID:</strong> {user.id}
            </p>
            <p className="text-gray-600 dark:text-gray-300">
              <strong>Display Name:</strong> {user.name}
            </p>
            <p className="text-gray-600 dark:text-gray-300">
              <strong>Email Address:</strong> {user.email}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
