"use client";

import Link from "next/link";
import {useAuth} from "../contexts/AuthContext";

export default function Navbar() {
    const {user, logout, loading} = useAuth();

    return (
        <nav className="bg-white dark:bg-gray-800 shadow sticky top-0 z-50">
            <div className="container mx-auto px-4 h-16 flex items-center justify-between">
                <Link href="/" className="text-2xl font-bold text-blue-600 dark:text-blue-400">
                    MyApp
                </Link>
                <div className="flex items-center gap-4">
                    {!loading && (
                        <>
                            {user ? (
                                <>
                                    <span className="text-sm font-medium text-gray-700 dark:text-gray-200">
                                        {user.name}
                                    </span>
                                    <button
                                        onClick={logout}
                                        className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-md transition-colors"
                                    >
                                        Logout
                                    </button>
                                </>
                            ) : (
                                <>
                                    <Link
                                        href="/login"
                                        className="font-medium text-gray-700 dark:text-gray-200 hover:text-blue-600"
                                    >
                                        Login
                                    </Link>
                                    <Link
                                        href="/register"
                                        className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-md transition-colors"
                                    >
                                        Register
                                    </Link>
                                </>
                            )}
                        </>
                    )}
                </div>
            </div>
        </nav>
    );
}
