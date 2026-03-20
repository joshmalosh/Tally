import SwiftUI

struct CurrencySetupView: View {
    @Environment(AppState.self) private var appState
    var onComplete: (() -> Void)? = nil
    @State private var selectedCode = "USD"
    @State private var searchText = ""

    private var commonCurrencies: [SupportedCurrency] {
        CurrencyFormatter.supportedCurrencies
            .filter { CurrencyFormatter.commonCurrencyCodes.contains($0.code) }
            .sorted { $0.code < $1.code }
    }

    private var otherCurrencies: [SupportedCurrency] {
        CurrencyFormatter.supportedCurrencies
            .filter { !CurrencyFormatter.commonCurrencyCodes.contains($0.code) }
            .sorted { $0.name < $1.name }
    }

    private func matches(_ currency: SupportedCurrency) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return currency.code.lowercased().contains(query)
            || currency.name.lowercased().contains(query)
    }

    private var filteredCommon: [SupportedCurrency] { commonCurrencies.filter { matches($0) } }
    private var filteredOther: [SupportedCurrency] { otherCurrencies.filter { matches($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.md)

            searchBar
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if !filteredCommon.isEmpty {
                        currencySection(currencies: filteredCommon)
                    }
                    if !filteredOther.isEmpty {
                        currencySection(currencies: filteredOther)
                    }
                    if filteredCommon.isEmpty && filteredOther.isEmpty {
                        Text("No currencies match \"\(searchText)\"")
                            .font(Fonts.body(15))
                            .foregroundStyle(Color.textMuted)
                            .padding(.top, Spacing.xl)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, 100)
            }

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Divider()
                PrimaryButton(title: "Continue") {
                    appState.defaultCurrency = selectedCode
                    onComplete?()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .background(Color.bgPrimary)
        }
        .background(Color.bgPrimary)
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Text("Choose your currency")
                .font(Fonts.brand(24))
                .foregroundStyle(Color.textPrimary)

            Text("This will be the default for new expenses. You can always change it per expense or update it later in Settings.")
                .font(Fonts.body(15))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.textMuted)

            TextField("Search currencies", text: $searchText)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 44)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.borderColor, lineWidth: 1)
        )
    }

    private func currencySection(currencies: [SupportedCurrency]) -> some View {
        VStack(spacing: 0) {
            ForEach(currencies) { currency in
                currencyRow(currency)

                if currency.id != currencies.last?.id {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.borderColor, lineWidth: 1)
        )
    }

    private func currencyRow(_ currency: SupportedCurrency) -> some View {
        let isSelected = currency.code == selectedCode
        let symbol = CurrencyFormatter.shared.symbol(for: currency.code)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCode = currency.code }
        } label: {
            HStack(spacing: Spacing.smd) {
                Text(currency.flag)
                    .font(.system(size: 22))

                VStack(alignment: .leading, spacing: 1) {
                    Text(currency.code)
                        .font(Fonts.label(15))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(currency.name) (\(symbol))")
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.brandPrimary)
                } else {
                    Circle()
                        .stroke(Color.borderColor, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 56)
            .background(isSelected ? Color.brandTint : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
