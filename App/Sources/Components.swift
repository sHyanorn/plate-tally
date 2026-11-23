import Core
import SwiftUI

/// A number with its sign raised in front of it, as on a price tag: "≈" for an estimate, "=" for a conversion.
/// VoiceOver and the tests read it as one text, "≈ 656 kcal". A change of the number rolls its digits, or
/// fades it with Reduce Motion.
struct SignedNumber: View {
    let sign: String
    let value: Double
    let text: String
    let spoken: String

    @ScaledMetric private var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(sign: String, value: Double, text: String, spoken: String, role: TextRole) {
        self.sign = sign
        self.value = value
        self.text = text
        self.spoken = spoken
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.style)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            if !sign.isEmpty {
                Text(sign)
                    .font(.system(size: max(size * 0.4, 13), weight: .heavy, design: .rounded))
                    .padding(.top, size * 0.12)
            }
            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(reduceMotion ? ContentTransition.opacity : .numericText(value: value))
        }
        .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : .snappy, value: value)
        .accessibilityRepresentation { Text(spoken) }
    }
}

/// The energy of a day or a meal: the sign and a whole number of kcal, read as "≈ 656 kcal" (R9).
struct KcalNumber: View {
    let kcal: Double
    let role: TextRole

    var body: some View {
        SignedNumber(sign: estimateSign(kcal), value: kcal, text: wholeNumber(kcal), spoken: kcalText(kcal), role: role)
    }
}

/// The moss price tag of an energy: the punched hole, the label and the unit, the number below. The number
/// carries the identifier, because it is what a test reads.
struct EnergyTag: View {
    let label: LocalizedStringKey
    let kcal: Double
    let numberID: String
    /// The height inside the 18 pt padding.
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.canvas.shadow(.inner(color: .black.opacity(0.3), radius: 1, y: 1.5)))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(label).textRole(.label)
                Spacer(minLength: 4)
                Text(verbatim: "kcal").textRole(.unit).accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            KcalNumber(kcal: kcal, role: .tagNumber).accessibilityIdentifier(numberID)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .leading)
        .padding(18)
        .foregroundStyle(Palette.onMoss)
        .background(Palette.moss, in: .rect(cornerRadius: Metrics.tagRadius))
    }
}

/// The background of a card in a list: the surface, rounded 28, inside the margins of the screen. Rows that
/// make one card together leave the corners square where they meet.
struct CardBackground: View {
    var roundsTop = true
    var roundsBottom = true

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: roundsTop ? Metrics.cardRadius : 0,
            bottomLeadingRadius: roundsBottom ? Metrics.cardRadius : 0,
            bottomTrailingRadius: roundsBottom ? Metrics.cardRadius : 0,
            topTrailingRadius: roundsTop ? Metrics.cardRadius : 0
        )
        .fill(Palette.surface)
        .padding(.horizontal, Metrics.margin)
    }
}

extension View {
    /// A list row without a card: within the margins of the screen, no separator, the canvas behind it.
    func plainListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Metrics.margin, bottom: 0, trailing: Metrics.margin))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A list row on a card of its own, within the margins of the screen. The content pads itself, so that a
    /// button fills the whole card.
    func cardListRow(roundsTop: Bool = true, roundsBottom: Bool = true) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Metrics.margin, bottom: 0, trailing: Metrics.margin))
            .listRowSeparator(.hidden)
            .listRowBackground(CardBackground(roundsTop: roundsTop, roundsBottom: roundsBottom))
    }

    /// The padding of content on a card: 16 pt above and below, 20 pt at the sides.
    func cardPadding() -> some View {
        padding(.vertical, 16).padding(.horizontal, 20)
    }
}

/// A fully round button 58 pt high. The primary one is filled with ink, the quiet one is the surface with an
/// outline. A press shrinks it to 97% with a short spring, or only fades it with Reduce Motion.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case quiet
    }

    var kind = Kind.primary

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .textRole(.button)
            .lineLimit(1)
            .padding(.horizontal, 22)
            .frame(minHeight: Metrics.pillHeight)
            .foregroundStyle(kind == .primary ? Palette.onInk : Palette.ink)
            .background(kind == .primary ? Palette.ink : Palette.surface, in: .capsule)
            .overlay {
                if kind == .quiet { Capsule().strokeBorder(Palette.line, lineWidth: 1.5) }
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? (pressed && reduceMotion ? 0.7 : 1) : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? Animation.easeInOut(duration: 0.15) : .spring(duration: 0.2, bounce: 0.3),
                value: pressed)
    }
}

/// The top of a sheet: its title, 28 pt heavy, and one control at the trailing end. It stays in place above the
/// content, so the control is in reach whatever the content scrolls to.
struct SheetHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let titleID: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .textRole(.sheetTitle)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleID)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 22)
        .padding(.bottom, 12)
        .padding(.horizontal, Metrics.margin)
        .background(Palette.canvas)
    }
}

/// The round button that closes a sheet without saving.
struct CloseButton: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(.body, design: .rounded, weight: .bold))
                .frame(width: side, height: side)
                .background(Palette.surface2, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// A field on a card of its own: the label above, the field below, an ink outline while it has the focus.
struct InputCard<Content: View>: View {
    let label: LocalizedStringKey
    let focused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textRole(.caption).foregroundStyle(Palette.ink2)
            content
        }
        .inputCardStyle(focused: focused)
    }
}

extension View {
    func inputCardStyle(focused: Bool) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Palette.surface, in: .rect(cornerRadius: Metrics.inputRadius))
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Metrics.inputRadius).strokeBorder(Palette.ink, lineWidth: 2)
                }
            }
    }

    /// A sheet of the design: the canvas behind it, 38 pt corners, the large detent only.
    func designSheet() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Metrics.sheetRadius)
            .presentationBackground(Palette.canvas)
    }
}

/// A problem of a form in its three parts (R26), in ink: the design has no alarm colour.
struct ProblemText: View {
    let problem: Problem

    var body: some View {
        Label(problem.message, systemImage: "exclamationmark.circle")
            .textRole(.caption)
            .padding(.horizontal, 4)
    }
}
