import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Jyra",
  description: "Jira team metrics dashboard",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full">
      <body className="h-full bg-base text-txt antialiased">{children}</body>
    </html>
  );
}
