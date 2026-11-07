import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    // + test logic phân quyền của edge function (TS thuần, không gọi Deno API).
    include: ["src/**/*.test.{js,jsx}", "supabase/functions/**/*.test.ts"],
  },
});
