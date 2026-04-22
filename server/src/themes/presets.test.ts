import { describe, expect, it } from "vitest";
import { getPreset, listPresetIds, PRESET_THEMES } from "./presets.js";

describe("themes/presets", () => {
  it("listPresetIds returns exactly the 6 hackathon presets", () => {
    const ids = listPresetIds();
    expect(ids).toEqual([
      "default",
      "cyberpunk",
      "terminal",
      "paper",
      "bento-orange",
      "pastel",
    ]);
  });

  it("getPreset returns a fully-formed theme for each preset id", () => {
    for (const id of listPresetIds()) {
      const t = getPreset(id);
      expect(t).toBeDefined();
      expect(t!.id).toBe(id);
      expect(t!.name.length).toBeGreaterThan(0);
      // Colors must all be present.
      expect(Object.keys(t!.colors).sort()).toEqual(
        [
          "accent",
          "background",
          "border",
          "negative",
          "positive",
          "primary",
          "secondary",
          "surface",
        ].sort(),
      );
      expect(["rounded", "serif", "monospaced", "default"]).toContain(
        t!.font.family,
      );
      expect([
        "regular",
        "medium",
        "semibold",
        "bold",
        "heavy",
      ]).toContain(t!.font.weightPrimary);
      expect(t!.chart.stroke).toMatch(/^#/);
    }
  });

  it("getPreset returns undefined for unknown ids", () => {
    expect(getPreset("not-a-theme")).toBeUndefined();
    expect(getPreset("")).toBeUndefined();
  });

  it("PRESET_THEMES length matches listPresetIds", () => {
    expect(PRESET_THEMES).toHaveLength(listPresetIds().length);
  });
});
