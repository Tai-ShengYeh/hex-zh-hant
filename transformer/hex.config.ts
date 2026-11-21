import { defineHexConfig } from "@hex/commands"
import { convertS2TW, convertS2TWP } from "./hex-s2tw"

// Hex runs this file itself and reloads it when you save. It is plain
// TypeScript or JavaScript with no npm packages: transformations return text.
// Transformations appear as optional final steps in every dictation mode.
export default defineHexConfig({
  transformations: {
    "trim-whitespace": {
      name: "Trim whitespace",
      description: "Remove leading and trailing whitespace",
      transform: (text) => text.trim(),
    },
    "s2tw": {
      name: "簡轉繁（台灣）",
      description: "用 OpenCC s2tw 字典把簡體轉成繁體",
      transform: (text) => convertS2TW(text),
    },
    "s2twp": {
      name: "簡轉繁（台灣用語）",
      description: "用 OpenCC s2twp 字典把簡體轉成繁體，並替換成台灣用語",
      transform: (text) => convertS2TWP(text),
    },
  },
})
