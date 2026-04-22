import fs from "fs";
import path from "path";
import os from "os";
import type { AppConfig, SafeConfig } from "@/types";

const CONFIG_DIR = path.join(os.homedir(), ".config", "jyra");
const CONFIG_FILE = path.join(CONFIG_DIR, "config.json");

function ensureDir() {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
}

export function readConfig(): AppConfig | null {
  try {
    if (!fs.existsSync(CONFIG_FILE)) return null;
    const raw = fs.readFileSync(CONFIG_FILE, "utf-8");
    return JSON.parse(raw) as AppConfig;
  } catch {
    return null;
  }
}

export function writeConfig(data: Omit<AppConfig, "createdAt" | "updatedAt">): AppConfig {
  ensureDir();
  const existing = readConfig();
  const config: AppConfig = {
    ...data,
    createdAt: existing?.createdAt ?? new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), { mode: 0o600 });
  return config;
}

export function clearConfig() {
  if (fs.existsSync(CONFIG_FILE)) fs.unlinkSync(CONFIG_FILE);
}

export function toSafeConfig(c: AppConfig): SafeConfig {
  return {
    jiraUrl: c.jiraUrl,
    email: c.email,
    hasApiKey: Boolean(c.apiKey),
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
  };
}
