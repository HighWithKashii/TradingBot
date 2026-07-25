import SwiftUI

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = JournalViewModel()

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                factorsCard
                moodCard
                saveButton
                historyCard
            }
            .padding(.vertical, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Journal")
        .onAppear { viewModel.load(modelContext: modelContext) }
    }

    private var factorsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Heute")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(JournalFactor.allCases) { factor in
                        FactorChip(
                            factor: factor,
                            isSelected: viewModel.selectedFactors.contains(factor)
                        ) {
                            viewModel.toggle(factor)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var moodCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Stimmung")
                HStack(spacing: 14) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            HapticManager.selection()
                            viewModel.moodRating = rating
                        } label: {
                            Text(moodEmoji(rating))
                                .font(.system(size: 30))
                                .opacity(viewModel.moodRating == rating ? 1 : 0.35)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var saveButton: some View {
        Button {
            viewModel.saveTodayEntry(modelContext: modelContext)
        } label: {
            Text("Eintrag speichern")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.recoveryGreen))
        }
        .padding(.horizontal)
    }

    private var historyCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Verlauf")
                ForEach(viewModel.entries.prefix(10)) { entry in
                    HStack {
                        Text(entry.date.dayMonthLabel)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(Array(entry.factors).prefix(3)) { factor in
                                Image(systemName: factor.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func moodEmoji(_ rating: Int) -> String {
        ["😞", "🙁", "😐", "🙂", "😄"][max(0, min(4, rating - 1))]
    }
}

private struct FactorChip: View {
    let factor: JournalFactor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: factor.systemImage)
                    .font(.system(size: 18))
                Text(factor.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(isSelected ? Color.black : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.recoveryGreen : Color.cardBackgroundElevated)
            )
        }
    }
}

#Preview {
    NavigationStack {
        JournalView()
    }
    .preferredColorScheme(.dark)
    .modelContainer(for: [JournalEntry.self], inMemory: true)
}
