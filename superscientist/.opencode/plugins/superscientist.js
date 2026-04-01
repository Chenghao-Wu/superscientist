// OpenCode plugin entry point for superscientist
// ESM module — no npm dependencies

import { readFileSync } from "fs";
import { join, resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PLUGIN_ROOT = resolve(__dirname, "../..");

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { meta: {}, body: content };
  const meta = {};
  for (const line of match[1].split("\n")) {
    const idx = line.indexOf(":");
    if (idx > 0) {
      meta[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
    }
  }
  return { meta, body: match[2] };
}

export async function SuperscientistPlugin(api) {
  const skillsDir = join(PLUGIN_ROOT, "skills");
  const skillPath = join(skillsDir, "using-superscientist", "SKILL.md");

  let bootstrapContent = "";
  try {
    bootstrapContent = readFileSync(skillPath, "utf-8");
  } catch {
    bootstrapContent = "Error: could not read using-superscientist skill.";
  }

  api.hook("config", () => ({
    skills: skillsDir,
  }));

  api.hook("experimental.chat.system.transform", (system) => {
    const injection = `<EXTREMELY_IMPORTANT>\nYou have superscientist.\n\n${bootstrapContent}\n</EXTREMELY_IMPORTANT>`;
    return system + "\n\n" + injection;
  });
}
