#include "config/config.hpp"
#include <catch2/catch_test_macros.hpp>
#include <QTemporaryDir>
#include <filesystem>

namespace Omnicast {
std::filesystem::path configDir() { return {}; }
} // namespace Omnicast

TEST_CASE("retains a standalone hotkey exclusion") {
  QTemporaryDir directory;
  REQUIRE(directory.isValid());

  std::filesystem::path const configPath =
      std::filesystem::path{directory.path().toStdString()} / "settings.json";
  EntrypointId const moonlight{"applications", "com.moonlight-stream.Moonlight"};

  {
    config::Manager manager{configPath};
    REQUIRE(manager.mergeEntrypointWithUser(moonlight, {.hotkeyExcluded = true}));
  }

  config::Manager reloaded{configPath};
  auto provider = reloaded.value().providers.find(moonlight.provider);
  REQUIRE(provider != reloaded.value().providers.end());

  auto entrypoint = provider->second.entrypoints.find(moonlight.entrypoint);
  REQUIRE(entrypoint != provider->second.entrypoints.end());
  REQUIRE(entrypoint->second.hotkeyExcluded.value_or(false));
}
