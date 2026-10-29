import security from "eslint-plugin-security";

export default [
  {
    ignores: ["**/node_modules/**", "**/dist/**", "**/coverage/**"],
  },
  security.configs.recommended,
  {
    rules: {
      "security/detect-bidi-characters": "error",
      "security/detect-buffer-noassert": "error",
      "security/detect-child-process": "error",
      "security/detect-disable-mustache-escape": "error",
      "security/detect-eval-with-expression": "error",
      "security/detect-invisible-characters": "error",
      "security/detect-new-buffer": "error",
      "security/detect-non-literal-require": "error",
    },
  },
];
