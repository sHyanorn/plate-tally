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
        SignedNumber(sign: estimateSign(kcal), value: kcal, text: wholeKcal(kcal), spoken: kcalText(kcal), role: role)
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

/// The background of a card in a list: the surface, rounded 28, inside the margins of the screen.
struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.cardRadius)
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
    func cardListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Metrics.margin, bottom: 0, trailing: Metrics.margin))
            .listRowSeparator(.hidden)
            .listRowBackground(CardBackground())
    }

    /// The padding of content on a card: 16 pt above and below, 20 pt at the sides.
    func cardPadding() -> some View {
        padding(.vertical, 16).padding(.horizontal, 20)
    }
}

/// A fully round button 58 pt high, filled with ink. A press shrinks it to 97% with a short spring, or only
/// fades it with Reduce Motion.
struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .textRole(.button)
            .lineLimit(1)
            .padding(.horizontal, 22)
            .frame(minHeight: Metrics.pillHeight)
            .foregroundStyle(Palette.onInk)
            .background(Palette.ink, in: .capsule)
            .contentShape(.capsule)
            .opacity(isEnabled ? (pressed && reduceMotion ? 0.7 : 1) : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? Animation.easeInOut(duration: 0.15) : .spring(duration: 0.2, bounce: 0.3),
                value: pressed)
    }
}
