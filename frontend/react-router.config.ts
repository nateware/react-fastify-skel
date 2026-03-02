import type { Config } from "@react-router/dev/config";

export default {
  // SPA mode: static build, no server runtime. Deploy to CDN/bucket.
  // Set to `true` for SSR mode (requires Node.js server, e.g. Cloud Run).
  ssr: false,
} satisfies Config;
