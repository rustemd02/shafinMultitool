//
//  ZoomControlView.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct ZoomControlView: View {
    let availableLenses: [CameraLens]
    let currentLens: CameraLens
    let onLensChange: (CameraLens) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(availableLenses, id: \.self) { lens in
                ZoomButton(
                    lens: lens,
                    isSelected: lens == currentLens,
                    action: { onLensChange(lens) }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }
}

private struct ZoomButton: View {
    let lens: CameraLens
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(lens.displayName)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .black : .white)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    Circle()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.2))
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            ZoomControlView(
                availableLenses: [.ultraWide, .wide, .telephoto2x, .telephoto3x],
                currentLens: .wide,
                onLensChange: { lens in
                    print("Selected: \(lens.displayName)")
                }
            )
            .padding(.bottom, 40)
        }
    }
}


