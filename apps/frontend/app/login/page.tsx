"use client";

import { useState } from "react";
import { useAuth } from "../contexts/AuthContext";
import Link from "next/link";

export default function Login() {
    const { login } = useAuth();
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [error, setError] = useState("");
    const [isLoading, setIsLoading] = useState(false);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError("");
        setIsLoading(true);

        try {
            const res = await fetch("http://localhost:8000/api/login", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    Accept: "application/json",
                },
                body: JSON.stringify({ email, password }),
            });

            const data = await res.json();

            if (res.ok) {
                await login(data.token);
            } else {
                // Handle Validation Errors from Laravel
                const validationError = data.errors?.email?.[0] || data.errors?.password?.[0];
                setError(data.message || validationError || "Login failed");
            }
        } catch (err) {
            setError("An unexpected error occurred. Please try again.");
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="max-w-md mx-auto mt-20 p-6 bg-white dark:bg-gray-800 rounded-lg shadow-md border border-gray-200 dark:border-gray-700">
            <h2 className="text-3xl font-bold text-center mb-6">Log in</h2>
            {error && (
                <div className="mb-4 p-3 bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400 border border-red-200 dark:border-red-800 rounded-md text-sm">
                    {error}
                </div>
            )}
            <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                    <label className="block text-sm font-medium mb-1" htmlFor="email">
                        Email
                    </label>
                    <input
                        id="email"
                        type="email"
                        required
                        className="w-full px-4 py-2 border rounded-md dark:bg-gray-700 dark:border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium mb-1" htmlFor="password">
                        Password
                    </label>
                    <input
                        id="password"
                        type="password"
                        required
                        className="w-full px-4 py-2 border rounded-md dark:bg-gray-700 dark:border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                    />
                </div>
                <button
                    type="submit"
                    disabled={isLoading}
                    className="w-full py-2 px-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-md transition-colors disabled:bg-blue-400"
                >
                    {isLoading ? "Logging in..." : "Login"}
                </button>
            </form>
            <div className="text-center mt-6 text-sm">
                Don&apos;t have an account?{" "}
                <Link href="/register" className="text-blue-600 dark:text-blue-400 hover:underline">
                    Register here
                </Link>
            </div>
        </div>
    );
}
