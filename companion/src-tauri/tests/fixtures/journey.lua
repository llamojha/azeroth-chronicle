AzerothChronicleDB = {
  ["schemaVersion"] = 1,
  ["characters"] = {
    ["Player-fixture"] = {
      name = "Explorer", realm = "Fixture", race = "Undead", class = "Paladin", level = 8,
      events = {
        { id = "accepted", type = "quest_accepted", timestamp = 100, questId = 92516,
          title = "Hippogryph Harassment", description = "A captured description.\nSecond line.",
          objectivesText = "A captured objective.", zone = "Zephras Isle" },
        { id = "complete", type = "quest_completed", timestamp = 200, questId = 92516 },
        { id = "location", type = "location_changed", timestamp = 90, zone = "The Barrens" },
      },
    },
  },
}
