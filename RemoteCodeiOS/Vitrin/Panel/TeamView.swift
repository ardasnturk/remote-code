// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/TeamView.swift).
import SwiftUI

/// The team's App Store Connect, beyond one app: people, devices, signing, and every asc command.
enum TeamPage: String, CaseIterable, Identifiable {
    case users, devices, certificates, profiles, bundleIDs, reports, automation, ads, account
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .users: return "person.2.fill"
        case .devices: return "iphone.gen3"
        case .certificates: return "checkmark.seal.fill"
        case .profiles: return "doc.badge.gearshape.fill"
        case .bundleIDs: return "app.badge.fill"
        case .reports: return "chart.bar.doc.horizontal.fill"
        case .automation: return "gearshape.2.fill"
        case .ads: return "megaphone.fill"
        case .account: return "building.2.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .users: return BadgeColors.deep
        case .devices: return BadgeColors.cool
        case .certificates: return BadgeColors.fresh
        case .profiles: return BadgeColors.warm
        case .bundleIDs: return BadgeColors.magic
        case .reports: return BadgeColors.fresh
        case .automation: return BadgeColors.gray
        case .ads: return BadgeColors.brand
        case .account: return BadgeColors.warm
        }
    }
    var titleKey: String { "team.\(rawValue)" }
    var groups: [String] {
        switch self {
        case .users: return AscAreas.users
        case .devices: return AscAreas.devices
        case .certificates: return ["certificates", "signing", "notarization"]
        case .profiles: return ["profiles"]
        case .bundleIDs: return ["bundle-ids", "merchant-ids", "pass-type-ids"]
        case .reports: return AscAreas.reports
        case .automation: return AscAreas.automation
        case .ads: return AscAreas.ads
        case .account: return AscAreas.account
        }
    }
}

struct TeamView: View {
    @Environment(VitrinPanelModel.self) private var model
    var page: TeamPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaneHeader(symbol: page.symbol, colors: page.colors, title: Text(L.t(page.titleKey)), subtitle: Text(L.t(page.titleKey + ".subtitle")))
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
                Divider().opacity(0.5)
                if !model.connection.isConnected {
                    ConnectHint().padding(16)
                } else {
                    content.frame(maxWidth: .infinity, alignment: .topLeading)
                        .environment(\.ascShelf, AscShelfContext(title: L.t("asc.shelf.title"), groups: page.groups))
                }
            }
        }
        .brandWindowBackground()
        .navigationTitle(L.t(page.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .id(page)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .reports:
            TabPage {
                AscSection(title: L.t("team.reports.regions"), args: ["finance", "regions"])
            }
        case .automation:
            TabPage {
                AscSection(title: L.t("team.auto.products"), args: ["xcode-cloud", "products", "list"], empty: L.t("team.auto.noProducts"))
            }
        case .ads:
            TabPage {
                AppleAdsPage()
            }
        case .account:
            TabPage {
                AscSection(title: L.t("team.account.status"), args: ["account", "status"])
                AscSection(title: L.t("team.account.system"), args: ["system-status"])
            }
        case .users:
            TabPage {
                AscLoad(args: ["users", "list", "--paginate"]) { doc, reload in
                    let users = AscActions.options(doc) { "\(JSONAPI.text($0, "firstName")) \(JSONAPI.text($0, "lastName")) · \(JSONAPI.text($0, "username"))" }
                    ActionBar(title: L.t("team.actions")) {
                        AscActionButton(action: AscActions.inviteUser(), done: reload, prominent: true)
                        if !users.isEmpty { AscActionButton(action: AscActions.removeUser(users: users), done: reload) }
                    }
                    ResourceTable(items: JSONAPI.items(doc), columns: [
                        (L.t("asc.field.firstName"), "firstName", .text), (L.t("asc.field.lastName"), "lastName", .text),
                        (L.t("asc.field.email"), "username", .mono), (L.t("act.roles"), "roles", .text), (L.t("act.allApps"), "allAppsVisible", .bool),
                    ], empty: L.t("asc.empty"))
                }
                AscSection(title: L.t("team.users.invites"), args: ["users", "invites", "list"], empty: L.t("team.users.noInvites"))
                AscSection(title: L.t("team.users.sandbox"), args: ["sandbox", "list"], empty: L.t("team.users.noSandbox"))
            }
        case .devices:
            TabPage {
                AscLoad(args: ["devices", "list", "--paginate"]) { doc, reload in
                    ActionBar(title: L.t("team.actions")) {
                        AscActionButton(action: AscActions.registerDevice(), done: reload, prominent: true)
                    }
                    ResourceTable(items: JSONAPI.items(doc), columns: [
                        (L.t("asc.field.name"), "name", .text), ("UDID", "udid", .mono), (L.t("asc.field.platform"), "platform", .mono),
                        (L.t("team.model"), "model", .text), (L.t("asc.field.state"), "status", .state),
                    ], empty: L.t("asc.empty"))
                }
            }
        case .certificates:
            TabPage {
                AscLoad(args: ["certificates", "list", "--paginate"]) { doc, reload in
                    let certs = AscActions.options(doc) { "\(JSONAPI.text($0, "displayName")) · \(JSONAPI.text($0, "certificateType"))" }
                    ActionBar(title: L.t("team.actions")) {
                        if !certs.isEmpty { AscActionButton(action: AscActions.revokeCertificate(certs: certs), done: reload) }
                    }
                    ResourceTable(items: JSONAPI.items(doc), columns: [
                        (L.t("asc.field.name"), "displayName", .text), (L.t("team.type"), "certificateType", .mono),
                        (L.t("team.expires"), "expirationDate", .date), (L.t("asc.field.platform"), "platform", .mono),
                    ], empty: L.t("asc.empty"))
                }
            }
        case .profiles:
            TabPage {
                AscLoad(args: ["profiles", "list", "--paginate"]) { doc, reload in
                    let profiles = AscActions.options(doc) { "\(JSONAPI.text($0, "name")) · \(JSONAPI.text($0, "profileType"))" }
                    ActionBar(title: L.t("team.actions")) {
                        if !profiles.isEmpty { AscActionButton(action: AscActions.deleteProfile(profiles: profiles), done: reload) }
                    }
                    ResourceTable(items: JSONAPI.items(doc), columns: [
                        (L.t("asc.field.name"), "name", .text), (L.t("team.type"), "profileType", .mono),
                        (L.t("asc.field.state"), "profileState", .state), (L.t("team.expires"), "expirationDate", .date),
                    ], empty: L.t("asc.empty"))
                }
            }
        case .bundleIDs:
            TabPage {
                AscLoad(args: ["bundle-ids", "list", "--paginate"]) { doc, reload in
                    ActionBar(title: L.t("team.actions")) {
                        AscActionButton(action: AscActions.createBundleID(), done: reload, prominent: true)
                    }
                    ResourceTable(items: JSONAPI.items(doc), columns: [
                        (L.t("asc.field.name"), "name", .text), ("Bundle ID", "identifier", .mono),
                        (L.t("asc.field.platform"), "platform", .mono), ("Seed", "seedId", .mono),
                    ], empty: L.t("asc.empty"))
                }
            }
        }
    }
}
