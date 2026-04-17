import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        fortinet: {
          red: "#EF3B2D",
          dark: "#1A1A2E",
          gray: "#2D2D44",
        },
      },
    },
  },
  plugins: [],
};

export default config;
