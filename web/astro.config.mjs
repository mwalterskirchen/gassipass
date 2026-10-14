// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  site: "https://gassipass.ch",
  // One HTML file per page, so that vercel.json can rewrite each invitation URL to invitation.html.
  build: { format: "file" },
  vite: { plugins: [tailwindcss()] },
});
