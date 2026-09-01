struct CameraUITestState {
    let isEnabled: Bool
    let cameraState: CameraSessionController.State?

    init(processEnvironment: [String: String]) {
        let requestedState = processEnvironment["AICAMERA_UI_TEST_STATE"]
        isEnabled = requestedState != nil
        if requestedState == "unauthorized" {
            cameraState = .unauthorized
        } else if requestedState == "running" {
            cameraState = .running
        } else {
            cameraState = nil
        }
    }
}
