import SwiftUI

struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCode: String
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

    private var filteredCommon: [SupportedCurrency] {
        commonCurrencies.filter { matches($0) }
    }

    private var filteredOther: [SupportedCurrency] {
        otherCurrencies.filter { matches($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    searchBar

                    if !filteredCommon.isEmpty {
                        currencySection(title: "Common", currencies: filteredCommon)
                    }

                    if !filteredOther.isEmpty {
                        currencySection(title: "Other", currencies: filteredOther)
                    }

                    if filteredCommon.isEmpty && filteredOther.isEmpty {
                        Text("No currencies match \"\(searchText)\"")
                            .font(Fonts.body(15))
                            .foregroundStyle(Color.textMuted)
                            .padding(.top, Spacing.xl)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .keyboardDoneToolbar()
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

    private func currencySection(title: String, currencies: [SupportedCurrency]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Fonts.caption(13))
                .foregroundStyle(Color.textSecondary)
                .padding(.leading, Spacing.xs)

            VStack(spacing: 0) {
                ForEach(currencies) { currency in
                    currencyRow(currency)
                }
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.borderColor, lineWidth: 1)
            )
        }
    }

    private func currencyRow(_ currency: SupportedCurrency) -> some View {
        let isSelected = currency.code == selectedCode
        let symbol = CurrencyFormatter.shared.symbol(for: currency.code)

        return Button {
            selectedCode = currency.code
            dismiss()
        } label: {
            HStack(spacing: Spacing.smd) {
                Text(currency.flag)
                    .font(.system(size: 20))

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
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 52)
            .background(isSelected ? Color.brandTint : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
