//
//  ProControlsPanelView.swift
//  shafinMultitool
//
//  M9-016: the single SET OS-compliant Pro Controls layer inside the
//  existing Camera Coach screen (no second camera screen/session).
//  Contract-driven rows; capability tier and read-back values only;
//  SET tokens exclusively (HUD scrim, hairline, single accent).
//

import SwiftUI

struct ProControlsPanelView: View {
    let rows: [ProControlRow]
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.proControlsTitle.localizedString(locale: locale))
                .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.title, relativeTo: .headline))
                .foregroundStyle(.setTextPrimary)

            ForEach(rows) { row in
                ProControlRowView(row: row, locale: locale)
            }
        }
        .padding(SETSpacing.x3)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.setHUDScrim)
        .overlay {
            RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                .strokeBorder(.setHairline, lineWidth: SETStroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_controls_panel")
    }
}

private struct ProControlRowView: View {
    let row: ProControlRow
    let locale: Locale

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            tierDot
            VStack(alignment: .leading, spacing: 2) {
                nameText
                tierLabel
            }
            Spacer(minLength: SETSpacing.x2)
            valueText
        }
        .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.nameKey.localizedString(locale: locale))
        .accessibilityValue(row.accessibilityValueText)
        .accessibilityIdentifier("pro_control_\(row.id)")
    }

    private var tierDot: some View {
        Circle()
            .fill(row.availability == .available ? Color.setOrange : Color.setTextTertiary)
            .frame(width: 6, height: 6)
    }

    private var nameText: some View {
        Text(row.nameKey.localizedString(locale: locale))
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
            .foregroundStyle(.setTextPrimary)
    }

    private var tierLabel: some View {
        Text(ProControlsPresentation.tierText(row.availability))
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.micro, relativeTo: .caption2))
            .foregroundStyle(.setTextSecondary)
    }

    private var valueText: some View {
        Text(row.valueText ?? "—")
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
            .monospacedDigit()
            .foregroundStyle(row.valueText == nil ? Color.setTextTertiary : Color.setTextPrimary)
    }
}
