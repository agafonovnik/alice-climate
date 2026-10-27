import AppKit
import SwiftUI
import ClimateCore

private let accent = Color(red: 0.55, green: 0.36, blue: 0.95)

struct ClimateMenu: View {
    @ObservedObject var store: ClimateStore
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.isDemo ? "ДЕМОНСТРАЦИОННЫЕ ДАННЫЕ" : "ДОМ С АЛИСОЙ")
                        .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(accent)
                    Text("Климат дома").font(.system(size: 23, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button { Task { await store.refresh() } } label: {
                    if store.isRefreshing { ProgressView().controlSize(.small).frame(width: 18, height: 18) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .medium)).frame(width: 18, height: 18) }
                }
                .buttonStyle(.borderless).disabled(store.isRefreshing || store.isConnecting || !store.hasToken)
                .help("Обновить показания").accessibilityLabel("Обновить показания")
            }

            if !store.hasToken && !store.isDemo {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "thermometer.medium").font(.system(size: 30)).foregroundStyle(accent)
                    Text("Ваш дом — одним взглядом").font(.headline)
                    Text("Подключите Яндекс, чтобы видеть температуру и влажность прямо в строке меню.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Подключить Яндекс", action: openSettings).buttonStyle(.borderedProminent).tint(accent)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            } else if store.isRefreshing && store.lastSync == nil {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Получаем показания…") }.padding(.vertical, 24)
            } else if store.readings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Датчики пока не найдены").font(.headline)
                    Text("Проверьте, что в этом аккаунте в «Доме с Алисой» есть устройства с температурой или влажностью.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Настройки подключения", action: openSettings)
                }.padding(.vertical, 10)
            } else {
                if let reading = store.selected {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Circle().fill(reading.online ? accent : Color.orange).frame(width: 6, height: 6)
                            Menu {
                                ForEach(store.readings) { sensor in
                                    Button {
                                        store.selectedID = sensor.id
                                    } label: {
                                        if sensor.id == store.selected?.id {
                                            Label(sensor.room.isEmpty ? sensor.name : "\(sensor.room) — \(sensor.name)", systemImage: "checkmark")
                                        } else {
                                            Text(sensor.room.isEmpty ? sensor.name : "\(sensor.room) — \(sensor.name)")
                                        }
                                    }
                                }
                            } label: {
                                Text(reading.room.isEmpty ? reading.name : reading.room)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel("Выбрать комнату для строки меню")
                            Spacer()
                            Text(reading.online ? "В СТРОКЕ МЕНЮ" : "НЕТ СВЯЗИ")
                                .font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                        }
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            HStack(alignment: .top, spacing: 0) {
                                MetricTile(title: "Температура", metric: reading.temperature, suffix: "°", symbol: "thermometer.medium", online: reading.online, now: context.date)
                                Rectangle().fill(Color.primary.opacity(0.09)).frame(width: 1, height: 64).padding(.horizontal, 16)
                                MetricTile(title: "Влажность", metric: reading.humidity, suffix: "%", symbol: "humidity", online: reading.online, now: context.date)
                            }
                        }
                        if !reading.online {
                            Text("Датчик не в сети. В строке меню показаны прочерки.").font(.system(size: 10)).foregroundStyle(.secondary)
                        } else if reading.isOld(at: Date()) {
                            Text("≈ Измерения старше 30 минут или время неизвестно.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(17).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    notice("Выбранный датчик больше не найден. Выберите другой ниже.")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("ВАШИ ДАТЧИКИ").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(store.readings) { reading in
                                Button { store.selectedID = reading.id } label: {
                                    SensorRow(reading: reading, selected: store.selected?.id == reading.id)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    // A maximum alone gives ScrollView a near-zero ideal height inside NSPopover.
                    // Reserve actual row space so async arrivals cannot collapse the list.
                    .frame(height: min(CGFloat(store.readings.count) * 56, 224))
                }
            }
            if let error = store.error { notice(error) }
            if let warning = store.partialWarning { notice(warning) }
            Divider()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isDemo ? "Демо · без подключения к аккаунту" : "Обновление каждую минуту")
                    if let last = store.lastSync {
                        Text("Синхронизация: \(last.formatted(date: .omitted, time: .shortened))")
                    }
                }.font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 14)) }
                    .buttonStyle(.borderless).help("Настройки").accessibilityLabel("Настройки")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power").font(.system(size: 14)) }
                    .buttonStyle(.borderless).help("Завершить приложение").accessibilityLabel("Завершить приложение")
            }
        }
        .padding(20).frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11)).foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct MetricTile: View {
    let title: String
    let metric: Metric?
    let suffix: String
    let symbol: String
    let online: Bool
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(online ? metric?.formatted(suffix: suffix) ?? "—" : "—")
                .font(.system(size: 33, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(online ? metric?.ageDescription(at: now) ?? "нет показаний" : "датчик не в сети")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SensorRow: View {
    let reading: ClimateReading
    let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reading.online ? "sensor" : "wifi.slash")
                .font(.system(size: 15)).foregroundStyle(reading.online ? accent : .secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.room.isEmpty ? reading.name : reading.room).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(reading.room.isEmpty ? "Без комнаты" : reading.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(reading.online ? "\(reading.temperature?.formatted(suffix: "°") ?? "—") · \(reading.humidity?.formatted(suffix: "%") ?? "—")" : "Нет связи")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                if reading.online { Text(reading.measurementDescription(at: Date())).font(.system(size: 8)).foregroundStyle(.secondary) }
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? accent : Color.primary.opacity(0.18)).font(.system(size: 13))
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(selected ? accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ConnectionSettings: View {
    @ObservedObject var store: ClimateStore
    @State private var clientID = UserDefaults.standard.string(forKey: "yandexClientID") ?? ""
    @State private var tokenInput = ""
    @State private var message: String?
    @State private var success = false
    let done: () -> Void
    private var validClientID: Bool {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.count == 32 && id.allSatisfy { $0.isHexDigit }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Алиса Климат").font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Температура и влажность всегда под рукой.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "thermometer.medium").font(.system(size: 32)).foregroundStyle(accent)
                }
                if store.isDemo {
                    Label("Деморежим: подключение отключено. Перезапустите приложение без --demo для своих датчиков.", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                if store.hasToken {
                    Label("Аккаунт подключён · токен сохранён в Связке ключей", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12)).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 15) {
                    step("1", "Создайте личное приложение Яндекса", "Это однократная настройка. Название можно выбрать любое, например «Климат на Mac».")
                    Link("Создать приложение в Яндексе ↗", destination: URL(string: "https://oauth.yandex.ru/")!)
                    Text("Выберите «Для доступа к API или отладки». Redirect URI уже задан:").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text("https://oauth.yandex.ru/verification_code").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("https://oauth.yandex.ru/verification_code", forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }.help("Скопировать Redirect URI")
                    }
                    Text("В доступах добавьте iot:view — просмотр устройств умного дома.")
                        .font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                    Divider()
                    step("2", "Получите токен", "Скопируйте ClientID из свойств созданного приложения. На сайте войдите в аккаунт с вашими датчиками и разрешите просмотр.")
                    HStack {
                        TextField("ClientID приложения", text: $clientID).textFieldStyle(.roundedBorder)
                            .onChange(of: clientID) { value in UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "yandexClientID") }
                        Button("Вставить") {
                            if let text = NSPasteboard.general.string(forType: .string) {
                                clientID = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }.accessibilityLabel("Вставить ClientID из буфера")
                        Button("Получить токен") {
                            var components = URLComponents(string: "https://oauth.yandex.ru/authorize")!
                            components.queryItems = [URLQueryItem(name: "response_type", value: "token"), URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)), URLQueryItem(name: "scope", value: "iot:view")]
                            if let url = components.url { NSWorkspace.shared.open(url) }
                        }.disabled(!validClientID || store.isDemo)
                    }
                    Divider()
                    step("3", "Подключите датчики", "Вставьте выданный токен или полный адрес страницы результата. Пароль Яндекса приложению не нужен.")
                    HStack {
                        SecureField("OAuth-токен Яндекса", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("OAuth-токен Яндекса")
                            .onSubmit { connect() }
                        Button("Вставить") {
                            if let text = NSPasteboard.general.string(forType: .string) {
                                tokenInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .accessibilityLabel("Вставить токен из буфера")
                        .disabled(store.isConnecting)
                    }
                    HStack(spacing: 12) {
                        Button(store.isConnecting ? "Проверяем доступ…" : "Подключить") { connect() }
                            .buttonStyle(.borderedProminent).tint(accent)
                            .disabled(tokenInput.isEmpty || store.isConnecting || store.isRefreshing || store.isDemo)
                        if store.isConnecting { ProgressView().controlSize(.small) }
                        if store.hasToken { Button("Готово", action: done) }
                    }
                }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                if let message {
                    Label(message, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(success ? accent : Color.orange)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield").font(.system(size: 21)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Только просмотр. Без своего сервера.").font(.system(size: 12, weight: .medium))
                        Text("Токен хранится в Связке ключей macOS. Приложение обращается к официальному API Яндекса раз в минуту и не управляет устройствами.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Link("Инструкция Яндекса ↗", destination: URL(string: "https://yandex.ru/dev/id/doc/ru/tokens/debug-token")!)
                    Spacer()
                    if store.hasToken {
                        Button("Отключить аккаунт", role: .destructive) {
                            success = false
                            message = store.disconnect()
                            tokenInput = ""
                        }.disabled(store.isConnecting)
                    }
                }.font(.system(size: 11))
            }.padding(28)
        }.frame(width: 600, height: 700).background(Color(nsColor: .windowBackgroundColor))
    }
    private func connect() {
        guard !store.isDemo, !store.isConnecting, !store.isRefreshing, !tokenInput.isEmpty else { return }
        success = false; message = nil
        Task {
            if let error = await store.connect(input: tokenInput) { message = error }
            else {
                tokenInput = ""
                success = true
                message = store.readings.isEmpty ? "Подключено, но датчики температуры или влажности не найдены. Проверьте аккаунт." : "Подключено! Показания уже доступны в строке меню."
            }
        }
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number).font(.system(size: 11, weight: .bold)).foregroundStyle(accent)
                .frame(width: 23, height: 23).background(accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
