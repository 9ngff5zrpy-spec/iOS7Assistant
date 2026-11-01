import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AssistantModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isBusy else { return .terminateNow }
        if model.isFlashing {
            let alert = NSAlert(); alert.messageText = model.t("busyQuit"); alert.informativeText = model.t("restoreConfirmBody")
            alert.addButton(withTitle: model.t("continue")); alert.addButton(withTitle: model.t("quit"))
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        model.stopAllProcesses(); return .terminateNow
    }
}

@main struct AssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AssistantModel()
    @State private var showCredits = false
    var body: some Scene {
        Window("iOS 7 Assistant", id: "main") {
            AssistantView(model: model, showCredits: $showCredits)
                .onAppear { delegate.model = model }
                .environment(\.locale, Locale(identifier: model.language))
        }
        .defaultSize(width: 820, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) { Button(model.t("credits")) { showCredits = true } }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .saveItem) { Button(model.t("exportLog")) { model.saveLog() }.keyboardShortcut("s", modifiers: [.command, .shift]) }
            CommandGroup(replacing: .help) { Button(model.t("credits")) { showCredits = true } }
        }
    }
}

struct AssistantView: View {
    @Bindable var model: AssistantModel
    @Binding var showCredits: Bool
    @State private var confirmErase = false
    @State private var logExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            HStack {
                Picker(model.t("mode"), selection: $model.mode) {
                    Text(model.t("bootMode")).tag(WorkflowMode.boot)
                    Text(model.t("restoreMode")).tag(WorkflowMode.restore)
                    Text(model.t("extrasMode")).tag(WorkflowMode.extras)
                }
                .pickerStyle(.segmented).disabled(model.step != .setup || model.isBusy)
                .accessibilityLabel(model.t("mode"))
            }
            if model.isDemo { Label(model.t("demo"), systemImage: "play.rectangle").font(.callout).foregroundStyle(.orange) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.t(model.step == .done && !model.restoreCompleted && !model.extrasVerified ? "activationAndExtrasTitle" : model.step.titleKey)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(model.t("workflowOrder")).font(.callout).foregroundStyle(.secondary)
                    if model.activationConfirmed { Label(model.t("activated"), systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    stepContent
                    if model.isBusy {
                        HStack(spacing: 10) {
                            if let value = model.progress { ProgressView(value: value).frame(maxWidth: 200) } else { ProgressView().controlSize(.small) }
                            Text(model.t(model.statusKey)).font(.callout)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if model.reconnectNotice && model.isFlashing { Label(model.t("reconnectDuringRestore"), systemImage: "cable.connector").padding(12).background(.orange.opacity(0.10), in: .rect(cornerRadius: 8)) }
                    if let error = model.errorKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(model.t(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            if !model.errorDetail.isEmpty { DisclosureGroup(model.t("logs")) { Text(model.errorDetail).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                        }.padding(12).background(.red.opacity(0.06), in: .rect(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
            if model.step == .setup {
                Button(model.t("begin")) { model.begin() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.isBusy || (!model.isDemo && model.profile == nil))
            }
            Text(model.t("limitations")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(model.t("logs"), isExpanded: $logExpanded) {
                ScrollView { Text(model.log.isEmpty ? "—" : model.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.frame(height: 130).background(Color(nsColor: .textBackgroundColor))
            }
            footer
        }
        .padding(22)
        .frame(minWidth: 700, minHeight: 650)
        .confirmationDialog(model.t("restoreConfirmTitle"), isPresented: $confirmErase, titleVisibility: .visible) {
            Button(model.t("eraseInstall"), role: .destructive) { model.startRestore() }
            Button(model.t("cancel"), role: .cancel) { }
        } message: { Text(model.t("restoreConfirmBody")) }
        .sheet(isPresented: $showCredits) { CreditsView(model: model) }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "iphone").font(.system(size: 30)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("iOS 7 Assistant").font(.title3.bold())
                Text(model.t("appSubtitle")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(model.t("language"), selection: $model.language) {
                Text("Español").tag("es"); Text("English").tag("en")
            }.frame(width: 175)
        }
    }
    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .setup:
            if model.mode == .extras {
                Text(model.t("extrasSetup"))
                Button(model.t("importProfile")) { model.importProfile() }.disabled(model.isBusy)
            } else {
            Text(model.t("setupBody"))
            firmwareRow("firmware7", url: model.ios7) { model.chooseFirmware(isSeven: true) }
            firmwareRow("firmware12", url: model.ios12) { model.chooseFirmware(isSeven: false) }
            HStack {
                Button(model.t("prepare")) { model.prepareFiles() }.disabled(model.isBusy || (!model.isDemo && (model.ios7 == nil || model.ios12 == nil)))
                Button(model.t("importProfile")) { model.importProfile() }.disabled(model.isBusy)
            }
            }
            if model.profileValid || model.profile != nil {
                Label(model.t(model.profileValid ? "profileReady" : "profileLocation"), systemImage: "folder.fill")
                    .foregroundStyle(model.profileValid ? Color.green : Color.secondary)
                if let profile = model.profile { Text(profile.lastPathComponent).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Text(model.t("prepareHint")).font(.callout).foregroundStyle(.secondary)
            Text(model.t("downloadHelp")).font(.callout).foregroundStyle(.secondary)
            Text(model.t(model.mode == .extras ? "extrasPreparationHint" : (model.mode == .restore ? "restoreExtras" : "bootExtras"))).font(.callout).foregroundStyle(.secondary)
        case .dfu:
            cableLabel("USB-A + adaptador USB-C", "USB-A + USB-C adapter")
            Text(model.t("dfuBody")); Text(model.t("dfuTiming")).fontWeight(.medium)
            if model.timerRemaining > 0 {
                HStack(spacing: 14) {
                    Text("\(model.timerRemaining > 10 ? model.timerRemaining - 10 : model.timerRemaining) s").font(.title.monospacedDigit()).frame(width: 74)
                    Text(model.t(model.timerRemaining > 10 ? "holdBoth" : "holdHome")).fontWeight(.semibold)
                    Button(model.t("cancel")) { model.timerTask?.cancel(); model.timerRemaining = 0 }
                }
            } else { Button(model.t("startTimer")) { model.startTimer() }.disabled(model.isBusy) }
            Text(model.t("oneDevice")).font(.callout).foregroundStyle(.secondary)
            Button(model.t("checkDFU")) { model.checkDFU() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        case .cable:
            cableLabel("Lightning → USB-C directo", "Lightning → direct USB-C")
            Text(model.t("cableBody"))
            identityLabel
            Button(model.t("checkCable")) { model.cableSwitched() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        case .ibss:
            cableLabel("Reconexión manual · USB-C", "Manual reconnection · USB-C")
            Text(model.t("ibssBody")); Text(model.t("waitingIBSS")).font(.callout).foregroundStyle(.secondary)
            Button(model.t("checkReconnect")) { model.afterIBSS() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        case .ibec:
            cableLabel("Reconexión manual · USB-C", "Manual reconnection · USB-C")
            Text(model.t("ibecBody")); Text(model.t("waitingIBEC")).font(.callout).foregroundStyle(.secondary)
            Button(model.t("checkReconnect")) { model.afterIBEC() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        case .ready:
            identityLabel
            if model.mode == .restore {
                Text(model.t("restoreReady"))
                Toggle(model.t("eraseConsent"), isOn: $model.eraseConsent)
                Button(model.t("eraseInstall"), role: .destructive) { confirmErase = true }.buttonStyle(.borderedProminent).tint(.red).disabled(model.isBusy || !model.eraseConsent)
            } else if model.mode == .extras {
                Text(model.t("maintenanceReady"))
                Button(model.t("startMaintenance")) { model.startMaintenance() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            } else {
                Text(model.t("bootReady"))
                Button(model.t("bootMode")) { model.startBoot() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            }
        case .restore: Text(model.t("installingBody"))
        case .boot: Text(model.t("bootingBody"))
        case .maintenanceConnect:
            Text(model.t("maintenanceConnectBody"))
            Button(model.t("connectMaintenance")) { model.connectMaintenance() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        case .extrasReady:
            Label(model.t("maintenanceStaged"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text(model.t("maintenanceFinalBoot"))
            Button(model.t("bootAfterMaintenance")) { model.bootAfterMaintenance() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        case .done:
            Label(model.t(model.restoreCompleted ? "restoreDone" : (model.bootVerified ? "bootDone" : "bootSent")), systemImage: model.restoreCompleted || model.bootVerified ? "checkmark.circle.fill" : "iphone")
                .foregroundStyle(model.restoreCompleted || model.bootVerified ? Color.green : Color.primary)
            if model.restoreCompleted {
                Button(model.t("firstBoot")) { model.firstBoot() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            } else {
                HStack {
                    Button(model.t("verifyBoot")) { model.verifyBoot() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                    if model.bootVerified { Button(model.t("activate")) { model.activate() }.disabled(model.isBusy || model.activationConfirmed) }
                }
                Text(model.t("activationHelp")).font(.callout).foregroundStyle(.secondary)
                if model.extrasVerified {
                    Label(model.t("extrasVerified"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(model.t("extrasManualTests"))
                    Toggle(model.t("testCydia"), isOn: $model.cydiaTest)
                    Toggle(model.t("testWiFi"), isOn: $model.wifiTest)
                    Toggle(model.t("testSleep"), isOn: $model.sleepTest)
                    if model.cydiaTest && model.wifiTest && model.sleepTest { Label(model.t("extrasAllDone"), systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                } else if model.bootVerified && model.extrasPendingBoot {
                    Button(model.t("finishExtras")) { model.finishExtras() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                } else if model.bootVerified && model.activationConfirmed {
                    Text(model.t("continueExtrasBody"))
                    Button(model.t("continueExtras")) { model.beginExtras() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                }
            }
        }
    }
    private func firmwareRow(_ key: String, url: URL?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t(key)).fontWeight(.medium)
                Text(url?.lastPathComponent ?? model.t("notSelected")).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(); Button(model.t("choose"), action: action).disabled(model.isBusy).accessibilityLabel(model.t("choose") + " " + model.t(key))
        }.padding(10).background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 7))
    }
    private func cableLabel(_ es: String, _ en: String) -> some View {
        Label(model.language == "es" ? es : en, systemImage: "cable.connector").font(.headline)
    }
    private var identityLabel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(model.t("readyDevice"), systemImage: "iphone.gen1")
            if let device = model.device { Text("\(device.product) · \(device.model) · ECID \(device.ecid)").font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
        }
    }
    private var footer: some View {
        HStack {
            Button(model.t("credits")) { showCredits = true }
            Spacer()
            Button(model.t("exportLog")) { model.saveLog() }
            if model.step != .setup { Button(model.t("newSession")) { model.reset() }.disabled(model.isBusy) }
        }.controlSize(.regular)
    }
}

struct CreditsView: View {
    let model: AssistantModel
    @Environment(\.dismiss) private var dismiss
    private let projects: [(String, String, String)] = [
        ("Legacy-iOS-Kit", "LukeZGD", "https://github.com/LukeZGD/Legacy-iOS-Kit"),
        ("5sd7", "AcePlayzGamesYT / StillDebugging", "https://github.com/AcePlayzGamesYT/5sd7"),
        ("surrealra1n", "pwnerblu", "https://github.com/pwnerblu/surrealra1n"),
        ("ipwnder_lite", "dora2ios · LukeZGD", "https://github.com/LukeZGD/ipwnder_lite"),
        ("idevicerestore · libirecovery · libimobiledevice", "libimobiledevice contributors", "https://github.com/libimobiledevice"),
        ("iPatcher", "exploit3dguy · xerub", "https://github.com/exploit3dguy/iPatcher"),
        ("Kernel64Patcher / seprmvr64", "Ralph0045 · y08wilmarchive · mineek · xerub · Ploosh", "https://github.com/y08wilmarchive/Kernel64Patcher"),
        ("img4lib", "xerub · LukeZGD", "https://github.com/LukeZGD/img4lib"),
        ("kerneldiff", "xerub · LukeZGD", "https://gist.github.com/LukeZGD/8c719b613ca28d6883552437bdd500de"),
        ("tsschecker", "tihmstar · 1Conan", "https://github.com/1Conan/tsschecker")
        ,("SCS WiFi Fix", "DevTweaker", "https://github.com/DevTweaker/Tweak")
        ,("Fiona", "julioverne", "https://julioverne.github.io/")
        ,("PreferenceLoader", "Dustin Howett · Sam Bingner", "https://github.com/sbingner/preferenceloader")
        ,("Pangu / Cydia / Substrate bootstrap", "Pangu Team · Jay Freeman (saurik) · Legacy-iOS-Kit contributors", "https://github.com/LukeZGD/Legacy-iOS-Kit")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("credits")).font(.title2.bold())
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("@criss.repair_").font(.headline)
                    Text(model.t("codexCredit")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: URL(string: "https://www.youtube.com/@CrissRepair")!) {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                }.buttonStyle(.borderedProminent).tint(.red)
            }
            Text(model.t("creditsBody")).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(projects, id: \.0) { project in
                        VStack(alignment: .leading, spacing: 3) {
                            Link(project.0, destination: URL(string: project.2)!).fontWeight(.semibold)
                            Text(project.1).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(model.t("openLicenses")) { NSWorkspace.shared.open(model.resources.appendingPathComponent("Licenses")) }
                Spacer(); Button(model.t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 600, height: 590)
    }
}
