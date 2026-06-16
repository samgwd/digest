import CarPlay

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var carPlayManager: CarPlayManager?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        let manager = CarPlayManager(interfaceController: interfaceController)
        self.carPlayManager = manager
        Task { @MainActor in
            manager.configure()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        carPlayManager = nil
    }
}
