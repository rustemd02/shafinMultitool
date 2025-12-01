//
//  StageSelectionViewController.swift
//  shafinMultitool
//
//  Created on 15.11.2025.
//

import UIKit
import SwiftUI

// MARK: - SwiftUI View
struct StageSelectionView: View {
    @Environment(\.presentationMode) var presentationMode

    let onPreProductionTapped: () -> Void
    let onFilmingTapped: () -> Void
    let onSceneGeneratorTapped: () -> Void

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                Text("Выберите стадию")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 20)
                    .padding(.bottom, 40)

                // Cards
                HStack(spacing: 20) {
                    StageCard(
                        title: "Пре-продакшен",
                        subtitle: "Планирование и подготовка",
                        emoji: "📋",
                        gradientColors: [
                            Color(red: 0.4, green: 0.6, blue: 1.0),
                            Color(red: 0.2, green: 0.4, blue: 0.8)
                        ]
                    ) {
                        onPreProductionTapped()
                    }

                    StageCard(
                        title: "Съёмка",
                        subtitle: "Процесс съёмки",
                        emoji: "🎥",
                        gradientColors: [
                            Color(red: 1.0, green: 0.4, blue: 0.5),
                            Color(red: 0.8, green: 0.2, blue: 0.3)
                        ]
                    ) {
                        onFilmingTapped()
                    }

                    StageCard(
                        title: "Scene Generator",
                        subtitle: "Генерация сцен из текста",
                        emoji: "✨",
                        gradientColors: [
                            Color(red: 0.6, green: 0.4, blue: 1.0),
                            Color(red: 0.4, green: 0.2, blue: 0.8)
                        ]
                    ) {
                        onSceneGeneratorTapped()
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
}

// MARK: - Stage Card Component
struct StageCard: View {
    let title: String
    let subtitle: String
    let emoji: String
    let gradientColors: [Color]
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                // Background with gradient
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: gradientColors[0].opacity(0.5),
                        radius: isPressed ? 8 : 20,
                        x: 0,
                        y: isPressed ? 4 : 10
                    )

                // Overlay shine effect
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    // Иконка слева сверху
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 50, height: 50)

                            Text(emoji)
                                .font(.system(size: 28))
                        }

                        Spacer()
                    }

                    Spacer()

                    // Текст растянут на всю ширину
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            // .frame(height: 140)
        }
        .buttonStyle(CardButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - Button Style
struct CardButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                isPressed = newValue
            }
    }
}

// MARK: - UIKit Wrapper
class StageSelectionViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let swiftUIView = StageSelectionView(
            onPreProductionTapped: { [weak self] in
                self?.preProductionTapped()
            },
            onFilmingTapped: { [weak self] in
                self?.filmingTapped()
            },
            onSceneGeneratorTapped: { [weak self] in
                self?.sceneGeneratorTapped()
            }
        )
        let hostingController = UIHostingController(rootView: swiftUIView)

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
    }

    private func preProductionTapped() {
        let vc = SOModuleBuilder.build()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func filmingTapped() {
        let contentView = ContentView()
        let hostingController = LandscapeHostingController(rootView: contentView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }
    
    private func sceneGeneratorTapped() {
        let sceneGeneratorView = SceneGeneratorView()
        let hostingController = LandscapeHostingController(rootView: sceneGeneratorView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }
}

// MARK: - Landscape Hosting Controller
class LandscapeHostingController<Content: View>: UIHostingController<Content> {
}
