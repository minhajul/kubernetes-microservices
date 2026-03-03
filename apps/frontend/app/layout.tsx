import type {Metadata} from "next";
import {Providers} from "./providers";
import Navbar from "./components/Navbar";
import "./globals.css";

export const metadata: Metadata = {
    title: "MyApp - Home page",
    description: "NextJS React application dashboard with authentication",
};

export default function RootLayout({children,}: Readonly<{ children: React.ReactNode; }>) {
    return (
        <html lang="en">
        <body className="antialiased bg-gray-50 text-gray-900 dark:bg-gray-900 dark:text-gray-100 min-h-screen flex flex-col">
        <Providers>
            <Navbar/>
            <main className="grow container mx-auto px-4 py-8">
                {children}
            </main>
        </Providers>
        </body>
        </html>
    );
}
