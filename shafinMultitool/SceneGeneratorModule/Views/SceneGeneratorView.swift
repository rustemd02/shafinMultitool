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
            MarkerNameInputSheet(viewModel: viewModel)
                .presentationDetents([.height(220)])
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
    @ObservedObject var viewModel: SceneGeneratorViewModel
    @State private var markerName: String = ""

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Как назвать объект?")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Например: шкаф, стол или стойка. Это имя используется для привязки реального объекта к описанию сцены.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                TextField("Шкаф", text: $markerName)
                    .textFieldStyle(.roundedBorder)

                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Новый маркер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        viewModel.cancelMarkerCreation()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        viewModel.createMarker(withName: markerName)
                        markerName = ""
                    }
                    .disabled(markerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onDisappear {
            if viewModel.pendingMarkerPosition != nil {
                viewModel.cancelMarkerCreation()
            }
        }
    }
}

#if DEBUG
struct SceneGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        SceneGeneratorView()
    }
}
#endif
