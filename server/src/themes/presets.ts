export type Theme = {
  id: string;
  name: string;
  // All colors are hex with optional alpha. Consumed by both the iOS app
  // and the SwiftUI widget extension.
  colors: {
    background: string;    // widget background
    surface: string;       // card surface within widget
    primary: string;       // main text / numbers
    secondary: string;     // labels, captions
    accent: string;        // trend arrows, active state
    positive: string;      // green / success
    negative: string;      // red / failure
    border: string;
  };
  font: {
    // Names of system fonts iOS can resolve, or SF Pro fallbacks.
    family: "rounded" | "serif" | "monospaced" | "default";
    weightPrimary: "regular" | "medium" | "semibold" | "bold" | "heavy";
  };
  chart: {
    stroke: string;
    fillStart: string;
    fillEnd: string;
  };
};

export const PRESET_THEMES: Theme[] = [
  {
    id: "default",
    name: "Default",
    colors: {
      background: "#0B0B0F",
      surface: "#17171D",
      primary: "#F5F5F7",
      secondary: "#9A9AA5",
      accent: "#FF7A1A",
      positive: "#27C26A",
      negative: "#FF5252",
      border: "#2A2A33",
    },
    font: { family: "default", weightPrimary: "bold" },
    chart: {
      stroke: "#FF7A1A",
      fillStart: "#FF7A1A55",
      fillEnd: "#FF7A1A00",
    },
  },
  {
    id: "cyberpunk",
    name: "Cyberpunk",
    colors: {
      background: "#0A0214",
      surface: "#120825",
      primary: "#00F0FF",
      secondary: "#B383FF",
      accent: "#FF006E",
      positive: "#39FF14",
      negative: "#FF2A6D",
      border: "#3A1F5C",
    },
    font: { family: "monospaced", weightPrimary: "heavy" },
    chart: {
      stroke: "#FF006E",
      fillStart: "#FF006E66",
      fillEnd: "#00F0FF00",
    },
  },
  {
    id: "terminal",
    name: "Terminal",
    colors: {
      background: "#000000",
      surface: "#0A0A0A",
      primary: "#00FF41",
      secondary: "#2EC764",
      accent: "#FFFFFF",
      positive: "#00FF41",
      negative: "#FF3333",
      border: "#113311",
    },
    font: { family: "monospaced", weightPrimary: "bold" },
    chart: {
      stroke: "#00FF41",
      fillStart: "#00FF4155",
      fillEnd: "#00FF4100",
    },
  },
  {
    id: "paper",
    name: "Paper",
    colors: {
      background: "#F7F3EA",
      surface: "#FFFFFF",
      primary: "#1A1A1A",
      secondary: "#6B6658",
      accent: "#CC4A1A",
      positive: "#2E7D4F",
      negative: "#C13515",
      border: "#E5DFD1",
    },
    font: { family: "serif", weightPrimary: "semibold" },
    chart: {
      stroke: "#CC4A1A",
      fillStart: "#CC4A1A33",
      fillEnd: "#CC4A1A00",
    },
  },
  {
    id: "bento-orange",
    name: "Bento Orange",
    colors: {
      background: "#1A0F05",
      surface: "#2A1A0B",
      primary: "#FFE4B5",
      secondary: "#D4A373",
      accent: "#FF8C42",
      positive: "#A3D977",
      negative: "#E63946",
      border: "#4A2E12",
    },
    font: { family: "rounded", weightPrimary: "bold" },
    chart: {
      stroke: "#FF8C42",
      fillStart: "#FF8C4266",
      fillEnd: "#FF8C4200",
    },
  },
  {
    id: "pastel",
    name: "Pastel",
    colors: {
      background: "#FDF6F0",
      surface: "#FFFFFF",
      primary: "#3D3047",
      secondary: "#9B86A3",
      accent: "#E8A5C4",
      positive: "#A8D5BA",
      negative: "#F5A5A5",
      border: "#F0E0E8",
    },
    font: { family: "rounded", weightPrimary: "semibold" },
    chart: {
      stroke: "#E8A5C4",
      fillStart: "#E8A5C466",
      fillEnd: "#E8A5C400",
    },
  },
];

export function getPreset(id: string): Theme | undefined {
  return PRESET_THEMES.find((t) => t.id === id);
}

export function listPresetIds(): string[] {
  return PRESET_THEMES.map((t) => t.id);
}
