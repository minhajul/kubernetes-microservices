"use client";

import React, {createContext, useContext, useState, useEffect} from "react";
import {useRouter} from "next/navigation";

interface User {
    id: number;
    name: string;
    email: string;
}

interface AuthContextType {
    user: User | null;
    token: string | null;
    login: (token: string) => Promise<void>;
    logout: () => Promise<void>;
    loading: boolean;
}

const AuthContext = createContext<AuthContextType>({
    user: null,
    token: null,
    login: async () => {
    },
    logout: async () => {
    },
    loading: true,
});

export const AuthProvider = ({children}: { children: React.ReactNode }) => {
    const [user, setUser] = useState<User | null>(null);
    const [token, setToken] = useState<string | null>(null);
    const [loading, setLoading] = useState(true);
    const router = useRouter();

    useEffect(() => {
        const storedToken = localStorage.getItem("auth_token");
        if (storedToken) {
            setToken(storedToken);
            fetchUser(storedToken);
        } else {
            setLoading(false);
        }
    }, []);

    const fetchUser = async (authToken: string) => {
        try {
            const res = await fetch("http://localhost:8000/api/user", {
                headers: {
                    Authorization: `Bearer ${authToken}`,
                    Accept: "application/json",
                },
            });
            if (res.ok) {
                const userData = await res.json();
                setUser(userData);
            } else {
                localStorage.removeItem("auth_token");
                setToken(null);
                setUser(null);
            }
        } catch (e) {
            console.error(e);
            localStorage.removeItem("auth_token");
            setToken(null);
            setUser(null);
        } finally {
            setLoading(false);
        }
    };

    const login = async (newToken: string) => {
        localStorage.setItem("auth_token", newToken);
        setToken(newToken);
        await fetchUser(newToken);
        router.push("/");
    };

    const logout = async () => {
        if (token) {
            try {
                await fetch("http://localhost:8000/api/logout", {
                    method: "POST",
                    headers: {
                        Authorization: `Bearer ${token}`,
                        Accept: "application/json",
                    },
                });
            } catch (e) {
                console.error(e);
            }
        }
        localStorage.removeItem("auth_token");
        setToken(null);
        setUser(null);
        router.push("/login"); // Fixed router call
    };

    return (
        <AuthContext.Provider value={{user, token, login, logout, loading}}>
            {children}
        </AuthContext.Provider>
    );
};

export const useAuth = () => useContext(AuthContext);
