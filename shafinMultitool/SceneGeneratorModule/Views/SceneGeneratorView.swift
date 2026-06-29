//
//  SceneGeneratorView.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI

struct SceneGeneratorView: View {
    @StateObject private var viewModel: SceneGeneratorViewModel
    @Environment(\.dismiss) private var dismiss

    init(projectName: String = "Новая сцена", isNewProject: Bool = true) {
        _viewModel = StateObject(
            wrappedValue: SceneGeneratorViewModel(projectName: projectName, isNewProject: isNewProject)
        )
    }

    var body: some View {
        LegacySceneGeneratorCameraShell(viewModel: viewModel) {
            viewModel.persistWorkspaceState()
            dismiss()
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.prepareWorkspace()
        }
        .onDisappear {
            viewModel.persistWorkspaceState()
        }
        .sheet(isPresented: $viewModel.showInputSheet) {
            SceneInputSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showMarkerNameInput) {
            MarkerNameInputSheet(
                onCancel: {
                    viewModel.cancelMarkerCreation()
                },
                onSave: { name in
                    viewModel.createMarker(withName: name)
                },
                shouldCancelOnDisappear: {
                    viewModel.pendingMarkerPosition != nil
                }
            )
                .presentationDetents([.height(170)])
                .presentationDragIndicator(.visible)
        }
        .alert("Ошибка", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }
}

struct MarkerNameInputSheet: View {
    let onCancel: () -> Void
    let onSave: (String) -> Void
    let shouldCancelOnDisappear: () -> Bool

    @State private var markerName: String = ""
    @State private var didFinishExplicitly = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Название", text: $markerName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(saveMarkerIfPossible)

                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Маркер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        didFinishExplicitly = true
                        onCancel()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveMarkerIfPossible()
                    }
                    .disabled(markerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
        .onDisappear {
            if !didFinishExplicitly && shouldCancelOnDisappear() {
                onCancel()
            }
        }
    }

    private func saveMarkerIfPossible() {
        let trimmedName = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        didFinishExplicitly = true
        onSave(trimmedName)
        markerName = ""
    }
}

#if DEBUG
struct SceneGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        SceneGeneratorView()
    }
}
#endif
