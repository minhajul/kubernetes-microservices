import type {NextConfig} from "next";

const nextConfig: NextConfig = {
    // Emits .next/standalone (server.js + traced production deps) for the Docker image.
    output: "standalone",
    logging: {
        browserToTerminal: true
    }
};

export default nextConfig;
