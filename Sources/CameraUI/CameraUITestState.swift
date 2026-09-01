struct CameraUITestState {
    let isEnabled: Bool
    let cameraState: CameraSessionController.State?

    init(requestedState: String?) {
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
