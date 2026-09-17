import SwiftUI

/// Settings for optional addons that extend the app with extra capabilities.
struct AddonsSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            // MARK: - Ad Blocker

            Section {
                Toggle("Enable Ad Blocker", isOn: self.$settings.adBlockEnabled)
                    .help("Blocks ad and tracking domains in all WebViews, and auto-skips YouTube in-video ads.")
            } header: {
                Text("Ad Blocker")
            } footer: {
                Text("Content-blocking rules block known ad-serving and tracking domains. YouTube video ads are intercepted at the API level before they load. Changes take effect after restarting KasetPlus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - SponsorBlock

            Section {
                Toggle("Enable SponsorBlock", isOn: self.$settings.sponsorBlockEnabled)
                    .help("Automatically skip sponsored segments and other non-content sections in YouTube videos.")

                if self.settings.sponsorBlockEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Skip these segment types:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        ForEach(SettingsManager.sponsorBlockCategoryOptions, id: \.id) { category in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(SponsorSegment.color(for: category.id))
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)

                                Toggle(category.label, isOn: Binding(
                                    get: { self.settings.sponsorBlockCategories.contains(category.id) },
                                    set: { enabled in
                                        if enabled {
                                            if !self.settings.sponsorBlockCategories.contains(category.id) {
                                                self.settings.sponsorBlockCategories.append(category.id)
                                            }
                                        } else {
                                            self.settings.sponsorBlockCategories.removeAll { $0 == category.id }
                                        }
                                    }
                                ))
                            }
                        }
                    }
                }
            } header: {
                Text("SponsorBlock")
            } footer: {
                Text("Powered by the SponsorBlock database. Segments are crowd-sourced — some videos may not have any. Settings take effect on the next video you watch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Return YouTube Dislikes

            Section {
                Toggle("Enable Return YouTube Dislikes", isOn: self.$settings.returnYouTubeDislikesEnabled)
                    .help("Show dislike counts on YouTube videos, powered by the Return YouTube Dislikes API.")
            } header: {
                Text("Return YouTube Dislikes")
            } footer: {
                Text("Shows the dislike count next to the dislike button in the YouTube player bar. Data is fetched from the community-driven RYD API. Takes effect on the next video you watch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - DeArrow

            Section {
                Toggle("Enable DeArrow", isOn: self.$settings.dearrowEnabled)
                    .help("Replace clickbait YouTube video titles with community-submitted accurate titles.")
            } header: {
                Text("DeArrow")
            } footer: {
                Text("Clickbait titles are replaced with accurate descriptions from the DeArrow community database. A toggle icon (↔) appears next to the title — click it to see the original. Powered by the same community as SponsorBlock. Takes effect on the next video you watch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Discord Rich Presence

            Section {
                Toggle("Enable Discord Rich Presence", isOn: self.$settings.discordRichPresenceEnabled)
                    .help("Show the track or video you are playing on your Discord profile.")

                if self.settings.discordRichPresenceEnabled {
                    LabeledContent(
                        DiscordPresenceActivity.hasDefaultApplicationID
                            ? String(localized: "Application ID (optional)")
                            : String(localized: "Application ID")
                    ) {
                        TextField(
                            "",
                            text: self.$settings.discordApplicationID,
                            prompt: Text(
                                DiscordPresenceActivity.hasDefaultApplicationID
                                    ? String(localized: "Default")
                                    : String(localized: "Paste your Application ID")
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .font(.body.monospacedDigit())
                    }

                    HStack(spacing: 6) {
                        Image(systemName: self.discordStatusIcon)
                            .foregroundStyle(self.discordStatusColor)
                        Text(self.discordStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !DiscordPresenceActivity.hasDefaultApplicationID {
                        Link(
                            "Create an application on the Discord Developer Portal",
                            destination: URL(string: "https://discord.com/developers/applications")!
                        )
                        .font(.caption)
                    }
                }
            } header: {
                Text("Discord Rich Presence")
            } footer: {
                Text(DiscordPresenceActivity.hasDefaultApplicationID
                    ? String(localized: "Publishes what you are playing to the Discord app running on this Mac, so your profile reads \"Listening to KasetPlus\". Leave the Application ID blank to use KasetPlus's own; set one to show a name of your choosing instead. Nothing is sent anywhere else, and the presence clears when playback stops.")
                    : String(localized: "Publishes what you are playing to the Discord app running on this Mac. Discord shows the name and icon of the application whose ID you paste here, so create one named however you want your profile to read — no bot, no permissions and no sign-in needed, just the Application ID from its General Information page. Nothing is sent anywhere else, and the presence clears when playback stops."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Discord status

    private var discordStatusText: String {
        switch DiscordRichPresenceService.shared.status {
        case .disabled:
            String(localized: "Off")
        case .needsApplicationID:
            String(localized: "Paste the Application ID of a Discord application you created.")
        case .waitingForDiscord:
            String(localized: "Waiting for Discord to be running on this Mac.")
        case .connected:
            String(localized: "Connected to Discord.")
        case let .rejected(message):
            String(localized: "Discord refused the connection: \(message)")
        case let .failed(message):
            String(localized: "Could not reach Discord: \(message)")
        }
    }

    private var discordStatusIcon: String {
        switch DiscordRichPresenceService.shared.status {
        case .connected: "checkmark.circle.fill"
        case .rejected, .failed: "exclamationmark.triangle.fill"
        default: "clock"
        }
    }

    private var discordStatusColor: Color {
        switch DiscordRichPresenceService.shared.status {
        case .connected: .green
        case .rejected, .failed: .orange
        default: .secondary
        }
    }
}
