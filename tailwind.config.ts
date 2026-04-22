import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        base: "#080D1A",
        surface: "#0F1629",
        card: "#141E35",
        "card-hover": "#1A2640",
        border: "#1E2D47",
        "border-bright": "#2A3F5F",
        txt: "#E8EDF5",
        muted: "#8A9BB5",
        subtle: "#4A5B75",
        accent: "#22D3EE",
        "accent-dim": "#0E7490",
        violet: "#818CF8",
        emerald: "#34D399",
        amber: "#FBBF24",
        rose: "#FB7185",
        orange: "#FB923C",
        pink: "#F472B6",
      },
      fontFamily: {
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "monospace"],
      },
    },
  },
  plugins: [],
};

export default config;
