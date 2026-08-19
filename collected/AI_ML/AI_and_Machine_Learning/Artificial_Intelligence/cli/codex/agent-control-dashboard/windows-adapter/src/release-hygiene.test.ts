import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

describe("release hygiene", () => {
  it("ignores local remote-chat attachments", () => {
    const repositoryRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
    const gitignore = readFileSync(join(repositoryRoot, ".gitignore"), "utf8");
    expect(gitignore.split(/\r?\n/)).toContain(".codex-remote-attachments/");
  });
});
